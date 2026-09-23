# Online room relay

Jump Circuit now uses a Cloudflare Worker and Durable Object for room-code multiplayer. Each game
connects to the relay over WebSocket; the relay routes lobby, race and racer-pose messages between
the players in that room. Players still run the game locally and simulate their own movement.

## Local relay

From `relay/`:

```powershell
npm install
npm run dev
```

Set `network/relay_url` in `project.godot` to `ws://127.0.0.1:8787` while using the local Worker.
The Worker responds to `http://127.0.0.1:8787/health` with a small health status.

## Deploy to Cloudflare

1. Sign in once from `relay/` with `npx wrangler login`.
2. Ensure the Cloudflare account has a `workers.dev` subdomain. Wrangler links to Cloudflare's
   setup page if one has not been registered.
3. Run `npm run deploy:dry-run` to inspect the upload, then `npm run deploy`.
4. Use the deployed URL Wrangler prints. It follows the pattern
   `https://jump-circuit-relay.<account-subdomain>.workers.dev`.
5. Set `network/relay_url` in `project.godot` to that hostname with `wss://` instead of `https://`.
6. Export/build the game and send the updated game files to your friends.

The game appends `/ws` and the room code to that base URL. `/health` can be used to check the
deployed Worker in a browser. Do not include `/ws` in the setting itself.
The game and relay exchange a small application-level keepalive every 20 seconds so idle lobbies
and results screens do not lose their WebSocket connection to Cloudflare's idle timeout.

The room code is eight characters and uses letters/numbers that are easy to distinguish. Anyone
with the code can join while the host is in the lobby, so share it with your group. A room closes
when its host disconnects; rooms do not persist between sessions.

The deployed Worker is `https://jump-circuit-relay.jumpcircuit.workers.dev` and its `/health` route
has returned `{"ok":true,"service":"jump-circuit-relay"}`. The project setting is configured to
use the secure WebSocket version of this endpoint. Rebuild the game before sharing it with friends.
