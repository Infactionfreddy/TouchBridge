# TouchBridge: Design-Spezifikation (Meilenstein 1 und 2)

Stand: 2026-10-12
Status: zur Review

Geschrieben für: Frederic zum Review, danach als verbindliche Vorgabe für den Implementierungsplan.

## 1. Zweck

TouchBridge ist eine quelloffene macOS-App, die ein per USB angeschlossenes Multitouch-Display systemweit nutzbar macht. macOS verarbeitet HID-Touchscreens nativ nur als Single-Touch-Zeiger. TouchBridge übernimmt das Gerät exklusiv, interpretiert alle Finger selbst und speist Mausereignisse und Trackpad-Gesten (Scroll mit Momentum, Pinch, Rotate, Swipes) in macOS ein, so dass alle Apps sie wie von einem Trackpad erhalten.

Vorbild ist der Funktionsumfang kommerzieller Touch-Treiber, wie er in deren öffentlicher Dokumentation beschrieben ist: Treiber-Daemon, Gesten-Interpreter mit Default-Set und App-Overrides, Console mit Kalibrierung, API für eigene Apps. TouchBridge bildet dieses Modell in einem Prozess ab. Der Code ist eine Eigenentwicklung; es wird keine fremde Software analysiert oder übernommen.

Lizenz: MIT. Kein Lizenzschlüssel, keine Bezahlfunktion.

## 2. Ziele und Nicht-Ziele dieser Spec

### Ziele (Meilenstein 1: Core)

- Touchscreen automatisch erkennen, exklusiv öffnen, bei Ab- und Anstecken weiterlaufen.
- Alle Kontakte des Geräts parsen (beim Referenzgerät 10 Finger).
- Digitizer-Koordinaten auf das richtige Display abbilden, Rotation und Kalibrierung berücksichtigen.
- Ein Finger: Cursor folgt, Tap = Klick, Doppeltap = Doppelklick, Bewegung = Drag, langes Halten = Rechtsklick.
- Menüleisten-App mit Ein/Aus, Gerätestatus, Rechtestatus, Login-Item.
- Rechte-Onboarding für Input Monitoring und Accessibility ohne Abbruch bei fehlenden Rechten.

### Ziele (Meilenstein 2: Gesten)

- Zwei Finger: Scroll mit Trackpad-Phasen und Momentum, Pinch als Magnify, Rotate, Zwei-Finger-Tap als Rechtsklick.
- Drei und vier Finger: Swipes in vier Richtungen, standardmäßig auf Mission Control, App Exposé und Spaces-Wechsel gelegt.
- Gesture-Identifier-Fenster, das empfangene Gesten anzeigt, als Debug- und Abnahmewerkzeug.

### Nicht-Ziele (spätere Specs)

- Console mit Kalibrier-Overlay und Geräteliste (nur minimale Einstellungen in dieser Spec).
- Gestensets pro App und pro UI-Element.
- Lokale API für eigene Apps, TUIO-Server.
- Stift-Unterstützung (Druck, Neigung, Radierer).
- Mehrere Touch-Geräte gleichzeitig. Es wird genau ein aktives Gerät unterstützt; die Struktur lässt mehrere zu.
- iPad-artiges Ein-Finger-Scrollen (als spätere Option vorgesehen).
- Andere Betriebssysteme.

## 3. Referenz-Hardware

| Eigenschaft | Wert |
| --- | --- |
| USB Vendor / Product | 0x0712 / 0x000A, Hersteller-String "hotlotus", Produkt "normal Elan" |
| Seriennummer | 20231224X1 |
| USB | Full Speed, eine HID-Schnittstelle, Boot-Protokoll Maus |
| Panel | 52,75 × 29,70 cm physisch, Display 1920 × 1080 bei 60 Hz |
| macOS-Treiber heute | AppleUserHIDEventDriver, erzeugt nur Single-Touch-Zeiger |

Report-Descriptor (Auszug, vollständig in Anhang A):

