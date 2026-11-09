# TouchBridge

Multitouch für USB-Touchscreens unter macOS: TouchBridge übernimmt das Gerät exklusiv, verfolgt alle Finger selbst und speist Mausereignisse sowie Trackpad-Gesten systemweit in macOS ein.

![Swift](https://img.shields.io/badge/Swift-6.0-orange) ![Plattform](https://img.shields.io/badge/macOS-14%2B-blue) ![Lizenz](https://img.shields.io/badge/Lizenz-MIT-green)

> **Status:** Meilenstein 1 (Core) und 2 (Gesten) sind implementiert und unit-getestet; die Hardware-Abnahme am Referenzpanel steht noch aus.

macOS behandelt einen HID-Touchscreen nur als Single-Touch-Zeiger. TouchBridge sorgt dafür, dass jede App Pinch, Rotate, Scrollen mit Momentum und Mehrfinger-Swipes erhält, als kämen sie von einem Trackpad. Open Source (MIT), keine Lizenzschlüssel.

## Features

- Automatische Erkennung von HID-Touchscreens (Usage Page 0x0D / Usage 0x04), exklusiver Zugriff (Seize), Hotplug
- Abbildung auf das richtige Display inkl. Rotation und Kalibrierung je Geräteseriennummer
- Ein Finger: Klick, Doppelklick, Drag, langes Halten = Rechtsklick
- Zwei Finger: Scrollen mit Momentum, Pinch (Magnify), Rotate, Tap = Rechtsklick
- Drei/vier Finger: Swipes für Mission Control, App Exposé, Spaces
- Menüleisten-App mit Statusanzeige, Display-Auswahl, Login-Item und Gesture-Identifier-Fenster
- Einstellungen als JSON-Datei, live editierbar
- Rechte-Onboarding für Input Monitoring und Accessibility
- Hilfswerkzeug `hidrecord` zum Aufzeichnen roher HID-Reports

### Standard-Gesten

| Geste | Ergebnis |
| --- | --- |
| Tap | Linksklick |
| Doppeltap | Doppelklick |
| Drücken und bewegen | Drag |
| Halten (0,6 s) | Rechtsklick |
| Zwei-Finger-Tap | Rechtsklick |
| Zwei-Finger-Bewegung | Scrollen mit Momentum (natürliche Richtung, umschaltbar) |
| Pinch / Spread | Zoom |
| Zwei-Finger-Drehung | Rotation |
| Drei/vier Finger hoch | Mission Control |
| Drei/vier Finger runter | App Exposé |
| Drei/vier Finger links/rechts | Nächster / vorheriger Space |

## Tech-Stack

- Swift 6 (Sprachmodus 6), Swift Package Manager, macOS 14+
- SwiftUI/AppKit (Menüleiste), IOKit HID, CoreGraphics (CGEvent), ServiceManagement
- Tests mit Swift Testing

## Schnellstart

### Voraussetzungen

- macOS 14 oder neuer (entwickelt unter macOS 26)
- Touchscreen, der unter Windows ohne Treiber läuft (HID-Digitizer). Referenzgerät: Elan-10-Finger-Controller, 24" 1080p
- Xcode 16 oder neuer

### Installation und Start

```
git clone https://github.com/Infactionfreddy/TouchBridge.git
cd TouchBridge
Scripts/build-app.sh          # baut und signiert dist/TouchBridge.app
Scripts/install.sh            # kopiert nach ~/Applications und startet
```

Beim ersten Start im sich öffnenden Fenster **Input Monitoring** und **Accessibility** erteilen. Der Status aktualisiert sich selbst; nach der Freigabe kann macOS einen Neustart der App verlangen.

> Hinweis: `Scripts/build-app.sh` signiert standardmäßig mit einer festen Entwickler-Identität; mit `SIGN_IDENTITY` die eigene setzen.

## Konfiguration

Datei: `~/Library/Application Support/TouchBridge/settings.json` (im Menü: „Open settings file").

| Schlüssel / Variable | Beschreibung |
| --- | --- |
| `enabled` | Touch ein/aus |
| `displaySelection` | `{"auto":{}}` oder `{"display":{"uuid":"…"}}` |
| `naturalScrolling` | Scrollrichtung |
| `gesture` | Schwellen in Sekunden/Punkten |
| `calibrations` | je Seriennummer: `orientation`, `scaleX`, `scaleY`, `offsetX`, `offsetY` |
| `launchAtLogin` | Start beim Login |
| `SIGN_IDENTITY` (Umgebungsvariable, Build-Skript) | Signatur-Identität für `build-app.sh` |

Details: [docs/KONFIGURATION.md](docs/KONFIGURATION.md).

## Fehlersuche

- Menü zeigt „shared": exklusiver Zugriff fehlgeschlagen; Input Monitoring prüfen. Im Shared-Modus bewegt macOS den Cursor mit.
- Taps gespiegelt oder gedreht: `calibrations.<serial>.orientation` auf 90, 180 oder 270 setzen.
- Pinch wirkt in einer App nicht: „Gesture Identifier…" öffnen und Geste ausführen; erscheinen dort `magnify`-Zeilen, unterstützt die App keinen Trackpad-Zoom.
- Berührung ohne Wirkung trotz „exclusive": Log nach `read feature report` prüfen (siehe `docs/notes/seize-spike.md`).
- Logs: `log stream --predicate 'subsystem == "org.touchbridge"' --level info`
- `swift test` scheitert bei codesign („resource fork, Finder information…"): `swift test --scratch-path /tmp/touchbridge-build` oder `xattr -cr .build`.

## Projektstruktur

```
Package.swift
App/Info.plist             Bundle-Metadaten
Scripts/                   build-app.sh, install.sh
Sources/
  TouchCore/               HID-Parser, Decoder, Tracker, Gesten-Engine, Router, Settings (ohne System-APIs)
  TouchDevice/             DeviceManager (IOKit HID)
  TouchInject/             EventInjector, Momentum, Gesten-Felder (CGEvent)
  TouchBridge/             Menüleisten-App (SwiftUI)
  hidrecord/               CLI zum Aufzeichnen von Reports
Tests/                     TouchCoreTests, TouchInjectTests, Fixtures
docs/                      Dokumentation, Notizen, Specs, Pläne
```

## Entwicklung

```
swift build
swift test
swift run hidrecord --seconds 10 --out capture.jsonl
```

Bei neuer Hardware zuerst den Seize-Spike ausführen (TouchBridge vorher beenden): `swift run hidrecord --seconds 12 --out Tests/TouchCoreTests/Fixtures/elan-two-finger.jsonl`. `mode=exclusive` und ein stillstehender macOS-Cursor sind das Erfolgskriterium. Das Referenzpanel liefert erst nach dem Lesen seiner Feature-Reports Multitouch-Daten; `DeviceManager` erledigt das nach jedem Öffnen.

Design: `docs/superpowers/specs/`, Pläne: `docs/superpowers/plans/`. Die undokumentierten CGEvent-Felder für Magnify/Rotate stehen ausschließlich in `Sources/TouchInject/GestureEventFields.swift` und können mit macOS-Updates brechen.

## Dokumentation

- [Architektur](docs/ARCHITEKTUR.md)
- [Installation](docs/INSTALLATION.md)
- [Konfiguration](docs/KONFIGURATION.md)
- [Entwicklung](docs/ENTWICKLUNG.md)

## Lizenz

MIT, siehe [LICENSE](LICENSE).
