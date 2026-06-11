const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const pluginPath = path.join(__dirname, "GlanceHoldBridge.iinaplugin", "main.js");
const pluginSource = fs.readFileSync(pluginPath, "utf8");

function createHarness() {
  const replies = [];
  const calls = {
    pause: 0,
    resume: 0,
    setSpeed: [],
    mpvGetFlag: [],
    mpvGetNumber: []
  };
  let messageHandler = null;
  let newConnectionHandler = null;
  const eventHandlers = new Map();
  let paused = false;
  let idle = false;
  let playbackSpeed = 1.25;

  const iina = {
    language: "en",
    console: {
      log() {}
    },
    core: {
      pause() {
        calls.pause += 1;
        paused = true;
      },
      resume() {
        calls.resume += 1;
        paused = false;
      },
      setSpeed(speed) {
        calls.setSpeed.push(speed);
        playbackSpeed = speed;
      }
    },
    event: {
      on(name, handler) {
        eventHandlers.set(name, handler);
      }
    },
    menu: {
      item(title, action, options) {
        return { title, action, options };
      },
      addItem() {}
    },
    mpv: {
      getFlag(name) {
        calls.mpvGetFlag.push(name);
        if (name === "idle-active") {
          return idle;
        }
        if (name === "pause") {
          return paused;
        }
        return false;
      },
      getNumber(name) {
        calls.mpvGetNumber.push(name);
        if (name === "speed") {
          return playbackSpeed;
        }
        return 0;
      }
    },
    ws: {
      createServer() {},
      onStateUpdate() {},
      onNewConnection(handler) {
        newConnectionHandler = handler;
      },
      onConnectionStateUpdate() {},
      onMessage(handler) {
        messageHandler = handler;
      },
      sendText(conn, text) {
        replies.push({ conn, text, body: JSON.parse(text) });
      },
      startServer() {}
    }
  };

  vm.runInNewContext(pluginSource, { iina }, { filename: pluginPath });
  assert.equal(typeof messageHandler, "function");

  function sendRaw(text) {
    messageHandler("conn-1", {
      text() {
        return text;
      }
    });
    return replies.at(-1)?.body;
  }

  function sendRequest(request) {
    return sendRaw(JSON.stringify(request));
  }

  function connect(conn = "conn-1") {
    newConnectionHandler(conn);
  }

  function setPlayback({ isPaused = paused, isIdle = idle, speed = playbackSpeed } = {}) {
    paused = isPaused;
    idle = isIdle;
    playbackSpeed = speed;
  }

  function emit(name) {
    eventHandlers.get(name)();
  }

  return { calls, replies, connect, emit, sendRaw, sendRequest, setPlayback };
}

function assertNoSideEffects(calls) {
  assert.equal(calls.pause, 0);
  assert.equal(calls.resume, 0);
  assert.deepEqual(calls.setSpeed, []);
  assert.deepEqual(calls.mpvGetFlag, []);
  assert.deepEqual(calls.mpvGetNumber, []);
}

function assertMalformedResponse(response) {
  assert.equal(response.version, 3);
  assert.equal(response.id, null);
  assert.equal(response.ok, false);
  assert.equal(response.error, "malformed");
}

function assertInvalidSpeedResponse(response, id) {
  assert.equal(response.version, 3);
  assert.equal(response.id, id);
  assert.equal(response.ok, false);
  assert.equal(response.error, "invalid_speed");
}

function testMalformedJSONHasNoSideEffects() {
  const harness = createHarness();

  const response = harness.sendRaw("{");

  assertMalformedResponse(response);
  assertNoSideEffects(harness.calls);
}

function testInvalidRequestShapesHaveNoSideEffects() {
  const invalidRequests = [
    42,
    "snapshot",
    true,
    null,
    [],
    [1],
    { version: 3, type: "command", command: "pause" },
    { id: 0, version: 3, type: "command", command: "pause" },
    { id: -1, version: 3, type: "command", command: "pause" },
    { id: 1.5, version: 3, type: "command", command: "pause" },
    { id: "1", version: 3, type: "command", command: "pause" },
    { id: Number.MAX_SAFE_INTEGER + 1, version: 3, type: "command", command: "pause" }
  ];

  for (const request of invalidRequests) {
    const harness = createHarness();

    const response = harness.sendRequest(request);

    assertMalformedResponse(response);
    assertNoSideEffects(harness.calls);
  }
}