| Report-ID | Richtung | Inhalt |
| --- | --- | --- |
| 1 | Input | 10 × Finger-Collection: Contact-ID (6 Bit), Tip-Switch (1 Bit), 1 Bit Füllung, X (16 Bit, 0..2976), Y (16 Bit, 0..1680); danach Scan-Time (32 Bit), Contact-Count (8 Bit). 56 Byte inklusive Report-ID. |
| 2 | Feature | Contact-Count-Maximum = 10 |
| 3 | Feature | 256 Byte Hersteller-Blob (Zertifizierung, wird ignoriert) |
| 7 | Input | Maus-Emulation: 3 Tasten, X/Y absolut 16 Bit, Rad. Wird ignoriert. |
| 9 | Input/Output | Hersteller-Collection, 63 Byte ein / 4 Byte aus. Wird ignoriert. |

Das Gerät arbeitet im Parallel-Modus: jeder Report enthält alle Finger, Contact-Count steht am Ende. TouchBridge nutzt ausschließlich Report-ID 1.

## 4. Architektur

### 4.1 Prozessmodell

Eine signierte App mit Menüleisten-Icon (`LSUIElement`), die in der Login-Session des Benutzers läuft. Kein LaunchDaemon, kein root, kein zweiter Prozess. Start beim Login über `SMAppService.mainApp`. Dadurch werden Input Monitoring und Accessibility genau einmal für genau eine Code-Signatur erteilt.

### 4.2 Module

Swift Package am Repo-Root, Swift 6 Sprachmodus, Mindestversion macOS 14.

| Modul | Art | Abhängigkeiten | Inhalt |
| --- | --- | --- | --- |
| TouchCore | Library | Foundation | HID-Descriptor-Parser, Report-Decoder, TouchFrame, TouchTracker, DisplayMapping (reine Mathematik), GestureEngine, Actions, Konfigurationsmodelle. Keine AppKit- oder IOKit-Abhängigkeit, vollständig unit-testbar. |
| TouchDevice | Library | TouchCore, IOKit | DeviceManager: Geräte finden, exklusiv öffnen, Reports empfangen, Hotplug. |
| TouchInject | Library | TouchCore, CoreGraphics | EventInjector: Maus, Scroll, Tastatur über öffentliche API; Magnify und Rotate über die undokumentierten Gesten-Felder. Momentum-Generator. |
| TouchBridge | Executable (SwiftUI) | alle drei | Menüleiste, PermissionCoordinator, Pipeline-Verdrahtung, Einstellungen, Gesture-Identifier-Fenster, Display-Auswahl. |
| hidrecord | Executable (CLI) | TouchDevice | Zeichnet Rohreports als Fixtures auf, dient auch als Machbarkeitsprobe für den exklusiven Zugriff. |

### 4.3 Build, Bundle, Signatur

- `swift build` erzeugt die Binaries; `Scripts/build-app.sh` baut daraus `TouchBridge.app` (Info.plist, Icon, Binary) und signiert mit der lokalen "Apple Development"-Identität (`SIGN_IDENTITY` oder automatisch aus dem Schlüsselbund). Für Releases: "Developer ID Application" plus Notarisierung, gleicher Skriptpfad mit Parameter.
- Bundle-ID: `org.touchbridge.TouchBridge` (änderbar, muss danach stabil bleiben, weil die Rechte daran hängen).
- Installation für den Alltag nach `~/Applications/TouchBridge.app`; `Scripts/install.sh` kopiert und registriert das Login-Item.
- Xcode kann `Package.swift` direkt öffnen; ein `.xcodeproj` wird nicht gepflegt.

## 5. Komponenten

### 5.1 HIDDescriptorParser (TouchCore)

