# Entwicklung

[← Zurück zur README](../README.md)

## Lokale Umgebung

- macOS 14+, Xcode 16+ (Swift 6)
- `Package.swift` kann direkt in Xcode geöffnet werden; ein `.xcodeproj` wird nicht gepflegt.

```
swift build
swift test
swift run TouchBridge          # ohne Bundle/Signatur; Rechte hängen dann am Terminal (Annahme)
swift run hidrecord --seconds 10 --out capture.jsonl
```

Für die echte App: `Scripts/build-app.sh` und `Scripts/install.sh`.

## Code-Struktur

| Pfad | Inhalt |
| --- | --- |
| `Sources/TouchCore` | Reine Logik (Gesture, HID, Mapping, Routing, Settings, Touch) |
| `Sources/TouchDevice` | IOKit-Geräteverwaltung |
| `Sources/TouchInject` | CGEvent-Erzeugung, Momentum |
| `Sources/TouchBridge` | App, Views, Pipeline-Steuerung |
| `Sources/hidrecord` | Aufzeichnungs-CLI |
| `Tests/TouchCoreTests` | Unit-Tests, Fixtures (`elan-report-descriptor.hex`, `elan-two-finger.jsonl`), Support-Builder |
| `Tests/TouchInjectTests` | Event-Builder- und Momentum-Tests |
| `docs/notes` | Messungen, Seize-Spike, offene Punkte |
| `docs/superpowers` | Specs und Pläne |

## Tests

```
swift test
```

Die Tests nutzen Swift Testing (`@Suite`, `@Test`). Abgedeckt sind Descriptor-Parser, Framing, Decoder, Tracker, DisplayMapper, GestureEngine (1/2/3+ Finger), ActionRouter, SettingsStore sowie Event-Builder und Momentum. `RecordedReportTests` nutzt die aufgezeichnete Elan-Session und wird übersprungen, falls die Fixture fehlt.

Nicht automatisch getestet: App-Layer (`AppState`, `PipelineController`, Views), `DeviceManager`, echter CGEvent-Versand. Die Hardware-Abnahme erfolgt manuell (Checklisten in `docs/notes/follow-ups.md`).

Probleme mit `swift test` und codesign: `swift test --scratch-path /tmp/touchbridge-build` oder `xattr -cr .build`.

## Neue Hardware testen

1. TouchBridge beenden (zwei Seizer ergeben `shared`).
2. `swift run hidrecord --seconds 12 --out Tests/TouchCoreTests/Fixtures/elan-two-finger.jsonl`
3. Erwartet: `mode=exclusive`, Cursor bewegt sich nicht mehr. Bei `shared (seize failed 0x…)`: Input Monitoring für die Terminal-App prüfen.

## Coding-Standards

- Swift 6 Sprachmodus (strikte Nebenläufigkeit): Modelle `Sendable`, UI auf `@MainActor`.
- `TouchCore` bleibt frei von AppKit/IOKit/CoreGraphics-Systemzugriffen.
- Die Engine bezieht Zeit nur aus Eingaben, nicht aus Systemuhren (Determinismus).
- Undokumentierte CGEvent-Felder ausschließlich in `GestureEventFields.swift`, mit Quellenangabe.
- `DeviceManager.stop()` ist synchron und darf nie aus dem Sink aufgerufen werden.
- Einstellungswerte werden beim Dekodieren geklemmt, damit handbearbeitete Dateien die Pipeline nicht zum Absturz bringen.
- Zu Namenskonventionen/Linting: kein Linter-Setup im Repo erkennbar.

## Release-Ablauf

Noch nicht automatisiert (Annahme anhand der Notizen):

1. Hardware-Checklisten (Meilenstein 1 und 2) abarbeiten.
2. `swift test` grün.
3. App mit Release-Konfiguration bauen (`Scripts/build-app.sh release`); für Verteilung Developer-ID-Signatur und Notarisierung (derzeit nicht skriptiert).
4. Tag `v0.1.0` erst nach bestandener Abnahme setzen.

## Offene Punkte

Siehe `docs/notes/follow-ups.md` (Device-Layer-Härtung, Momentum-Glättung, zusätzliche Grenzfalltests, Settings-Migration).
