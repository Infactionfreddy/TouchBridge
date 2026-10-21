# TouchBridge: Gestenprofile und Einstellungsfenster (Teil A)

Stand: 2026-10-21
Status: zur Review
Baut auf: `2026-10-12-touchbridge-design.md` (Meilensteine 1 und 2, umgesetzt und abgenommen)

Geschrieben für: Frederic zum Review, danach als verbindliche Vorgabe für den Implementierungsplan.

## 1. Zweck

TouchBridge soll Gesten je Programm unterschiedlich belegen und abstimmen können, nach dem Vorbild der
UPDD-Gesten-Software: ein Standard-Gestenset plus Profile je App, jede Geste mit Aktion und Optionen,
alle Zeiten und Schwellen je Profil anpassbar. Die Bedienung erfolgt in einem Einstellungsfenster; die
JSON-Datei bleibt als Expertenweg erhalten.

Dies ist Teil A von drei Teilprojekten:

- **A (diese Spec)**: Profile, Aktionsmodell, Einstellungsfenster, Vordergrund-App-Erkennung. Gilt für
  die heute erkannten Gesten; der Gestenkatalog enthält bereits alle UPDD-Gesten.
- **B (spätere Spec)**: Drei-, Vier-, Fünf-Finger-Tap, -Doppeltap, -Drag; Zwei-Finger-Doppeltap;
  Fünf-Finger-Swipes; Press and Tap.
- **C (spätere Spec)**: Rand-Swipes, Vier-/Fünf-Finger-Squeeze und -Splay, Pinch/Spread und Rotate als
  diskrete Aktionen.

Nicht übernommen: UPDD-Gesten mit Druck (Force Press, Force Drag); das Referenzpanel liefert keinen Druck.

## 2. Entscheidungen aus dem Brainstorming

| Frage | Entscheidung |
| --- | --- |
| Was unterscheidet sich je App | Zuordnung der Gesten und alle Zeiten/Schwellen (`GestureConfig`), nicht überschriebene Werte erben |
| Aktionsziele | Maus (links/rechts/mitte/zurück/vor, 1–3 Klicks), Tastenkürzel, Systemaktion, Datei/Programm öffnen, nichts, Durchreichen |
| Gestenliste | Voller UPDD-Katalog im Datenmodell; nicht erkannte Arten in der UI ausgegraut |
| App hinzufügen | Datei-Dialog auf `/Applications`, Schlüssel ist die Bundle-ID |
| Abschalten je App | nicht in Teil A |
| Sprache der UI | Englisch |
| Architektur | Profile als Overlay im `ActionRouter`, ein Settings-Dokument (Schema 2), SwiftUI-Fenster |

## 3. Datenmodell (TouchCore)

Alle Typen sind `Codable`, `Equatable`, `Sendable`, ohne System-Zugriff.

### 3.1 GestureKind

Enum mit stabilen String-RawValues für JSON. Vollständiger Katalog:

| Gruppe | Arten |
| --- | --- |
| Ein Finger | `tap`, `doubleTap`, `press`, `pressAndTap`, `drag` |
| Zwei Finger | `twoFingerTap`, `twoFingerDoubleTap`, `twoFingerDrag` (= Scroll), `twoFingerSwipeUp/Down/Left/Right` |
| Drei Finger | `threeFingerTap`, `threeFingerDoubleTap`, `threeFingerDrag`, `threeFingerSwipeUp/Down/Left/Right` |
| Vier Finger | `fourFingerTap`, `fourFingerDoubleTap`, `fourFingerDrag`, `fourFingerSwipeUp/Down/Left/Right`, `fourFingerSqueeze`, `fourFingerSplay` |
| Fünf Finger | `fiveFingerTap`, `fiveFingerDoubleTap`, `fiveFingerDrag`, `fiveFingerSwipeUp/Down/Left/Right`, `fiveFingerSqueeze`, `fiveFingerSplay` |
| Zwei-Finger-Form | `pinch`, `spread`, `rotateLeft`, `rotateRight` |
| Rand | `oneFingerEdgeSwipeFromLeft`, `oneFingerEdgeSwipeFromRight`, `twoFingerEdgeSwipeFromLeft`, `twoFingerEdgeSwipeFromRight` |

Jede Art hat `displayName` (Englisch), `fingerGroup` für die UI-Gruppierung und `isRecognized`. In Teil A
sind achtzehn Arten erkannt: `tap`, `doubleTap`, `press`, `drag`, `twoFingerTap`, `twoFingerDrag`, `pinch`, `spread`,
`rotateLeft`, `rotateRight`, `threeFingerSwipe*`, `fourFingerSwipe*`.