- Eingabe: Descriptor-Bytes (aus der IORegistry-Eigenschaft `ReportDescriptor`).
- Ausgabe: `ReportLayout` je Report-ID mit Feldern: Usage-Page, Usage, Bit-Offset, Bit-Breite, Logical Min/Max, Collection-Pfad.
- Unterstützt Main-Items Input/Feature/Collection/End Collection, Global-Items Usage Page, Logical Min/Max, Report Size/Count/ID, Local-Items Usage/Usage Min/Max. Push/Pop und Designatoren werden nicht benötigt und führen zu einem klaren Fehler.
- Erkennt eine Touch-Screen-Application-Collection (Usage-Page 0x0D, Usage 0x04) und darin Finger-Collections (Usage 0x22) mit Contact-ID (0x51), Tip-Switch (0x42), X (0x01/0x30), Y (0x01/0x31) sowie Contact-Count (0x54) und optional Scan-Time (0x56), In-Range (0x32), Confidence (0x47).

### 5.2 ReportDecoder (TouchCore)

- Eingabe: `ReportLayout`, Rohreport-Bytes, Zeitstempel.
- Ausgabe: `TouchFrame { timestamp: UInt64 (Nanosekunden, monoton), contacts: [Contact { id: Int, x: Int, y: Int, down: Bool }], contactCount: Int }`.
- Es werden nur die ersten `contactCount` Finger-Slots gewertet; Slots ohne Tip-Switch gelten als `down == false`. Hybrid-Modus (Contact-Count 0 in Folgereports) wird akzeptiert: dann werden Slots aller Reports bis zum nächsten Report mit Contact-Count > 0 zusammengeführt.

### 5.3 DeviceManager (TouchDevice)

- Matching: Primary-Usage-Page 0x0D und Primary-Usage 0x04. Keine Vendor-Liste.
- Öffnet jedes passende Gerät mit `kIOHIDOptionsTypeSeizeDevice`. Bei `kIOReturnNotPermitted` meldet er "Input Monitoring fehlt", bei anderen Fehlern "exklusiver Zugriff fehlgeschlagen" und öffnet nicht-exklusiv als Fallback (siehe Abschnitt 11).
- Empfängt Rohreports über `IOHIDDeviceRegisterInputReportCallback` auf einem eigenen Thread mit eigenem RunLoop und reicht `(reportID, bytes, timestamp)` an die Pipeline.
- Liefert für jedes Gerät eine `DeviceInfo { vendorID, productID, product, serial, descriptor }`.
- Hotplug: Matching- und Removal-Callbacks; beim Entfernen wird die Pipeline des Geräts beendet (Abschnitt 11).

### 5.4 DisplayMapper (TouchCore, Display-Auflösung in TouchBridge)

- Eingabe: Kontakt in Digitizer-Einheiten plus `MappingConfig { logicalMaxX, logicalMaxY, displayFrame (globale CG-Koordinaten), orientation: 0/90/180/270, calibration { scaleX, scaleY, offsetX, offsetY } }`.
- Ausgabe: Punkt in globalen CG-Koordinaten (Ursprung oben links des Hauptdisplays, wie CGEvent sie erwartet).
- Orientation dreht die normierten Koordinaten vor der Skalierung. Kalibrierung ist standardmäßig Identität; sie wird je Geräteseriennummer gespeichert.
- Display-Auswahl (in der App): Standard "auto" = erstes Display, das nicht eingebaut ist; sonst eine gespeicherte Display-UUID. Bei Änderungen der Displaykonfiguration wird das Mapping neu berechnet.

### 5.5 TouchTracker (TouchCore)

- Wandelt aufeinanderfolgende `TouchFrame`s in `TouchEvent { id, phase: began/moved/ended, point (gemappt), timestamp }` um.
- Ein Kontakt, der länger als `stuckTimeout` (Standard 500 ms) nicht gemeldet wurde, wird mit `ended` abgeschlossen.
- Hält den aktuellen Satz aktiver Touches als Wert (`TouchSet`), den die GestureEngine liest.

### 5.6 GestureEngine (TouchCore)

Zustandsautomat über der Fingerzahl. Ausgabe sind `Action`s, jede mit Phase (`began`, `changed`, `ended`, `cancelled`) wo sinnvoll:

