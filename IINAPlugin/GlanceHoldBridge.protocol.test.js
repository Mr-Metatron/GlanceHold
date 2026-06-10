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

  const iina = {
    language: "en",
    console: {
      log() {}
    },
    core: {
      pause() {
        calls.pause += 1;
      },
      resume() {
        calls.resume += 1;
      },
      setSpeed(speed) {
        calls.setSpeed.push(speed);
      }
    },
    event: {
      on() {}
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
          return false;
        }
        if (name === "pause") {
          return false;
        }
        return false;
      },
      getNumber(name) {
        calls.mpvGetNumber.push(name);
        if (name === "speed") {
          return 1.25;
        }
        return 0;
      }
    },
    ws: {
      createServer() {},
      onStateUpdate() {},
      onNewConnection() {},
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

  return { calls, replies, sendRaw, sendRequest };
}

function assertNoSideEffects(calls) {
  assert.equal(calls.pause, 0);
  assert.equal(calls.resume, 0);
  assert.deepEqual(calls.setSpeed, []);
  assert.deepEqual(calls.mpvGetFlag, []);
  assert.deepEqual(calls.mpvGetNumber, []);
}

function assertMalformedResponse(response) {
  assert.equal(response.version, 2);
  assert.equal(response.id, null);
  assert.equal(response.ok, false);
  assert.equal(response.error, "malformed");
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
    { version: 2, type: "command", command: "pause" },
    { id: 0, version: 2, type: "command", command: "pause" },
    { id: -1, version: 2, type: "command", command: "pause" },
    { id: 1.5, version: 2, type: "command", command: "pause" },
    { id: "1", version: 2, type: "command", command: "pause" },
    { id: Number.MAX_SAFE_INTEGER + 1, version: 2, type: "command", command: "pause" }
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
    version: 2,
    type: "command",
    command: "pause"
  });

  assert.deepEqual(response, { version: 2, id: 12, ok: true });
  assert.equal(harness.calls.pause, 1);
  assert.equal(harness.calls.resume, 0);
  assert.deepEqual(harness.calls.setSpeed, []);
  assert.deepEqual(harness.calls.mpvGetFlag, []);
  assert.deepEqual(harness.calls.mpvGetNumber, []);
}

function testValidSnapshotReadsSnapshot() {
  const harness = createHarness();

  const response = harness.sendRequest({
    id: 44,
    version: 2,
    type: "snapshot"
  });

  assert.deepEqual(response, {
    version: 2,
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

const tests = [
  testMalformedJSONHasNoSideEffects,
  testInvalidRequestShapesHaveNoSideEffects,
  testValidPauseCommandHasOneSideEffect,
  testValidSnapshotReadsSnapshot
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
