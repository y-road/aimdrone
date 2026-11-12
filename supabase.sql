-- AimDrone global ranking. Run this whole file once in the Supabase SQL editor.
-- One row per player (their best score). The game talks to the two functions only;
-- the table itself is closed to the public key.

create table if not exists public.aimdrone_scores (
  player_id  uuid primary key,
  name       text        not null check (char_length(name) between 1 and 16),
  score      integer     not null check (score between 0 and 50000000),
  wave       integer     not null default 0,
  kills      integer     not null default 0,
  accuracy   integer     not null default 0,
  updated_at timestamptz not null default now()
);

create index if not exists aimdrone_scores_rank
  on public.aimdrone_scores (score desc, updated_at asc);

alter table public.aimdrone_scores add column if not exists submitted_at timestamptz not null default now();

alter table public.aimdrone_scores enable row level security;
revoke all on table public.aimdrone_scores from anon, authenticated;

-- Top 100, total player count, and the caller's own rank.
create or replace function public.aimdrone_board(p_player uuid default null)
returns json
language sql
stable
security definer
set search_path = public
as $$
  with r as (
    select player_id, name, score, wave, kills,
           row_number() over (order by score desc, updated_at asc) as rnk
    from aimdrone_scores
  )
  select json_build_object(
    'total', (select count(*) from aimdrone_scores),
    'top', coalesce((
      select json_agg(json_build_object(
               'rank', t.rnk, 'name', t.name, 'score', t.score, 'wave', t.wave, 'kills', t.kills,
               'me', coalesce(t.player_id = p_player, false)) order by t.rnk)
      from (select * from r order by rnk limit 100) t), '[]'::json),
    'me', (select json_build_object('rank', rnk, 'name', name, 'score', score, 'wave', wave)
           from r where player_id = p_player)
  );
$$;

-- Save a result. Keeps the player's best score; the name can be changed any time.
create or replace function public.aimdrone_submit(
  p_player uuid, p_name text, p_score integer, p_wave integer, p_kills integer, p_acc integer)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := left(btrim(regexp_replace(coalesce(p_name, ''), '[[:cntrl:]]', '', 'g')), 16);
  v_wave  integer := coalesce(p_wave, 0);
  v_kills integer := coalesce(p_kills, 0);
  v_max_kills integer;
  v_last timestamptz;
begin
  if p_player is null then raise exception 'player required'; end if;
  if p_score is null or p_score < 0 or p_score > 50000000 then raise exception 'bad score'; end if;

  -- Plausibility checks. Scores are computed in the browser, so this cannot make cheating impossible;
  -- it only rejects numbers the game itself could never produce.
  -- Drones per wave n: min(9, 2+n) Shaheds + (n<2 ? 0 : min(8, round((n-1)*1.4))) FPVs.
  if v_wave < 0 or v_wave > 200 or v_kills < 0 then raise exception 'bad run'; end if;
  select coalesce(sum(least(9, 2 + n) + case when n < 2 then 0 else least(8, round((n - 1) * 1.4)) end), 0)
    into v_max_kills from generate_series(1, v_wave) n;
  if v_kills > v_max_kills then raise exception 'bad run'; end if;
  -- Per kill at most ~1000 points on average (long-range shots, full streak) + hit points,
  -- plus the wave-clear bonus (max 250 per wave number) and some slack.
  if p_score > v_kills * 1030 + 125 * v_wave * (v_wave + 1) + 500 then raise exception 'bad run'; end if;

  -- One submit per player every 10 s (a round lasts far longer than that).
  select submitted_at into v_last from aimdrone_scores where player_id = p_player;
  if v_last is not null and v_last > now() - interval '10 seconds' then raise exception 'too fast'; end if;
  if v_name = '' then v_name := 'PLAYER'; end if;

  insert into aimdrone_scores (player_id, name, score, wave, kills, accuracy)
  values (p_player, v_name, p_score,
          greatest(coalesce(p_wave, 0), 0), greatest(coalesce(p_kills, 0), 0),
          least(greatest(coalesce(p_acc, 0), 0), 100))
  on conflict (player_id) do update set
    name       = excluded.name,
    wave       = case when excluded.score > aimdrone_scores.score then excluded.wave     else aimdrone_scores.wave     end,
    kills      = case when excluded.score > aimdrone_scores.score then excluded.kills    else aimdrone_scores.kills    end,
    accuracy   = case when excluded.score > aimdrone_scores.score then excluded.accuracy else aimdrone_scores.accuracy end,
    updated_at = case when excluded.score > aimdrone_scores.score then now()             else aimdrone_scores.updated_at end,
    score      = greatest(aimdrone_scores.score, excluded.score),
    submitted_at = now();

  return aimdrone_board(p_player);
end;
$$;

revoke all on function public.aimdrone_board(uuid) from public;
revoke all on function public.aimdrone_submit(uuid, text, integer, integer, integer, integer) from public;
grant execute on function public.aimdrone_board(uuid) to anon, authenticated;
grant execute on function public.aimdrone_submit(uuid, text, integer, integer, integer, integer) to anon, authenticated;

-- To wipe the ranking later:  truncate table public.aimdrone_scores;

-- Remove a cheated entry by name:   delete from public.aimdrone_scores where name = 'cheat1';
-- Remove anything above a score:    delete from public.aimdrone_scores where score > 100000;