- `moveCursor(to:)`
- `click(button: left/right, at:, count:)`
- `drag(button: left, phase:, to:)`
- `scroll(phase:, delta: (dx, dy), at:)` und `scrollMomentum(velocity:)` beim Loslassen
- `magnify(phase:, delta:, at:)` mit `delta = distance_now / distance_prev − 1`
- `rotate(phase:, degrees:, at:)` mit mathematisch positivem Drehsinn (gegen den Uhrzeigersinn), wie AppKit
- `swipe(fingers: 3/4, direction: up/down/left/right)`

Regeln des Default-Sets:

| Situation | Verhalten |
| --- | --- |
| 1 Finger down | `moveCursor` auf den Punkt. Kein Maus-Down (verzögerter Down). |
| 1 Finger up, Dauer ≤ `tapMaxDuration`, Weg ≤ `tapMaxMovement` | `click(left, count: 1)`; zweiter Tap innerhalb `doubleTapInterval` und `tapMaxMovement` ergibt `count: 2` |
| 1 Finger bewegt sich über `tapMaxMovement` | `drag(began)` am Startpunkt, dann `drag(changed)`; up ergibt `drag(ended)` |
| 1 Finger ruht länger als `longPressDuration` ohne Bewegung | `click(right)` am Punkt; der Kontakt ist danach verbraucht, kein Drag mehr |
| 2 Finger down | Klassifikationsphase: bis eine Hand `classifyMovement` zurückgelegt hat, wird nichts gesendet |
| 2 Finger, Abstandsänderung ≥ `pinchThreshold` zuerst | Pinch: `magnify(began …)`, ab dann nur Magnify bis ein Finger hebt |
| 2 Finger, Winkeländerung ≥ `rotateThreshold` zuerst | Rotate: `rotate(began …)`, ab dann nur Rotate |
| 2 Finger, sonst Bewegung ≥ `classifyMovement` | Scroll: `scroll(began …)`, Delta = Mittelpunktbewegung; Inhalt folgt den Fingern (Natural), invertierbar |
| 2 Finger heben ohne Klassifikation innerhalb `tapMaxDuration` | `click(right)` am Mittelpunkt |
| 2 Finger heben nach Scroll mit Geschwindigkeit ≥ `momentumMinVelocity` | `scrollMomentum(velocity)`; ein neuer Kontakt bricht das Momentum ab |
| 3 oder 4 Finger, Weg ≥ `swipeDistance` innerhalb `swipeMaxDuration`, dominante Achse | genau ein `swipe`; danach ignoriert bis alle Finger heben |
| Fingerzahl wechselt mitten in einer Geste | laufende Geste wird mit `ended` abgeschlossen, neue Klassifikation beginnt |

Parameter mit Standardwerten (alle in `GestureConfig`, über die Einstellungsdatei änderbar):

| Parameter | Standard |
| --- | --- |
| tapMaxDuration | 250 ms |
| tapMaxMovement | 8 pt |
| doubleTapInterval | 300 ms |
| longPressDuration | 600 ms |
| classifyMovement | 10 pt |
| pinchThreshold | 12 pt Abstandsänderung |
| rotateThreshold | 8° |
| momentumMinVelocity | 50 pt/s |
| momentumDecayPerFrame | 0,96 bei 60 Hz |
| momentumStopVelocity | 20 pt/s |
| swipeDistance | 60 pt |
| swipeMaxDuration | 500 ms |
| stuckTimeout | 500 ms |

Die Engine ist deterministisch: gleiche Eingabefolge mit gleichen Zeitstempeln ergibt gleiche Actions. Zeit kommt ausschließlich aus den Eingaben, nie aus Systemuhren, damit Tests reproduzierbar sind. Eingaben sind `TouchFrame`s und zusätzlich `tick(timestamp)`-Aufrufe: Die Pipeline ruft `tick` alle 20 ms auf, solange mindestens ein Kontakt aktiv ist oder eine Geste offen ist. Long-Press, Doppeltap-Fenster und Stuck-Timeout werden aus Frames und Ticks abgeleitet, denn ein Panel sendet keine Reports mehr, sobald es keinen Finger mehr sieht, und ein verlorener Abschluss-Report darf keinen Kontakt dauerhaft hängen lassen.