### 3.2 GestureAction

```
enum GestureAction {
  case none                       // Geste wird verworfen
  case passThrough                // natives Verhalten wie heute (Cursor, Klick, Drag, Scroll, Magnify, Rotate)
  case mouseClick(button: MouseButton, count: Int)   // MouseButton: left, right, middle, back, forward; count 1…3
  case keystroke(KeyCommand)
  case systemAction(SystemAction) // missionControl, appExpose, spaceLeft, spaceRight, showDesktop
  case openFile(path: String)
}
```

`MouseButton` wird um `middle`, `back`, `forward` erweitert. Systemaktionen werden im Router auf ihre
Standard-Tastenkürzel abgebildet (⌃↑, ⌃↓, ⌃←, ⌃→, F11); wer andere Kürzel eingestellt hat, nutzt
`keystroke`.

### 3.3 GestureBinding

`enabled: Bool`, `action: GestureAction`, `naturalScrolling: Bool?`, `momentum: Bool?`. Die beiden
Optionen gelten nur für `twoFingerDrag`; andere Arten ignorieren sie.

### 3.4 Standardbindungen

Das eingebaute Standardverhalten (vor jeder Benutzeränderung) entspricht dem heutigen Default-Set:

| Art | Bindung |
| --- | --- |
| `tap`, `doubleTap`, `drag`, `twoFingerDrag`, `pinch`, `spread`, `rotateLeft`, `rotateRight` | `passThrough` |
| `press`, `twoFingerTap` | `passThrough` (= Rechtsklick) |
| `threeFingerSwipeUp`, `fourFingerSwipeUp` | `systemAction(missionControl)` |
| `threeFingerSwipeDown`, `fourFingerSwipeDown` | `systemAction(appExpose)` |
| `threeFingerSwipeLeft`, `fourFingerSwipeLeft` | `systemAction(spaceRight)` |
| `threeFingerSwipeRight`, `fourFingerSwipeRight` | `systemAction(spaceLeft)` |
| alle nicht erkannten Arten | `none` |

`twoFingerDrag` hat `naturalScrolling = true`, `momentum = true`.

### 3.5 GestureConfigOverrides

Spiegel von `GestureConfig` mit allen Feldern optional (`nil` = erben). `apply(to:)` liefert eine
vollständige `GestureConfig`; Werte werden dabei wie bisher geklemmt.

### 3.6 GestureProfile

`bundleID: String?` (nil nur für das Standardprofil), `displayName: String`, `bindings: [GestureKind:
GestureBinding]` (nur Abweichungen), `config: GestureConfigOverrides`.

### 3.7 Settings, Schema 2

```
schemaVersion: 2
enabled, displaySelection, launchAtLogin, calibrations   (unverändert)
defaultProfile: GestureProfile                            (bundleID nil)
appProfiles: [GestureProfile]                             (eindeutige bundleIDs, sortiert nach displayName)
```

Die Schema-1-Felder `gesture` und `naturalScrolling` entfallen; siehe Migration (Abschnitt 7).

### 3.8 ProfileResolver

`effective(for bundleID: String?) -> EffectiveProfile` mit `config: GestureConfig`, `bindings:
[GestureKind: GestureBinding]` (vollständig, alle Arten), `profileName: String`. Auflösung Feld für Feld:
eingebaute Standardwerte ⟵ Standardprofil ⟵ App-Profil. Ohne passendes App-Profil oder bei `nil`
gilt das Standardprofil. Reine Funktion, deterministisch.

## 4. Router und Engine-Anbindung

- Die `GestureEngine` bleibt unverändert und liefert weiterhin `Action`s. Je Pipeline bekommt sie die
  effektive `GestureConfig` der Vordergrund-App.
- `ActionRouter` nimmt ein `EffectiveProfile` statt `naturalScrolling: Bool`. Zuordnung Action → Art:

| Action | Art |
| --- | --- |
| `moveCursor` | immer durchgereicht (Cursor folgt dem Finger) |
| `click(left, count 1)` | `tap`; `count 2` → `doubleTap` |
| `click(right)` aus langem Druck | `press` |
| `click(right)` aus Zwei-Finger-Tap | `twoFingerTap` |
| `drag` | `drag` |
| `scroll`, `scrollMomentum`, `cancelMomentum` | `twoFingerDrag` |
| `magnify` (delta > 0 / < 0) | `spread` / `pinch` |
| `rotate` (Grad > 0 / < 0) | `rotateLeft` / `rotateRight` |
| `swipe(3/4, Richtung)` | `threeFingerSwipe…` / `fourFingerSwipe…` |

  Damit der Router `press` von `twoFingerTap` unterscheiden kann, erhält `Action.click` ein Feld
  `source: ClickSource` (`tap`, `longPress`, `twoFingerTap`). Die Engine setzt es; bestehende Tests
  werden entsprechend ergänzt.
