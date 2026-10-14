# TouchBridge

Multitouch for USB touch screens on macOS. TouchBridge takes exclusive control of a HID touch screen, tracks all contacts itself and injects mouse events and trackpad gestures (scroll with momentum, pinch, rotate, 3/4-finger swipes) system-wide.

Status: milestone 1 and 2 in development. See `docs/superpowers/specs/` for the design.

## Build

```
swift build
swift test
Scripts/build-app.sh        # → dist/TouchBridge.app (signed)
Scripts/install.sh          # → ~/Applications/TouchBridge.app
```

## Permissions

TouchBridge needs **Input Monitoring** (to open the touch screen exclusively) and **Accessibility** (to post events). The app asks for both on first launch.

## License

MIT