### 5.7 ActionRouter (TouchCore)

- Eingabe: `Action`, Kontext `{ frontmostBundleID }`.
- Ausgabe: `Command`s für den Injector. In dieser Spec ist die Zuordnung das Default-Set ohne Overrides: Maus-Actions 1:1, `magnify`/`rotate` 1:1, `swipe` auf Tastenkürzel: 3 oder 4 Finger hoch = Mission Control (Ctrl+↑), runter = App Exposé (Ctrl+↓), links/rechts = Space wechseln (Ctrl+←/→).
- Die Schnittstelle nimmt bereits den Bundle-Identifier entgegen, damit App-Overrides später ohne Umbau eingehängt werden können.

### 5.8 EventInjector (TouchInject)

Öffentliche API:

- Maus: `CGEvent(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)`, Klickzähler über `mouseEventClickState`, Post an `kCGHIDEventTap`.
- Scroll: `CGEvent(scrollWheelEvent2Source:units: .pixel …)`, Felder `scrollWheelEventIsContinuous = 1`, `scrollWheelEventScrollPhase` (began 1, changed 2, ended 4), `scrollWheelEventMomentumPhase` (begin 1, continue 2, end 3). Momentum erzeugt der Injector selbst mit einem 60-Hz-Timer aus der Abhebegeschwindigkeit.
- Tastatur: `CGEvent(keyboardEventSource:virtualKey:keyDown:)` mit Modifier-Flags.

Undokumentierte Gesten-Events (Magnify, Rotate):

- Basis ist ein `mouseMoved`-Event an der Cursorposition (gültiger Zeitstempel), dann Typ 29 (Gesture) setzen, Feld 110 = HID-Typ (Zoom 8, Rotation 5), Feld 113 = Zoom-Delta (Double), Feld 114 = Rotation in Grad (Double), Feld 132 = Phase (began 1, changed 2, ended 4, cancelled 8). Quellen: WebKit `CoreGraphicsTestSPI.h` (Feldnummern 110, 113, 114, 115, 132) und die Open-Source-App Touch-Up, die zusätzlich die Felder 55 = 29, 50 = 248 und 101 = 4 setzt; deren Bedeutung ist nicht dokumentiert und wird im Plan empirisch mit dem Gesture-Identifier geprüft.
- Alle undokumentierten Feldnummern stehen in genau einer Datei `GestureEventFields.swift` mit Quellenangabe.

Alle eigenen Events tragen eine Markierung in `eventSourceUserData`, damit ein eventueller Event-Tap (Plan B) sie von Systemereignissen unterscheiden kann.

### 5.9 PermissionCoordinator (TouchBridge)

- Input Monitoring: `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` zur Anzeige, `IOHIDRequestAccess` zum Anfordern.
- Accessibility: `AXIsProcessTrustedWithOptions` mit Prompt.
- Öffnet die passenden Bereiche der Systemeinstellungen über `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent` und `?Privacy_Accessibility`.
- Pollt den Status alle 2 s, solange etwas fehlt, und startet die Pipeline automatisch, sobald beides erteilt ist.

### 5.10 Menüleiste und Fenster (TouchBridge)

- Menü: Status (Gerät erkannt / exklusiv / Rechte), Schalter "Touch aktiv", Display-Auswahl, "Gesture Identifier öffnen", "Einstellungen öffnen" (öffnet die JSON-Datei im Editor), "Beim Login starten", "Beenden".
- Gesture-Identifier-Fenster: eine Ansicht, die `magnify(with:)`, `rotate(with:)`, `scrollWheel(with:)` und Mausereignisse empfängt und die letzten Ereignisse mit Phase und Werten listet. Zeigt zusätzlich live die aktiven Kontakte des Panels als Punkte. Dient Abnahme und Fehlersuche.