function testValidPauseCommandHasOneSideEffect() {
  const harness = createHarness();

  const response = harness.sendRequest({
    id: 12,
    version: 3,
    type: "command",
    command: "pause"
  });

  assert.deepEqual(response, { version: 3, id: 12, ok: true });
  assert.equal(harness.calls.pause, 1);
  assert.equal(harness.calls.resume, 0);
  assert.deepEqual(harness.calls.setSpeed, []);
  assert.deepEqual(harness.calls.mpvGetFlag, []);
  assert.deepEqual(harness.calls.mpvGetNumber, []);
}

function testSetSpeedBoundariesAreAccepted() {
  for (const speed of [0.1, 16.0]) {
    const harness = createHarness();

    const response = harness.sendRequest({
      id: 20,
      version: 3,
      type: "command",
      command: "setSpeed",
      speed
    });

    assert.deepEqual(response, { version: 3, id: 20, ok: true });
    assert.equal(harness.calls.pause, 0);
    assert.equal(harness.calls.resume, 0);
    assert.deepEqual(harness.calls.setSpeed, [speed]);
    assert.deepEqual(harness.calls.mpvGetFlag, []);
    assert.deepEqual(harness.calls.mpvGetNumber, []);
  }
}

function testInvalidSetSpeedValuesAreRejectedWithoutSideEffects() {
  const invalidRequests = [
    { id: 30, version: 3, type: "command", command: "setSpeed", speed: 0 },
    { id: 31, version: 3, type: "command", command: "setSpeed", speed: -1 },
    { id: 32, version: 3, type: "command", command: "setSpeed", speed: 0.099 },
    { id: 33, version: 3, type: "command", command: "setSpeed", speed: 16.001 },
    { id: 34, version: 3, type: "command", command: "setSpeed" },
    { id: 35, version: 3, type: "command", command: "setSpeed", speed: "1" }
  ];

  for (const request of invalidRequests) {
    const harness = createHarness();

    const response = harness.sendRequest(request);

    assertInvalidSpeedResponse(response, request.id);
    assertNoSideEffects(harness.calls);
  }

  const nonFiniteHarness = createHarness();
  const nonFiniteResponse = nonFiniteHarness.sendRaw(
    '{"id":36,"version":3,"type":"command","command":"setSpeed","speed":1e999}'
  );

  assertInvalidSpeedResponse(nonFiniteResponse, 36);
  assertNoSideEffects(nonFiniteHarness.calls);
}

function testPauseAndResumeStillWorkAfterSpeedValidation() {
  const pauseHarness = createHarness();
  const pauseResponse = pauseHarness.sendRequest({
    id: 40,
    version: 3,
    type: "command",
    command: "pause"
  });

  assert.deepEqual(pauseResponse, { version: 3, id: 40, ok: true });
  assert.equal(pauseHarness.calls.pause, 1);
  assert.equal(pauseHarness.calls.resume, 0);
  assert.deepEqual(pauseHarness.calls.setSpeed, []);
  assert.deepEqual(pauseHarness.calls.mpvGetFlag, []);
  assert.deepEqual(pauseHarness.calls.mpvGetNumber, []);

  const resumeHarness = createHarness();
  const resumeResponse = resumeHarness.sendRequest({
    id: 41,
    version: 3,
    type: "command",
    command: "resume"
  });

  assert.deepEqual(resumeResponse, { version: 3, id: 41, ok: true });
  assert.equal(resumeHarness.calls.pause, 0);
  assert.equal(resumeHarness.calls.resume, 1);
  assert.deepEqual(resumeHarness.calls.setSpeed, []);
  assert.deepEqual(resumeHarness.calls.mpvGetFlag, []);
  assert.deepEqual(resumeHarness.calls.mpvGetNumber, []);
}

function testValidSnapshotReadsSnapshot() {
  const harness = createHarness();

  const response = harness.sendRequest({
    id: 44,
    version: 3,
    type: "snapshot"
  });

  assert.deepEqual(response, {
    version: 3,
    id: 44,
    ok: true,
    snapshot: {
      state: "playing",
      speed: 1.25
    }
  });
  assert.equal(harness.calls.pause, 0);
  assert.equal(harness.calls.resume, 0);
  assert.deepEqual(harness.calls.setSpeed, []);
  assert.deepEqual(harness.calls.mpvGetFlag, ["idle-active", "pause"]);
  assert.deepEqual(harness.calls.mpvGetNumber, ["speed"]);
}

