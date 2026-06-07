# GlanceHold IINA Plugin Bridge

`GlanceHoldBridge.iinaplugin` is the local companion plugin used by GlanceHold v1 to control IINA from the sandboxed status-bar app.

The bridge opens a local WebSocket server on `ws://127.0.0.1:47873` and accepts only four message intents:

- `snapshot`
- `setSpeed`
- `pause`
- `resume`

It does not proxy arbitrary mpv commands, shell commands, AppleScript, Accessibility actions, URL schemes, or media keys.

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
