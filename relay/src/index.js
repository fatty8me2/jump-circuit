import { DurableObject } from "cloudflare:workers";

const ROOM_CODE = /^[A-HJ-NP-Z2-9]{8}$/;
const MAX_PLAYERS = 8;
const MAX_MESSAGE_BYTES = 16 * 1024;
const HOST_EVENTS = new Set(["roster", "kick", "start_race", "return_lobby", "pong"]);
const PLAYER_EVENTS = new Set(["register", "ping", "pose", "checkpoint", "finished"]);

export default {
	async fetch(request, env) {
		const url = new URL(request.url);
		if (url.pathname === "/health") {
			return Response.json({ ok: true, service: "jump-circuit-relay" });
		}
		if (url.pathname !== "/ws") {
			return new Response("Not found", { status: 404 });
		}
		if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
			return new Response("WebSocket upgrade required", { status: 426 });
		}

		const code = (url.searchParams.get("room") ?? "").toUpperCase();
		const role = url.searchParams.get("role");
		if (!ROOM_CODE.test(code) || (role !== "host" && role !== "join")) {
			return new Response("Invalid room code or role", { status: 400 });
		}

		const id = env.ROOMS.idFromName(code);
		return env.ROOMS.get(id).fetch(request);
	},
};

export class RaceRoom extends DurableObject {
	async fetch(request) {
		const url = new URL(request.url);
		const role = url.searchParams.get("role");
		const code = (url.searchParams.get("room") ?? "").toUpperCase();
		const sockets = this.ctx.getWebSockets();
		const members = sockets.map((socket) => ({ socket, ...socket.deserializeAttachment() }));
		const host = members.find((member) => member.id === 1);
		let peerId = 0;
		let error = "";

		if (role === "host") {
			if (members.length > 0) {
				error = "That room code is already in use. Host another race to get a new code.";
			} else {
				peerId = 1;
			}
		} else if (role === "join") {
			if (host == null) {
				error = "Room not found. Check the code and make sure the host is still in the lobby.";
			} else if (members.length >= MAX_PLAYERS) {
				error = `That race is full (${members.length}/${MAX_PLAYERS}).`;
			} else {
				const occupied = new Set(members.map((member) => member.id));
				for (let candidate = 2; candidate <= MAX_PLAYERS; candidate += 1) {
					if (!occupied.has(candidate)) {
						peerId = candidate;
						break;
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
		server.serializeAttachment({ id: peerId, role, code });

		if (error !== "") {
			server.send(JSON.stringify({ type: "error", reason: error }));
			server.close(4000, "Room unavailable");
		} else {
			server.send(JSON.stringify({ type: "welcome", id: peerId, room: code }));
		}

		return new Response(null, { status: 101, webSocket: client });
	}

	async webSocketMessage(socket, rawMessage) {
		const sender = socket.deserializeAttachment();
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
		for (const member of this.ctx.getWebSockets()) {
			if (member === socket) continue;
			const target = member.deserializeAttachment();
			if (to !== null && target.id !== to) continue;
			try {
				member.send(outgoing);
			} catch {
				// Close handling removes stale sockets and notifies the room.
			}
		}
	}

	async webSocketClose(socket, code, reason) {
		const member = socket.deserializeAttachment();
		if (member.id === 1) {
			for (const other of this.ctx.getWebSockets()) {
				if (other === socket) continue;
				try {
					other.send(JSON.stringify({ type: "closed", reason: "The host closed the session." }));
					other.close(4001, "Host left");
				} catch {
					// A disconnected client may already have closed its socket.
				}
			}
		} else if (member.id > 1) {
			const message = JSON.stringify({ type: "peer_left", id: member.id });
			for (const other of this.ctx.getWebSockets()) {
				if (other === socket) continue;
				try {
					other.send(message);
				} catch {
					// A disconnected client may already have closed its socket.
				}
			}
		}
		socket.close(code, reason);
	}

	async webSocketError(socket) {
		try {
			socket.close(1011, "Relay error");
		} catch {
			// Socket is already gone.
		}
	}
}
