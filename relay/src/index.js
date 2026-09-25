import { DurableObject } from "cloudflare:workers";

const ROOM_CODE = /^[A-HJ-NP-Z2-9]{8}$/;
const SESSION = /^[A-Za-z0-9]{12,64}$/;
const MAX_PLAYERS = 8;
const MAX_MESSAGE_BYTES = 16 * 1024;
const HOST_EVENTS = new Set(["roster", "kick", "start_race", "return_lobby", "pong"]);
const PLAYER_EVENTS = new Set(["register", "ping", "pose", "checkpoint", "finished"]);
// A connection that drops without a clean close (code 1000) keeps its slot this long, so the
// game can reconnect with its session token and carry on (Wi-Fi blips, ISP resets, Cloudflare
// moving the connection). Only when the grace runs out does the room hear that it left.
const PEER_GRACE_MS = 20000;
const HOST_GRACE_MS = 30000;

export default {
	async fetch(request, env) {
		const url = new URL(request.url);
		if (url.pathname === "/health") {
			return Response.json({ ok: true, service: "jump-circuit-relay", resume: true });
		}
		if (url.pathname !== "/ws") {
			return new Response("Not found", { status: 404 });
		}
		if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
			return new Response("WebSocket upgrade required", { status: 426 });
		}

		const code = (url.searchParams.get("room") ?? "").toUpperCase();
		const role = url.searchParams.get("role");
		if (!ROOM_CODE.test(code) || (role !== "host" && role !== "join" && role !== "rejoin")) {
			return new Response("Invalid room code or role", { status: 400 });
		}

		const id = env.ROOMS.idFromName(code);
		return env.ROOMS.get(id).fetch(request);
	},
};

export class RaceRoom extends DurableObject {
	/** Live members, skipping sockets that were replaced by a reconnect. */
	members() {
		return this.ctx.getWebSockets().map((socket) => ({ socket, ...socket.deserializeAttachment() }))
			.filter((member) => !member.replaced);
	}

	async away() {
		return await this.ctx.storage.get("away") ?? {};
	}

	async sessions() {
		return await this.ctx.storage.get("sessions") ?? {};
	}

	broadcast(message, except = null) {
		const text = JSON.stringify(message);
		for (const member of this.members()) {
			if (member.socket === except) continue;
			try {
				member.socket.send(text);
			} catch {
				// Close handling removes stale sockets and notifies the room.
			}
		}
	}

	async fetch(request) {
		const url = new URL(request.url);
		const role = url.searchParams.get("role");
		const code = (url.searchParams.get("room") ?? "").toUpperCase();
		const session = url.searchParams.get("session") ?? "";
		const members = this.members();
		const away = await this.away();
		const sessions = await this.sessions();
		// Members the room still knows (a session) but has neither a socket nor a grace deadline
		// for were cut off without a close event (Cloudflare restarted the room): give them the
		// same grace to reconnect as an ordinary drop.
		let reconciled = false;
		for (const id of Object.keys(sessions)) {
			if (!members.some((member) => String(member.id) === id) && away[id] == null) {
				away[id] = Date.now() + (id === "1" ? HOST_GRACE_MS : PEER_GRACE_MS);
				reconciled = true;
			}
		}
		if (reconciled) {
			await this.ctx.storage.put("away", away);
			await this.scheduleAlarm(away);
		}
		const hostPresent = members.some((member) => member.id === 1);
		const hostAway = away["1"] != null;
		let peerId = 0;
		let error = "";
		let resumed = false;

		if (role === "host") {
			if (members.length > 0 || Object.keys(away).length > 0) {
				error = "That room code is already in use. Host another race to get a new code.";
			} else {
				peerId = 1;
			}
		} else if (role === "join") {
			const occupied = new Set([...members.map((member) => member.id), ...Object.keys(away).map(Number)]);
			if (!hostPresent && hostAway) {
				error = "The host is reconnecting. Try again in a moment.";
			} else if (!hostPresent) {
				error = "Room not found. Check the code and make sure the host is still in the lobby.";
			} else if (occupied.size >= MAX_PLAYERS) {
				error = `That race is full (${occupied.size}/${MAX_PLAYERS}).`;
			} else {
				for (let candidate = 2; candidate <= MAX_PLAYERS; candidate += 1) {
					if (!occupied.has(candidate)) {
						peerId = candidate;
						break;
					}
				}
			}
		} else if (role === "rejoin") {
			const wanted = Number(url.searchParams.get("id"));
			if (!Number.isInteger(wanted) || wanted < 1 || wanted > MAX_PLAYERS || !SESSION.test(session) ||
				sessions[String(wanted)] !== session) {
				error = "Could not resume that session.";
			} else if (wanted !== 1 && !hostPresent && !hostAway) {
				error = "The room has closed.";
			} else {
				peerId = wanted;
				resumed = true;
				// the old socket may not have noticed it is dead yet: retire it quietly
				for (const member of members) {
					if (member.id === wanted) {
						member.socket.serializeAttachment({ ...member.socket.deserializeAttachment(), replaced: true });
						try { member.socket.close(4002, "Replaced by a reconnect"); } catch { }
					}
				}
			}
		} else {
			error = "Invalid room role.";
		}

		const pair = new WebSocketPair();
		const client = pair[0];
		const server = pair[1];
		this.ctx.acceptWebSocket(server);
		server.serializeAttachment({ id: peerId, role: peerId === 1 ? "host" : "join", code, session });

		if (error !== "") {
			server.send(JSON.stringify({ type: "error", reason: error }));
			server.close(4000, "Room unavailable");
		} else {
			if (SESSION.test(session)) {
				sessions[String(peerId)] = session;
				await this.ctx.storage.put("sessions", sessions);
			}
			if (resumed) {
				delete away[String(peerId)];
				await this.ctx.storage.put("away", away);
				await this.scheduleAlarm(away);
			}
			server.send(JSON.stringify({ type: "welcome", id: peerId, room: code, resumed }));
			if (resumed) {
				this.broadcast(peerId === 1 ? { type: "host_back" } : { type: "peer_back", id: peerId }, server);
			}
		}

		return new Response(null, { status: 101, webSocket: client });
	}

