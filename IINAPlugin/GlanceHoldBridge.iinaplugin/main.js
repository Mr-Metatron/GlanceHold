const { console, core, mpv, ws } = iina;

const protocolVersion = 1;

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
ws.onMessage((conn, message) => {
  handleMessage(conn, message.text());
});
ws.startServer();