## 6. Datenfluss und Threading

```
USB-Report (~100 Hz)
  → DeviceManager (HID-Thread)
  → Pipeline-Queue (seriell): ReportDecoder → DisplayMapper → TouchTracker → GestureEngine → ActionRouter → EventInjector
  → CGEventPost
```

- Genau eine serielle `DispatchQueue` pro Gerät für die gesamte Verarbeitung; der 20-ms-Tick-Timer für TouchTracker und GestureEngine sowie der 60-Hz-Momentum-Timer des Injectors laufen als `DispatchSourceTimer` auf derselben Queue. Der Tick-Timer läuft nur, solange Kontakte aktiv oder Gesten offen sind.
- `CGEventPost` wird von der Pipeline-Queue aufgerufen. UI-Zustand (Status, Identifier-Liste) wird per `@MainActor`-Observable aktualisiert.
- Zustand der GestureEngine ist ein Wert, der ausschließlich auf der Pipeline-Queue mutiert wird; alle Modelle in TouchCore sind `Sendable`.

## 7. Einstellungen und Persistenz

- Datei `~/Library/Application Support/TouchBridge/settings.json`, Codable, mit `schemaVersion`.
- Inhalt: `enabled`, `displaySelection` (`auto` oder Display-UUID), `naturalScrolling`, `gesture` (GestureConfig), `calibrations` (Map Seriennummer → Orientation, Scale, Offset), `launchAtLogin`.
- Fehlende oder defekte Datei: Standardwerte verwenden, defekte Datei als `.broken` beiseite legen und neu schreiben.

## 8. Rechte und Installation

1. `Scripts/build-app.sh` bauen und signieren, `Scripts/install.sh` nach `~/Applications` kopieren.
2. Erster Start: Menüleisten-Icon rot, Onboarding-Fenster mit zwei Buttons für die beiden Rechte.
3. Nach Erteilung startet die Pipeline ohne Neustart. Icon grün, sobald ein Gerät exklusiv läuft.

## 9. Fehlerbehandlung

| Fall | Verhalten |
| --- | --- |
| Gerät abgesteckt | Laufende Geste `cancelled`, gedrückte Maustaste wird gelöst, Momentum gestoppt, Status "kein Gerät", Pipeline-Queue wird verworfen. |
| Gerät wieder da | Neue Pipeline, Kalibrierung per Seriennummer laden. |
| Exklusiver Zugriff scheitert | Nicht-exklusiv öffnen, Status gelb mit Hinweis "Cursor wird doppelt gesteuert", Plan B aus Abschnitt 12 anbieten. |
| Rechte entzogen zur Laufzeit | Status rot, Onboarding erneut anzeigen, Pipeline anhalten, kein Beenden. |
| Displaykonfiguration ändert sich | `CGDisplayRegisterReconfigurationCallback` → Mapping neu berechnen; verschwindet das gewählte Display, Rückfall auf `auto`. |
| Hängender Kontakt | nach `stuckTimeout` als `ended` behandelt. |
| Descriptor nicht parsebar | Gerät wird mit Fehlermeldung im Status ignoriert; Log enthält die Descriptor-Bytes. |
| Schlafen/Aufwachen | Beim Aufwachen alle Gesten zurücksetzen und Geräte neu öffnen. |

Logging über `os.Logger`, Subsystem `org.touchbridge`, Kategorien `device`, `pipeline`, `inject`, `permissions`. Keine Rohkoordinaten im Default-Level, nur bei `debug`.

## 10. Tests und Abnahme

### Unit-Tests (TouchCore, ohne Hardware)

