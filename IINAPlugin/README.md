# GlanceHold IINA Plugin Bridge

`GlanceHoldBridge.iinaplugin` is the local companion plugin used by GlanceHold v1 to control IINA from the sandboxed status-bar app.

The bridge is a local single-user loopback integration. GlanceHold connects to `ws://127.0.0.1:47873`; the plugin does not expose a general remote-control API. There is no remote host configuration.

The request surface is intentionally narrow: GlanceHold can request `snapshot`, `setSpeed`, `pause`, or `resume`, and the plugin can push status, heartbeat, and monitoring shortcut events back to connected GlanceHold clients.

## Install And Enable

Copy the plugin folder into IINA's plugin folder:

```zsh
mkdir -p "$HOME/Library/Application Support/com.colliderli.iina/plugins"
cp -R IINAPlugin/GlanceHoldBridge.iinaplugin "$HOME/Library/Application Support/com.colliderli.iina/plugins/"
```

Restart IINA, then enable `GlanceHold Bridge` in IINA's plugin UI if it is not enabled automatically.

When the bridge is connected, GlanceHold's status-bar menu should show an IINA status row such as `IINA Playing`, `IINA Paused`, `IINA Idle`, or `IINA Not Controllable` instead of an unavailable/setup-needed state.

## Local Trust Model

No request token is required.
Do not copy or paste a bridge token.
There is no remote host configuration.

The security boundary for v1.1 is local loopback plus the plugin's command whitelist. Any process on the same Mac can attempt to connect to the local port, so the plugin accepts only the GlanceHold protocol shape and only the `snapshot`, `setSpeed`, `pause`, and `resume` request names. It does not forward arbitrary mpv commands.

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

## Bridge Protocol

App-to-plugin requests carry protocol `version`, request `id`, request `type`, and any type-specific fields. Protocol version 3 is the supported no-token schema.

Supported request types are:

- `snapshot` returns the current IINA playback state and speed.
- `command` accepts only `setSpeed`, `pause`, or `resume`.
- `setSpeed` requires a finite numeric `speed`.

Server-pushed messages use the same protocol version and do not carry a request `id`.
`statusChanged` carries the current player snapshot:

```json
{"version":3,"type":"statusChanged","snapshot":{"state":"playing","speed":2.0}}
```

Snapshots may include optional `manualAction` values (`speedChanged`, `playPressed`, or `pausePressed`) when the plugin observes a user-originated player change. Echoes from GlanceHold bridge commands omit `manualAction`.

The bridge also sends a liveness-only heartbeat about every 5 seconds:

```json
{"version":3,"type":"heartbeat"}
```

Heartbeat messages carry no snapshot, speed, title, path, or request `id`.
They are only used to keep the pushed status stream alive and cannot satisfy
snapshot or command request ids.

The monitoring shortcut event is also pushed without a request `id`:

```json
{"version":3,"type":"toggleMonitoringRequested"}
```

The pushed stream is for menu/status freshness, liveness, and the monitoring shortcut only. It does not trigger playback commands by itself. GlanceHold's Swift playback policy remains responsible for deciding when to hold speed, restore speed, pause, or resume.

The plugin listens for IINA file-load/start events and mpv `pause`, `speed`, and `idle-active` property changes. A modest plugin-side fallback `statusChanged` refresh helps recover from missed events, while heartbeat remains a separate liveness signal.

## Troubleshooting

If GlanceHold shows IINA unavailable or setup-needed:

- Confirm IINA is open.
- Confirm `GlanceHold Bridge` is installed and enabled in IINA's plugin UI.
- Restart IINA after copying the plugin or changing the development link.
- Load a playable video when you expect `IINA Playing` or `IINA Paused`.

If GlanceHold reports an update-needed or protocol mismatch state, use the current plugin files with the current GlanceHold app. Update or reinstall the GlanceHold IINA plugin, then restart IINA.

If GlanceHold can send commands but the IINA status row does not update after manual play, pause, speed, or idle changes, restart IINA after copying or linking the latest plugin files and confirm the plugin is enabled.

Expected pushed message types are `statusChanged`, `heartbeat`, and `toggleMonitoringRequested`; request/response messages for `snapshot`, `setSpeed`, `pause`, and `resume` still include request ids.

## Supplemental Manual Smoke

This check is optional and supplemental, not a hard phase gate. After updating the plugin, restart IINA, load a playable video, and confirm the GlanceHold IINA row leaves `IINA Bridge Waiting` without reading or pasting any token.

Phase 11 inherits this no-token local loopback trust model.
