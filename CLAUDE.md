# AimDrone

Browser FPS: shoot down attack drones that arrive in waves. Static site, no build step.

## Files
- `index.html` — the whole game (HTML, CSS, one ES-module script). Three.js r160 is loaded from jsDelivr via an import map.
- `config.js` — Supabase URL + publishable key for the global ranking. Public values only; never commit a secret/service_role key.
- `supabase.sql` — ranking table and the two RPC functions (`aimdrone_board`, `aimdrone_submit`). Run in the Supabase SQL editor after changing it; it is safe to re-run.
- `README.md` — game description (Korean). Keep it to what the game is and how to play; no setup or deployment notes.

## Deploy
Pushing to `main` deploys automatically through the hosting provider's Git integration (framework: Other, no build command, output directory: repo root).

## Working on the game
- Sections inside the script are marked with `/* ---------- name ---------- */` comments (renderer, sky, terrain, props, particles, drones, weapon, audio, game state, ranking, shooting, input, post, hud canvas, ambience, main loop, boot).
- Many statements share long lines. Make targeted edits and keep the existing style rather than reformatting the file.
- Test hooks: `window.__game` exposes `G` (state), `P` (player), `drones`, `spawnDrone`, `begin()`, `skip()` (skip intro), `set(yaw,pitch)`, `shoot()`, `startReload()`. Setting `window.__noRender = true` before load skips rendering for fast logic tests.
- To preview locally: `npx serve .` (a plain file:// open also works, but pointer lock needs http/https in some browsers).
- UI text is English. Scores are computed client-side, so the ranking is not cheat-proof.
