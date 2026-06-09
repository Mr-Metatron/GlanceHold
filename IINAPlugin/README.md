# GlanceHold IINA Plugin Bridge

`GlanceHoldBridge.iinaplugin` is the local companion plugin used by GlanceHold v1 to control IINA from the sandboxed status-bar app.

The bridge opens a local WebSocket server on `ws://127.0.0.1:47873`, accepts authenticated GlanceHold protocol requests, and pushes player status changes to connected GlanceHold clients. It is intentionally narrow: GlanceHold can request a `snapshot`, `setSpeed`, `pause`, or `resume`, and the plugin can notify GlanceHold about status changes or the monitoring shortcut.

## Install And Enable

Copy the plugin folder into IINA's plugin folder:

```zsh
mkdir -p "$HOME/Library/Application Support/com.colliderli.iina/plugins"
cp -R IINAPlugin/GlanceHoldBridge.iinaplugin "$HOME/Library/Application Support/com.colliderli.iina/plugins/"
```

Restart IINA, then enable `GlanceHold Bridge` in IINA's plugin UI if it is not enabled automatically.

When the bridge is connected, GlanceHold's status-bar menu should show an IINA status row such as `IINA Playing`, `IINA Paused`, `IINA Idle`, or `IINA Not Controllable` instead of an unavailable/setup-needed state.

## Development Link

For local development, IINA can load a development link ending in `.iinaplugin-dev`:

```zsh
mkdir -p "$HOME/Library/Application Support/com.colliderli.iina/plugins"
ln -s "$PWD/IINAPlugin/GlanceHoldBridge.iinaplugin" "$HOME/Library/Application Support/com.colliderli.iina/plugins/GlanceHoldBridge.iinaplugin-dev"
```

If the `iina-plugin` CLI is available, the equivalent development link command is:

```zsh
iina-plugin link IINAPlugin/GlanceHoldBridge.iinaplugin
```

Restart IINA after changing plugin files.

## Shortcut

The plugin adds a localized `Toggle GlanceHold Monitoring` / `切换 GlanceHold 监控` item to IINA's Plugin menu with the `Option-G` shortcut (`Alt+g`).

The shortcut does not send playback commands. It broadcasts a local `toggleMonitoringRequested` event to connected GlanceHold clients, and GlanceHold routes that request through the same safe status-bar action path: calibrate if calibration is needed, enable monitoring when ready, or disable monitoring when active.

If GlanceHold is not running or no local client is connected, the shortcut is a plugin-side no-op apart from a diagnostic log. The plugin does not launch GlanceHold.

Phase 5 carry-forward evidence: the user completed the live IINA shortcut check, selected-state menu visual check, and English/Simplified Chinese readability check after Phase 5. Phase 6 records that as prior evidence and still keeps a final smoke retest path for related docs or copy changes.

## Bridge Protocol

App-to-plugin requests carry protocol `version`, request `id`, and the expected bridge token. Requests without the token are rejected before any playback command is considered.

Server-pushed messages use the same protocol version and do not carry a request `id`.
`statusChanged` carries the current player snapshot:

```json
{"version":1,"type":"statusChanged","snapshot":{"state":"playing","speed":2.0}}
```

The bridge also sends a liveness-only heartbeat about every 5 seconds:

```json
{"version":1,"type":"heartbeat"}
```

Heartbeat messages carry no snapshot, speed, title, path, token, or request `id`.
They are only used to keep the pushed status stream alive and cannot satisfy
snapshot or command request ids.

The monitoring shortcut event is also pushed without a request `id`:

```json
{"version":1,"type":"toggleMonitoringRequested"}
```

The pushed stream is for menu/status freshness, liveness, and the monitoring shortcut only. It does not trigger playback commands by itself. GlanceHold's Swift playback policy remains responsible for deciding when to hold speed, restore speed, pause, or resume.

The plugin listens for IINA file-load/start events and mpv `pause`, `speed`, and `idle-active` property changes. A modest plugin-side fallback `statusChanged` refresh helps recover from missed events, while heartbeat remains a separate liveness signal.

## Troubleshooting

If GlanceHold shows IINA unavailable or setup-needed:

- Confirm IINA is open.
- Confirm `GlanceHold Bridge` is installed and enabled in IINA's plugin UI.
- Restart IINA after copying the plugin or changing the development link.
- Load a playable video when you expect `IINA Playing` or `IINA Paused`.

If GlanceHold can send commands but the IINA status row does not update after manual play, pause, speed, or idle changes, restart IINA after copying or linking the latest plugin files and confirm the plugin is enabled.

Expected pushed message types are `statusChanged`, `heartbeat`, and `toggleMonitoringRequested`; request/response messages for `snapshot`, `setSpeed`, `pause`, and `resume` still include request ids.
