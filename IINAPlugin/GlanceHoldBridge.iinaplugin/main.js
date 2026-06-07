const { console, core, event, mpv, ws } = iina;

const protocolVersion = 1;
const activeConnections = new Set();
let lastBroadcastSnapshotKey = null;
let pendingBroadcastTimer = null;

function reply(conn, response) {
  ws.sendText(conn, JSON.stringify({ version: protocolVersion, ...response }));
}

function unavailable(conn, id, error = "unavailable") {
  reply(conn, { id, ok: false, error });
}

function readSnapshot() {
  const idle = mpv.getFlag("idle-active");
  if (idle) {
    return { state: "idle", speed: null };
  }

  const paused = mpv.getFlag("pause");
  const speed = mpv.getNumber("speed");
  if (typeof speed !== "number" || !Number.isFinite(speed)) {
    throw new Error("unavailable");
  }

  return { state: paused ? "paused" : "playing", speed };
}

function snapshotKey(snapshot) {
  return `${snapshot.state}:${snapshot.speed === null ? "null" : snapshot.speed}`;
}

function statusChangedMessage(snapshot) {
  return JSON.stringify({
    version: protocolVersion,
    type: "statusChanged",
    snapshot
  });
}

function sendStatusChanged(conn, snapshot) {
  ws.sendText(conn, statusChangedMessage(snapshot));
}

function sendCurrentStatus(conn) {
  try {
    sendStatusChanged(conn, readSnapshot());
  } catch (error) {
    console.log(`GlanceHold bridge snapshot unavailable: ${error.message || "unavailable"}`);
  }
}

function broadcastStatusChanged({ force = false } = {}) {
  if (activeConnections.size === 0) {
    return;
  }

  let snapshot;
  try {
    snapshot = readSnapshot();
  } catch (error) {
    console.log(`GlanceHold bridge status unavailable: ${error.message || "unavailable"}`);
    return;
  }

  const key = snapshotKey(snapshot);
  if (!force && key === lastBroadcastSnapshotKey) {
    return;
  }

  lastBroadcastSnapshotKey = key;
  for (const conn of activeConnections) {
    sendStatusChanged(conn, snapshot);
  }
}

function scheduleStatusChanged() {
  if (typeof setTimeout !== "function") {
    broadcastStatusChanged();
    return;
  }

  if (pendingBroadcastTimer !== null && typeof clearTimeout === "function") {
    clearTimeout(pendingBroadcastTimer);
  }

  pendingBroadcastTimer = setTimeout(() => {
    pendingBroadcastTimer = null;
    broadcastStatusChanged();
  }, 50);
}

function registerStatusEvent(name) {
  try {
    event.on(name, scheduleStatusChanged);
  } catch (error) {
    console.log(`GlanceHold bridge could not register ${name}: ${error.message || "unavailable"}`);
  }
}

function executeBridgeCommand(request) {
  switch (request.command) {
  case "setSpeed":
    if (typeof request.speed !== "number" || !Number.isFinite(request.speed)) {
      throw new Error("invalid_speed");
    }
    core.setSpeed(request.speed);
    return;
  case "pause":
    core.pause();
    return;
  case "resume":
    core.resume();
    return;
  default:
    throw new Error("unknown_command");
  }
}

function handleMessage(conn, text) {
  let request;
  try {
    request = JSON.parse(text);
  } catch {
    unavailable(conn, null, "malformed");
    return;
  }

  const id = request.id;
  if (request.version !== protocolVersion) {
    unavailable(conn, id, "unsupported_version");
    return;
  }

  try {
    switch (request.type) {
    case "snapshot":
      reply(conn, { id, ok: true, snapshot: readSnapshot() });
      return;
    case "command":
      executeBridgeCommand(request);
      reply(conn, { id, ok: true });
      scheduleStatusChanged();
      return;
    default:
      unavailable(conn, id, "unknown_type");
    }
  } catch (error) {
    unavailable(conn, id, error.message || "unavailable");
  }
}

ws.createServer({ port: 47873 });
ws.onStateUpdate((state, error) => {
  if (state === "failed" || state === "cancelled") {
    console.log(`GlanceHold bridge server ${state}: ${error ? error.description : ""}`);
  }
});
ws.onNewConnection((conn) => {
  activeConnections.add(conn);
  sendCurrentStatus(conn);
});
ws.onConnectionStateUpdate((conn, state) => {
  if (state === "failed" || state === "cancelled") {
    activeConnections.delete(conn);
  }
});
ws.onMessage((conn, message) => {
  handleMessage(conn, message.text());
});
registerStatusEvent("iina.file-loaded");
registerStatusEvent("iina.file-started");
registerStatusEvent("iina.window-did-close");
registerStatusEvent("mpv.pause.changed");
registerStatusEvent("mpv.speed.changed");
registerStatusEvent("mpv.idle-active.changed");

if (typeof setInterval === "function") {
  setInterval(() => broadcastStatusChanged(), 5000);
}

ws.startServer();
