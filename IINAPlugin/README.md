# GlanceHold IINA Plugin Bridge

`GlanceHoldBridge.iinaplugin` is the local companion plugin used by GlanceHold v1 to control IINA from the sandboxed status-bar app.

The bridge opens a local WebSocket server on `ws://127.0.0.1:47873`, accepts only authenticated GlanceHold protocol requests for four intents, and pushes read-only player status changes to connected GlanceHold clients.

- `snapshot`
- `setSpeed`
- `pause`
- `resume`

Server-pushed messages use the same protocol version and do not carry a request `id`:

```json
{"version":1,"type":"statusChanged","snapshot":{"state":"playing","speed":2.0}}
```

App-to-plugin requests carry the protocol version, request `id`, and bridge token. Requests without the expected token are rejected before any playback command is considered.

The pushed stream is for menu/status freshness only. It does not trigger playback commands by itself. GlanceHold's Swift playback policy remains responsible for deciding when to hold speed, restore speed, pause, or resume.

The plugin also adds a localized `Toggle GlanceHold Monitoring` / `切换 GlanceHold 监控` item to IINA's Plugin menu with the Option-G key binding (`Alt+g`). This does not send playback commands. It broadcasts one id-less local event to connected GlanceHold clients:

```json
{"version":1,"type":"toggleMonitoringRequested"}
```

If GlanceHold is not running or no local client is connected, the menu action is a plugin-side no-op apart from a diagnostic log. The plugin does not launch GlanceHold.

The plugin listens for IINA file-load/start events and mpv `pause`, `speed`, and `idle-active` property changes. A modest plugin-side fallback refresh helps recover from missed events; GlanceHold should not need one-second app-side polling for ordinary status updates.

It does not proxy arbitrary mpv commands, shell commands, AppleScript, Accessibility actions, URL schemes, app-launch requests, global hotkeys, or media keys.

## Install

Copy or link the plugin folder into IINA's plugin folder:

```zsh
mkdir -p "$HOME/Library/Application Support/com.colliderli.iina/plugins"
cp -R IINAPlugin/GlanceHoldBridge.iinaplugin "$HOME/Library/Application Support/com.colliderli.iina/plugins/"
```

Then open IINA and enable the plugin in IINA's plugin UI if it is not enabled automatically.

## Development Link

For local development, IINA can load a symlink ending in `.iinaplugin-dev`:

```zsh
mkdir -p "$HOME/Library/Application Support/com.colliderli.iina/plugins"
ln -s "$PWD/IINAPlugin/GlanceHoldBridge.iinaplugin" "$HOME/Library/Application Support/com.colliderli.iina/plugins/GlanceHoldBridge.iinaplugin-dev"
```

If the `iina-plugin` CLI is available, the equivalent development command is:

```zsh
iina-plugin link IINAPlugin/GlanceHoldBridge.iinaplugin
```

Restart IINA after changing plugin files.

## Troubleshooting Status Updates

If GlanceHold can send commands but the menu does not update after manual play, pause, speed, or idle changes, restart IINA after copying or linking the latest plugin files and confirm the GlanceHold Bridge plugin is enabled. The expected pushed message types are `statusChanged` and `toggleMonitoringRequested`; request/response messages for `snapshot`, `setSpeed`, `pause`, and `resume` still include request ids.