- Bindungsauswertung: `enabled == false` oder `none` verwirft die Action. Bei Phasen-Gesten (`drag`,
  `scroll`, `magnify`, `rotate`) gilt die Entscheidung der `began`-Phase für die ganze Geste, damit kein
  halber Drag entsteht. `passThrough` erzeugt dieselben Commands wie heute. `mouseClick` erzeugt
  `Command.click(button, at, count)` am Gestenort (bei Swipes am Cursor). `keystroke` und `systemAction`
  erzeugen `Command.key`. `openFile` erzeugt `Command.openFile(path)`.
- Für `twoFingerDrag` liefert die Bindung Scrollrichtung (`naturalScrolling`) und Momentum (`momentum
  == false` unterdrückt `scrollMomentum`). In Teil A ist für `pinch`, `spread`, `rotateLeft`,
  `rotateRight` nur `passThrough` oder `none` wirksam; andere Aktionen zeigt die UI als „available in a
  later version" an (Teil C).
- Neue `Command`-Fälle: `click` mit `middle`, `back`, `forward` (Injector: `otherMouseDown/Up`,
  Button-Nummern 2, 3, 4); `openFile(path)` wird im App-Layer über `NSWorkspace.open` ausgeführt, der
  Injector bleibt reines CGEvent.
- `FrontmostAppObserver` (App-Layer, Main Actor): beobachtet
  `NSWorkspace.didActivateApplicationNotification`, liefert die Bundle-ID. `PipelineController` löst das
  effektive Profil auf und reicht es an alle Pipelines, die auf ihrer Queue `ActionRouter` und
  `engine.config` tauschen. Ein Wechsel mitten in einer Geste wirkt ab der nächsten Entscheidung;
  laufende Phasen werden nicht abgebrochen.
- TouchBridge selbst (Bundle-ID der App) nutzt immer das Standardprofil, damit man sich beim
  Konfigurieren nicht aussperrt. Unbekannte Vordergrund-App → Standardprofil.

## 5. Einstellungsfenster (TouchBridge-App, SwiftUI, Englisch)

- Menüpunkt „Settings…" ersetzt „Open settings file"; die Datei bleibt über „Advanced → Open settings
  file" im Fenster erreichbar. Anzeige über `Windows.shared`.
- **Seitenleiste**: „Default" und die App-Profile mit Icon und Name aus dem Bundle (`NSWorkspace`), unten
  „+" (Datei-Dialog auf `/Applications`, akzeptiert `.app`, liest die Bundle-ID; doppelte Bundle-ID wählt
  das vorhandene Profil) und „−" (mit Rückfrage). Nicht installierte Apps zeigen ein generisches Icon
  und „(not installed)".