- HIDDescriptorParser: Elan-Descriptor aus Anhang A ergibt das Layout aus Abschnitt 3; ein zweiter, synthetischer Descriptor mit 5 Fingern und Hybrid-Modus.
- ReportDecoder: aufgezeichnete Rohreports des Panels (Fixtures aus `hidrecord`, JSON-Zeilen mit Zeitstempel und Hex) ergeben erwartete Frames; Grenzfälle: 0 Kontakte, 10 Kontakte, Tip-Switch-Wechsel ohne Positionsänderung.
- TouchTracker: began/moved/ended, Stuck-Timeout.
- DisplayMapper: alle vier Orientierungen, Kalibrier-Offsets, Display rechts vom Hauptdisplay, Display mit negativem Ursprung.
- GestureEngine: je ein Szenario pro Zeile der Tabelle in 5.6, dazu "Fingerzahl wechselt", "Pinch dann Scroll nach Neuaufsetzen", "Momentum durch neuen Kontakt abgebrochen". Die Szenarien sind als Kontaktfolgen mit Zeitstempeln formuliert und prüfen die exakte Action-Folge.
- ActionRouter: Default-Zuordnung.

### Manuelle Abnahme (mit Panel)

1. `hidrecord --seize`: Cursor bewegt sich bei Berührung nicht mehr, Reports kommen an. (Erste Aufgabe des Plans.)
2. Gesture-Identifier zeigt Tap, Doppeltap, Drag, Rechtsklick, Scroll mit Phasen und Momentum, Magnify, Rotate, Swipes mit korrekten Vorzeichen.
3. Safari: Pinch zoomt die Seite, Zwei-Finger-Scroll läuft mit Momentum aus, Zwei-Finger-Tap öffnet das Kontextmenü.
4. Vorschau: Pinch und Rotate auf einem Bild.
5. Finder: Drag einer Datei, Doppeltap öffnet.
6. Drei-Finger-Swipe hoch öffnet Mission Control.
7. Ab- und Anstecken während einer Geste hinterlässt keine gedrückte Maustaste.
8. Nach Neustart startet die App automatisch und läuft ohne erneute Rechtefreigabe.

## 11. Risiken und Plan B

- **Undokumentierte Gesten-Felder.** Können mit einem macOS-Update brechen. Gegenmaßnahme: eine Datei, ein Test im Identifier, Versions-Hinweis im README. Maus, Scroll und Tastenkürzel bleiben davon unberührt.
- **Exklusiver Zugriff auf macOS 26.** Wird zuerst geprüft. Plan B: ein `CGEventTap` auf Session-Ebene, der während aktiver Berührung alle Mausereignisse ohne TouchBridge-Markierung verwirft. Nachteil: eine echte Maus ist während der Berührung stumm.
- **Keine rohen Touches für fremde Apps.** Systembedingt; eigene Apps bekommen sie später über die API.
- **Scroll-Vorzeichen.** Ob die Natural-Scrolling-Einstellung des Systems auf synthetische Events wirkt, wird empirisch geklärt; die Einstellung `naturalScrolling` deckt beide Fälle ab.

## 12. Vorbereitete Erweiterungen (nicht Teil dieser Spec)

- Console: Kalibrier-Overlay mit Zielpunkten, Geräteliste, Einstellungs-UI. Nutzt `DisplayMapper.calibration` und `settings.json`.
- App-Overrides: `ActionRouter` erhält Regelsätze je Bundle-ID; Gestensets als JSON im Settings-Ordner.
- API: Unix-Domain-Socket mit JSON-Zeilen, ein Event je Touch mit Contact-ID, Bildschirmkoordinaten und Phase, dazu Frames. Speist sich aus `TouchTracker`-Ausgaben.
- TUIO: UDP-Server auf Basis derselben Daten.

## Anhang A: Report-Descriptor des Referenzgeräts

Quelle: IORegistry-Eigenschaft `ReportDescriptor` des Geräts "normal Elan", ausgelesen am 2026-10-12.