	async webSocketMessage(socket, rawMessage) {
		const sender = socket.deserializeAttachment();
		if (sender.replaced) return;
		let text;
		if (typeof rawMessage === "string") {
			text = rawMessage;
		} else {
			text = new TextDecoder().decode(rawMessage);
		}
		if (new TextEncoder().encode(text).byteLength > MAX_MESSAGE_BYTES) {
			socket.close(1009, "Message too large");
			return;
		}

		let packet;
		try {
			packet = JSON.parse(text);
		} catch {
			socket.close(1003, "Expected a JSON message");
			return;
		}
		if (packet?.type === "keepalive") {
			try {
				socket.send(JSON.stringify({ type: "keepalive_ack" }));
			} catch {
				socket.close(1011, "Could not acknowledge keepalive");
			}
			return;
		}
		if (packet?.type !== "event" || typeof packet.event !== "string" ||
			packet.data == null || typeof packet.data !== "object" || Array.isArray(packet.data)) {
			socket.close(1003, "Invalid message");
			return;
		}

		const event = packet.event;
		const to = packet.to == null ? null : Number(packet.to);
		if (HOST_EVENTS.has(event)) {
			if (sender.id !== 1) {
				socket.close(1008, "Host authority required");
				return;
			}
		} else if (!PLAYER_EVENTS.has(event)) {
			socket.close(1008, "Unknown event");
			return;
		}
		if ((event === "register" || event === "ping") && (sender.id === 1 || to !== 1)) {
			socket.close(1008, "Event must be sent to the host");
			return;
		}
		if ((event === "pong" || event === "kick") && (!Number.isInteger(to) || to < 2 || to > MAX_PLAYERS)) {
			socket.close(1008, "Event needs a valid target");
			return;
		}
		if ((event === "roster" || event === "start_race" || event === "return_lobby") && to !== null) {
			socket.close(1008, "Event must be broadcast");
			return;
		}
		if ((event === "pose" || event === "checkpoint" || event === "finished") && to !== null) {
			socket.close(1008, "Player event must be broadcast");
			return;
		}

		const outgoing = JSON.stringify({ type: "event", from: sender.id, event, data: packet.data });
		for (const member of this.members()) {
			if (member.socket === socket) continue;
			if (to !== null && member.id !== to) continue;
			try {
				member.socket.send(outgoing);
			} catch {
				// Close handling removes stale sockets and notifies the room.
			}
		}
	}

	async webSocketClose(socket, code, reason) {
		const member = socket.deserializeAttachment();
		try { socket.close(code, reason); } catch { }
		if (member.replaced || member.id < 1) {
			return;
		}
		// someone else already holds this slot (a reconnect beat the close): nothing left
		if (this.members().some((other) => other.socket !== socket && other.id === member.id)) {
			return;
		}
		if (code === 1000) {
			await this.depart(member.id, socket);
			return;
		}
		// an unclean drop: hold the slot for a reconnect
		const away = await this.away();
		away[String(member.id)] = Date.now() + (member.id === 1 ? HOST_GRACE_MS : PEER_GRACE_MS);
		await this.ctx.storage.put("away", away);
		await this.scheduleAlarm(away);
		this.broadcast(member.id === 1 ? { type: "host_away" } : { type: "peer_away", id: member.id }, socket);
	}

	async webSocketError(socket) {
		try {
			socket.close(1011, "Relay error");
		} catch {
			// Socket is already gone.
		}
	}

	/** A member is gone for good: tell the room (the host leaving closes it). */
	async depart(id, socket = null) {
		const sessions = await this.sessions();
		delete sessions[String(id)];
		await this.ctx.storage.put("sessions", sessions);
		if (id === 1) {
			for (const other of this.members()) {
				if (other.socket === socket) continue;
				try {
					other.socket.send(JSON.stringify({ type: "closed", reason: "The host closed the session." }));
					other.socket.close(4001, "Host left");
				} catch {
					// A disconnected client may already have closed its socket.
				}
			}
			await this.ctx.storage.deleteAll();
			return;
		}
		this.broadcast({ type: "peer_left", id }, socket);
		if (this.members().filter((m) => m.socket !== socket).length === 0 && Object.keys(await this.away()).length === 0) {
			await this.ctx.storage.deleteAll();
		}
	}

	async scheduleAlarm(away) {
		const deadlines = Object.values(away);
		if (deadlines.length === 0) {
			await this.ctx.storage.deleteAlarm();
		} else {
			await this.ctx.storage.setAlarm(Math.min(...deadlines));
		}
	}

	/** Grace ran out for anyone who did not come back. */
	async alarm() {
		const away = await this.away();
		const now = Date.now();
		const expired = Object.entries(away).filter(([, deadline]) => deadline <= now).map(([id]) => Number(id));
		for (const id of expired) {
			delete away[String(id)];
		}
		await this.ctx.storage.put("away", away);
		for (const id of expired.sort((a, b) => b - a)) {
			await this.depart(id);
			if (id === 1) return;
		}
		await this.scheduleAlarm(await this.away());
	}
}