- **Kopfzeile**: aktive Vordergrund-App und das gerade geltende Profil.
- **Tab Gestures**: Tabelle mit Spalten *Gesture*, *Enabled*, *Action*, *Options*, gruppiert nach
  Fingerzahl (One finger, Two fingers, Three fingers, Four fingers, Five fingers, Edges). Nicht erkannte
  Arten ausgegraut, Tooltip „Not recognized yet". *Action* ist ein Popup: Pass through, None, Mouse click
  ▸ (Left/Right/Middle/Back/Forward × 1/2/3 clicks), Keyboard shortcut… (Aufnahmefeld), System ▸
  (Mission Control, App Exposé, Space left, Space right, Show desktop), Open file… (Datei-Dialog).
  *Options*: bei `twoFingerDrag` die Schalter *Natural scrolling* und *Momentum*. In App-Profilen zeigt
  jede Zeile, ob sie erbt (grauer Text „Default") oder überschrieben ist; Kontextmenü „Reset to default".
- **Tab Tuning**: Formular mit allen `GestureConfig`-Feldern als Zahlenfeld plus Stepper, Einheit (s, pt,
  °, pt/s) und Standardwert als Platzhalter. In App-Profilen hat jede Zeile eine Checkbox *Override*;
  ohne Häkchen gilt der geerbte Wert ausgegraut. „Restore defaults" je Tab setzt das Profil zurück.
- **Kurzbefehl-Aufnahme**: kleiner `NSView` (`NSViewRepresentable`), liest `keyDown` und
  `flagsChanged`, liefert `KeyCommand` (Key-Code plus Modifier) und Anzeigetext (z. B. „⌘["). Escape
  bricht ab, Delete löscht. Kürzel ohne Modifier sind erlaubt, die UI warnt.
- **Verhalten**: Jede Änderung wird sofort gespeichert und live an die Pipelines gegeben (bestehender
  `saveSettings`-Weg). Kein OK/Abbrechen.

## 6. Datenfluss

```
NSWorkspace didActivate → FrontmostAppObserver → PipelineController.frontmostChanged(bundleID)
  → ProfileResolver.effective(for:) → jede DevicePipeline (queue): router = ActionRouter(profile), engine.config = profile.config
Settings-Fenster → AppState.settings (Main Actor) → saveSettings → PipelineController.updateSettings → wie oben neu auflösen
```

## 7. Migration und Fehlerbehandlung

- `SettingsStore.load()` erkennt Schema 1 und baut Schema 2: `gesture` wird zur vollständigen
  `config`-Überschreibung des Standardprofils, `naturalScrolling` zur Option der `twoFingerDrag`-Bindung.
  Vor dem Zurückschreiben wird die alte Datei als `settings.json.v1` kopiert. Das Ergebnis wird sofort
  gespeichert.
- Unbekannte `GestureKind`-Schlüssel oder Aktionen in Profilen: Schlüssel werden ignoriert und beim
  Speichern entfernt, unbekannte Aktionen fallen auf `passThrough` zurück. Zahlen werden geklemmt wie
  bisher. Eine defekte Datei wird wie heute beiseitegelegt (`.broken`) und durch Standardwerte ersetzt.
- `openFile` mit nicht existierender Datei: Aktion wird mit Log-Eintrag (`pipeline`) übersprungen; die
  Zeile zeigt ein Warnsymbol.
- Vordergrund-App unbekannt (noch kein Ereignis): Standardprofil.

## 8. Tests und Abnahme

Unit-Tests (TouchCore, ohne Hardware):

- `GestureKind`: Katalog vollständig, RawValues stabil (Snapshot-Liste), `isRecognized` für genau die
  achtzehn Arten aus 3.1.
- `ProfileResolver`: Erbfolge Feld für Feld für Bindungen und Config; App-Profil ohne Abweichungen
  liefert exakt das Standardprofil; `nil` und unbekannte Bundle-ID liefern das Standardprofil.
- `ActionRouter`: `passThrough` erzeugt für jede Action dieselben Commands wie heute (bestehende Tests
  bleiben grün); `none` und `enabled == false` verwerfen Phasen-Gesten vollständig; `mouseClick`,
  `keystroke`, `systemAction`, `openFile` erzeugen die richtigen Commands; `momentum == false`
  unterdrückt `scrollMomentum`; `press` und `twoFingerTap` werden über `ClickSource` getrennt.
- Migration Schema 1 → 2: alte Datei mit `gesture` und `naturalScrolling` ergibt das erwartete
  Standardprofil, `settings.json.v1` existiert, Schema 2 wird geschrieben; Rundreise Schema 2.
- Codable-Rundreise aller Profile mit allen Aktionsarten.

Unit-Tests (TouchInject): `middle`, `back`, `forward` erzeugen `otherMouseDown/Up` mit Button-Nummern
2, 3, 4 und `mouseEventClickState`.

Manuelle Abnahme: Profil für Safari anlegen, `threeFingerSwipeLeft` auf ⌘[ legen → Safari geht zurück,
Finder wechselt weiter den Space; Press-Dauer nur in Safari auf 1 s → langer Druck in Safari später,
in Finder unverändert; Profil löschen → Standard gilt wieder; Zwei-Finger-Tap auf Mitteltaste legen →
Link öffnet in neuem Tab; alte `settings.json` (Schema 1) wird beim Start migriert, `settings.json.v1`
liegt daneben; Kopfzeile zeigt die aktive App beim Wechsel.

## 9. Vorbereitete Erweiterungen (Teil B und C)

- Teil B ergänzt Engine-Zustände für Mehrfinger-Taps und -Drags und setzt `isRecognized` für die neuen
  Arten; Router und UI brauchen keine Änderung.
- Teil C ergänzt Rand-Erkennung (Startpunkt innerhalb eines Randbereichs des Displays) sowie
  Squeeze/Splay und diskrete Pinch/Rotate-Aktionen (Schwellen in `GestureConfig`).
- Export/Import einzelner Profile als JSON-Datei, falls Teilen gewünscht ist.