```
05 0d 09 04 a1 01 85 01
  [10 × Finger-Collection]
  09 22 a1 02 05 0d 95 01 75 06 09 51 15 00 25 3f 81 02
  09 42 25 01 75 01 95 01 81 02 75 01 95 01 81 03
  05 01 75 10 55 0e 65 11 09 30 26 a0 0b 35 00 46 9b 14 81 42
  09 31 26 90 06 46 9a 0b 81 42 c0
  [Ende der 10 Finger-Collections]
  05 0d 09 56 55 00 65 00 27 ff ff ff 7f 95 01 75 20 81 02
  09 54 25 7f 95 01 75 08 81 02
  85 02 09 55 25 0a b1 02
  06 00 ff 09 c5 85 03 15 00 26 ff 00 75 08 96 00 01 b1 02
c0
06 00 ff 09 01 a1 01 85 09 09 01 15 00 26 ff 00 95 3f 75 08 81 02
  09 01 15 00 26 ff 00 95 04 75 08 91 02 c0
05 01 09 02 a1 01 85 07 09 01 a1 00 05 09 19 01 29 03 15 00 25 01 75 01 95 03 81 02
  75 01 95 05 81 03 05 01 09 30 75 10 95 01 55 0e 65 11 35 00 46 79 08 26 a0 0b 81 02
  09 31 46 8a 03 26 90 06 81 02 09 38 15 81 25 7f 75 08 95 01 81 06 c0 c0
```

Vollständige Rohbytes (für die Test-Fixture):

```
050d0904a10185010922a102050d9501750609511500253f81020942250175019501810275019501810305017510550e6511093026a00b3500469b1481420931269006469a0b8142c0
050d0922a102050d9501750609511500253f81020942250175019501810275019501810305017510550e6511093026a00b3500469b1481420931269006469a0b8142c0
050d0922a102050d9501750609511500253f81020942250175019501810275019501810305017510550e6511093026a00b3500469b1481420931269006469a0b8142c0
050d0922a102050d9501750609511500253f81020942250175019501810275019501810305017510550e6511093026a00b3500469b1481420931269006469a0b8142c0
050d0922a102050d9501750609511500253f81020942250175019501810275019501810305017510550e6511093026a00b3500469b1481420931269006469a0b8142c0
050d0922a102050d9501750609511500253f81020942250175019501810275019501810305017510550e6511093026a00b3500469b1481420931269006469a0b8142c0
050d0922a102050d9501750609511500253f81020942250175019501810275019501810305017510550e6511093026a00b3500469b1481420931269006469a0b8142c0
050d0922a102050d9501750609511500253f81020942250175019501810275019501810305017510550e6511093026a00b3500469b1481420931269006469a0b8142c0
050d0922a102050d9501750609511500253f81020942250175019501810275019501810305017510550e6511093026a00b3500469b1481420931269006469a0b8142c0
050d0922a102050d9501750609511500253f81020942250175019501810275019501810305017510550e6511093026a00b3500469b1481420931269006469a0b8142c0
050d09565500650027ffffff7f9501752081020954257f95017508810285020955250ab1020600ff09c58503150026ff007508960001b102c0
0600ff0901a10185090901150026ff00953f750881020901150026ff00950475089102c0
05010902a10185070901a100050919012903150025017501950381027501950581030501093075109501550e6511350046790826a00b81020931468a03269006810209381581257f750895018106c0c0
```

(Zeilenumbrüche nur zur Lesbarkeit; die Fixture enthält die Bytes fortlaufend.)

## Anhang B: Quellen

- Apple, HIDDriverKit und IOHIDFamily (Digitizer-Usages, IOHIDManager): developer.apple.com/documentation/hiddriverkit
- USB-IF, HID Usage Tables, Digitizer-Page 0x0D
- WebKit, `Tools/TestRunnerShared/spi/CoreGraphicsTestSPI.h` (Gesten-Feldnummern)
- Touch-Up (RWTH Aachen, MIT-Lizenz), `TouchUpCore/TUCCursorUtilities.m` (Gesten-Event-Rezept)
- Öffentliche Dokumentation kommerzieller Touch-Treiber (Funktionsumfang als Messlatte): support.touch-base.com/commander/introduction, support.touch-base.com/Documentation/50394/Gesture-settings
