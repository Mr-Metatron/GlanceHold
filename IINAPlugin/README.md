# GlanceHold IINA Plugin Bridge

`GlanceHoldBridge.iinaplugin` is the local companion plugin used by GlanceHold v1 to control IINA from the sandboxed status-bar app.

The bridge is a local single-user loopback integration. GlanceHold connects to `ws://127.0.0.1:47873`; the plugin does not expose a general remote-control API. There is no remote host configuration.

The request surface is intentionally narrow: GlanceHold can request `snapshot`, `setSpeed`, `pause`, or `resume`, and the plugin can push status, heartbeat, and monitoring shortcut events back to connected GlanceHold clients.

## Install And Enable

### Public Release Package

For public release users, start from the [root README](../README.md) and the
GitHub Release for the exact GlanceHold app you downloaded.

1. Use `GlanceHoldBridge-<app-version>-build-<build>.iinaplgz` from the same GitHub Release as `GlanceHold-<app-version>-build-<build>.dmg`, or use the `.iinaplgz` included in the same DMG.
2. Open/install the `.iinaplgz` with IINA.
3. Restart IINA.
4. Confirm `GlanceHold Bridge` is enabled in IINA's plugin UI.
5. Return to GlanceHold and check the IINA row. A connected release pair should leave `IINA Bridge Waiting`, setup-needed, unavailable, and update-needed states.

Do not mix app and plugin files from different releases. GlanceHold does not
promise cross-release app/plugin mixing, even when the bridge protocol version
has not changed.

### Source/Development Install

For a source/development checkout, copy the plugin folder into IINA's plugin
folder. If an old development copy already exists, move it to macOS Trash
before copying the fresh folder:

```zsh
plugin_dir="$HOME/Library/Application Support/com.colliderli.iina/plugins"
target="$plugin_dir/GlanceHoldBridge.iinaplugin"
mkdir -p "$plugin_dir"

if [ -e "$target" ] || [ -L "$target" ]; then
  /usr/bin/trash "$target"
fi

cp -R IINAPlugin/GlanceHoldBridge.iinaplugin "$plugin_dir/"
```

Restart IINA, then confirm `GlanceHold Bridge` is enabled in IINA's plugin UI.

When the bridge is connected, GlanceHold's status-bar menu should show an IINA status row such as `IINA Playing`, `IINA Paused`, `IINA Idle`, or `IINA Not Controllable` instead of an unavailable/setup-needed state.

## Local Trust Model

No request token is required.
Do not copy or paste a bridge token.
There is no remote host configuration.

The bridge security boundary is local loopback plus the plugin's command whitelist. Any process on the same Mac can attempt to connect to the local port, so the plugin accepts only the GlanceHold protocol shape and only the `snapshot`, `setSpeed`, `pause`, and `resume` request names. It does not forward arbitrary mpv commands.

## Development Link

For source/development work, IINA can load a development link ending in
`.iinaplugin-dev`:

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
- For a public release install, confirm the `.iinaplgz` came from the same GitHub Release or same DMG as the GlanceHold app.
- Confirm `GlanceHold Bridge` is installed and enabled in IINA's plugin UI.
- Restart IINA after installing the `.iinaplgz`, copying the source plugin, or changing the development link.
- Load a playable video when you expect `IINA Playing` or `IINA Paused`.

If GlanceHold reports an update-needed or protocol mismatch state, use the current plugin package with the current GlanceHold app from the same GitHub Release or same DMG. Update or reinstall the GlanceHold IINA plugin, then restart IINA.

If IINA is open and the plugin is enabled but GlanceHold still reports the bridge as unavailable, keep both apps on the same Mac, restart IINA, and check again from the GlanceHold menu. The bridge listens on `ws://127.0.0.1:47873`; there is no remote host configuration and no request token to paste.

If GlanceHold can send commands but the IINA status row does not update after manual play, pause, speed, or idle changes, restart IINA after copying or linking the latest plugin files and confirm the plugin is enabled.

Expected pushed message types are `statusChanged`, `heartbeat`, and `toggleMonitoringRequested`; request/response messages for `snapshot`, `setSpeed`, `pause`, and `resume` still include request ids.

## Release Connectivity Smoke

After installing the public `.iinaplgz`, restart IINA, load a playable video, confirm `GlanceHold Bridge` is enabled, and confirm the GlanceHold IINA row leaves `IINA Bridge Waiting`, setup-needed, unavailable, and update-needed states without reading or pasting any token.

This smoke proves plugin install plus local bridge connectivity. Speed Control and Pause/Resume playback behavior are verified by the release verification workflow.

The current GlanceHold app/plugin pair uses this no-token local loopback trust model.
