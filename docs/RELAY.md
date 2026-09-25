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
with the code can join while the host is in the lobby, so share it with your group. Rooms do not
persist between sessions.

## Dropped connections (reconnect and resume)

Every connection carries a secret session token (`&session=`, 24 hex characters). If a socket
closes without a clean close (code 1000), the relay holds that player's slot instead of announcing
them gone: **20 s for a racer, 30 s for the host**. It tells the room `peer_away` / `host_away`,
and the game reconnects on its own with `role=rejoin&id=<slot>&session=<token>`. On success, the
relay replies `welcome` with `resumed: true`, tells the room `peer_back` / `host_back`, and
everything carries on: roster, race, clock. The HUD and lobby show "Connection lost -
reconnecting..." / "Reconnected", and name whoever dropped.
* A slot whose grace runs out is announced with `peer_left`. A host who never returns closes the
  room (`closed`, then close code 4001).
* A clean leave (close code 1000) is announced at once.
* If Cloudflare restarts the room and drops every socket without close events, the relay notices
  the missing members on the next connection and gives them the same grace.
* The game treats 45 s with nothing from the relay (not even a keepalive answer) as a dead link
  and reconnects.
* Close codes and reconnects are printed to the game's log (`[relay] ...` lines in
  `%APPDATA%\Godot\app_userdata\Jump Circuit\logs\godot.log`).

Poses are sent at most 15 times a second, and a racer standing still sends only a 1 s heartbeat.
Every incoming WebSocket message counts against the Durable Objects request budget (the free
tier bills them 20:1 against its daily allowance), so this keeps long sessions with several
players well inside it.

Testing it locally: `npx wrangler dev --port 8799 --ip 127.0.0.1` in `relay/`, point
`network/relay_url` at `ws://127.0.0.1:8799` in a scratch scene, and cut a socket with
`Net._relay_socket.close(4999)`. The game should reconnect into the same slot.

The deployed Worker is `https://jump-circuit-relay.jumpcircuit.workers.dev` and its `/health` route
has returned `{"ok":true,"service":"jump-circuit-relay"}`. The project setting is configured to
use the secure WebSocket version of this endpoint. Rebuild the game before sharing it with friends.