function testManualPropertyChangesAnnotateStatusChanged() {
  const harness = createHarness();
  harness.connect();

  harness.replies.length = 0;
  harness.setPlayback({ isPaused: true });
  harness.emit("mpv.pause.changed");
  assert.equal(harness.replies.at(-1).body.snapshot.manualAction, "pausePressed");

  harness.setPlayback({ isPaused: false });
  harness.emit("mpv.pause.changed");
  assert.equal(harness.replies.at(-1).body.snapshot.manualAction, "playPressed");

  harness.setPlayback({ isPaused: false, speed: 1.75 });
  harness.emit("mpv.speed.changed");
  assert.equal(harness.replies.at(-1).body.snapshot.manualAction, "speedChanged");

  harness.setPlayback({ isPaused: true, speed: 1.25 });
  harness.emit("mpv.speed.changed");
  assert.equal(harness.replies.at(-1).body.snapshot.state, "paused");
  assert.equal(harness.replies.at(-1).body.snapshot.manualAction, "speedChanged");
}

function testBridgeCommandEchoesAreNotAnnotatedAsManualActions() {
  const harness = createHarness();
  harness.connect();
  harness.replies.length = 0;

  const pauseStart = harness.replies.length;
  harness.sendRequest({
    id: 45,
    version: 3,
    type: "command",
    command: "pause"
  });
  const pauseReplies = harness.replies.slice(pauseStart).map((reply) => reply.body);
  const pauseResponse = pauseReplies.find((reply) => reply.id === 45);
  const pauseStatusChanged = pauseReplies.find((reply) => reply.type === "statusChanged");

  assert.deepEqual(pauseResponse, { version: 3, id: 45, ok: true });
  assert.equal(pauseStatusChanged.snapshot.state, "paused");
  assert.equal(pauseStatusChanged.snapshot.manualAction, undefined);

  const speedStart = harness.replies.length;
  harness.sendRequest({
    id: 46,
    version: 3,
    type: "command",
    command: "setSpeed",
    speed: 1.5
  });
  const speedReplies = harness.replies.slice(speedStart).map((reply) => reply.body);
  const speedResponse = speedReplies.find((reply) => reply.id === 46);
  const speedStatusChanged = speedReplies.find((reply) => reply.type === "statusChanged");

  assert.deepEqual(speedResponse, { version: 3, id: 46, ok: true });
  assert.equal(speedStatusChanged.snapshot.state, "paused");
  assert.equal(speedStatusChanged.snapshot.manualAction, undefined);

  const speedEchoStart = harness.replies.length;
  harness.emit("mpv.speed.changed");
  const speedEchoReplies = harness.replies.slice(speedEchoStart).map((reply) => reply.body);
  assert.equal(speedEchoReplies.length, 0);

  const laterManualSpeedStart = harness.replies.length;
  harness.emit("mpv.speed.changed");
  const laterManualSpeedReplies = harness.replies.slice(laterManualSpeedStart).map((reply) => reply.body);
  const laterManualSpeedStatusChanged = laterManualSpeedReplies.find((reply) => reply.type === "statusChanged");

  assert.equal(laterManualSpeedStatusChanged.snapshot.state, "paused");
  assert.equal(laterManualSpeedStatusChanged.snapshot.speed, 1.5);
  assert.equal(laterManualSpeedStatusChanged.snapshot.manualAction, "speedChanged");
}

const tests = [
  testMalformedJSONHasNoSideEffects,
  testInvalidRequestShapesHaveNoSideEffects,
  testValidPauseCommandHasOneSideEffect,
  testSetSpeedBoundariesAreAccepted,
  testInvalidSetSpeedValuesAreRejectedWithoutSideEffects,
  testPauseAndResumeStillWorkAfterSpeedValidation,
  testValidSnapshotReadsSnapshot,
  testManualPropertyChangesAnnotateStatusChanged,
  testBridgeCommandEchoesAreNotAnnotatedAsManualActions
];

let failed = 0;
for (const test of tests) {
  try {
    test();
    console.log(`ok ${test.name}`);
  } catch (error) {
    failed += 1;
    console.error(`not ok ${test.name}`);
    console.error(error);
  }
}

if (failed > 0) {
  process.exitCode = 1;
}
