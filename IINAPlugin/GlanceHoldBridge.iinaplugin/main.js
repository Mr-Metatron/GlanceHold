const { console, core, event, menu, mpv, ws } = iina;

const protocolVersion = 1;
const bridgeToken = "glancehold-iina-bridge-v1";
const toggleMonitoringTitles = {
  en: "Toggle GlanceHold Monitoring",
  "zh-Hans": "切换 GlanceHold 监控"
};
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

function heartbeatMessage() {
  return JSON.stringify({
    version: protocolVersion,
    type: "heartbeat"
  });
}

function toggleMonitoringRequestedMessage() {
  return JSON.stringify({
    version: protocolVersion,
    type: "toggleMonitoringRequested"
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

function broadcastHeartbeat() {
  if (activeConnections.size === 0) {
    return;
  }

  const message = heartbeatMessage();
  for (const conn of activeConnections) {
    ws.sendText(conn, message);
  }
}

function broadcastToggleMonitoringRequested() {
  if (activeConnections.size === 0) {
    console.log("GlanceHold bridge toggle requested with no active GlanceHold connection.");
    return;
  }

  const message = toggleMonitoringRequestedMessage();
  for (const conn of activeConnections) {
    ws.sendText(conn, message);
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

function isAuthorized(request) {
  return typeof request.token === "string" && request.token === bridgeToken;
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
  if (!isAuthorized(request)) {
    unavailable(conn, id, "unauthorized");
    return;
  }

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

function preferredLanguage() {
  const language = String(iina.language || iina.locale || "en");
  return language.toLowerCase().startsWith("zh") ? "zh-Hans" : "en";
}

function localizedToggleMonitoringTitle() {
  return toggleMonitoringTitles[preferredLanguage()] || toggleMonitoringTitles.en;
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

menu.addItem(menu.item(
  localizedToggleMonitoringTitle(),
  broadcastToggleMonitoringRequested,
  { keyBinding: "Alt+g" }
));

if (typeof setInterval === "function") {
  setInterval(() => broadcastHeartbeat(), 5000);
  setInterval(() => broadcastStatusChanged(), 5000);
}

ws.startServer();
