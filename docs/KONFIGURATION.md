# Konfiguration

[← Zurück zur README](../README.md)

## Einstellungsdatei

Pfad: `~/Library/Application Support/TouchBridge/settings.json`. Sie kann bei laufender App bearbeitet werden (Menü: „Open settings file"); die App speichert Änderungen aus dem Menü selbst. Fehlt die Datei, gelten Standardwerte. Eine defekte Datei wird als `settings.json.broken` beiseitegelegt und durch Standardwerte ersetzt. Fehlende Schlüssel erhalten Standardwerte.

### Top-Level-Schlüssel

| Schlüssel | Typ | Standard | Beschreibung |
| --- | --- | --- | --- |
| `schemaVersion` | Zahl | 1 | Wird von der App geschrieben; höhere Werte werden beim Speichern auf 1 normalisiert |
| `enabled` | Bool | `true` | Touch-Steuerung aktiv |
| `displaySelection` | Objekt | `{"auto":{}}` | `{"auto":{}}` oder `{"display":{"uuid":"…"}}` |
| `naturalScrolling` | Bool | `true` | Inhalt folgt den Fingern |
| `gesture` | Objekt | siehe unten | Schwellen und Zeiten |
| `calibrations` | Objekt | leer | Schlüssel = Geräteseriennummer |
| `launchAtLogin` | Bool | `false` | Start beim Login (SMAppService) |

### `calibrations.<Seriennummer>`

| Schlüssel | Beschreibung |
| --- | --- |
| `orientation` | 0/90/180/270; Wert wird modulo 360 reduziert, andere Werte werden zu 0 |
| `scaleX`, `scaleY` | Skalierung der normierten Koordinaten (Standard 1) |
| `offsetX`, `offsetY` | Versatz der normierten Koordinaten (Standard 0) |

### `gesture` (GestureConfig)

Bekannt aus Code, Tests und Spec (Standardwerte laut Spec bzw. Notizen; die tatsächlichen Defaults stehen in `GestureConfig.swift`):

| Schlüssel | Standard (laut Spec/Notizen) | Einheit |
| --- | --- | --- |
| `tapMaxDuration` | 0,25 | s |
| `tapMaxMovement` | 8 | pt |
| `doubleTapInterval` | 0,3 | s |
| `longPressDuration` | 0,6 | s |
| `classifyMovement` | 4 (Spec: 10, geändert laut scroll-tuning.md) | pt |
| `pinchThreshold` | 12 | pt |
| `rotateThreshold` | 8 | ° |
| `momentumMinVelocity` | 50 | pt/s |
| `momentumDecayPerFrame` | 0,96 | Faktor je 60-Hz-Frame |
| `momentumStopVelocity` | 20 | pt/s |
| `swipeDistance` | 60 | pt |
| `swipeMaxDuration` | 0,5 | s |
| `stuckTimeout` | 0,5 | s |
| `velocityWindow` | 0,05 | s |

Werte außerhalb des Bereichs werden beim Lesen geklemmt: Zeiten auf 0–10 s, `momentumDecayPerFrame` auf 0–0,999, `rotateThreshold` auf 0–180°, Distanzen und Geschwindigkeiten auf ≥ 0.

## Umgebungsvariablen

| Variable | Verwendet von | Beschreibung |
| --- | --- | --- |
| `SIGN_IDENTITY` | `Scripts/build-app.sh` | Überschreibt die Signatur-Identität |

Zur Laufzeit liest die App keine Umgebungsvariablen (Annahme aus dem gezeigten Code).

## Kommandozeile `hidrecord`

| Option | Beschreibung |
| --- | --- |
| `--shared` | Gerät nicht exklusiv öffnen |
| `--seconds N` | Nach N Sekunden beenden |
| `--out FILE` | Rohreports als JSON-Zeilen `{"t":ns,"id":reportID,"hex":"…"}` schreiben |

## Build-Skript

`Scripts/build-app.sh [debug|release]` – Standard `release`.

## Logging

Subsystem `org.touchbridge` (Kategorien u. a. `device`, `pipeline`, `inject`, `permissions` laut Spec):

```
log stream --predicate 'subsystem == "org.touchbridge"' --level info
```

## Hooks/Filter

Es gibt keine Hooks oder Filter. App-spezifische Überschreibungen sind nur als Konzept in `docs/superpowers/specs/` beschrieben.
