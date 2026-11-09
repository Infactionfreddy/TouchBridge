# Installation

[← Zurück zur README](../README.md)

## Voraussetzungen

- macOS 14 oder neuer
- Xcode 16 oder neuer (Swift 6 Toolchain), Kommandozeilen-Tools
- USB-Touchscreen als HID-Digitizer (Usage Page 0x0D / Usage 0x04)
- Eine Code-Signatur-Identität (z. B. „Apple Development"). Die Rechte (Input Monitoring, Accessibility) hängen an der Signatur; sie sollte stabil bleiben.

## Schritt für Schritt

1. Repository klonen:
   ```
   git clone https://github.com/Infactionfreddy/TouchBridge.git
   cd TouchBridge
   ```
2. App bauen und signieren (Standard: Konfiguration `release`):
   ```
   SIGN_IDENTITY="Apple Development: Dein Name (TEAMID)" Scripts/build-app.sh
   ```
   Ohne `SIGN_IDENTITY` wird die im Skript hinterlegte Identität verwendet, die auf anderen Rechnern vermutlich nicht existiert. Ergebnis: `dist/TouchBridge.app`.
3. Installieren und starten:
   ```
   Scripts/install.sh
   ```
   Das Skript beendet eine laufende Instanz, kopiert die App nach `~/Applications/TouchBridge.app` und startet sie.
4. Beim ersten Start **Input Monitoring** und **Accessibility** im Onboarding-Fenster freigeben (Systemeinstellungen → Datenschutz & Sicherheit). Ggf. App beenden und neu öffnen, wenn macOS dazu auffordert.
5. Touchscreen anschließen. Das Menüleisten-Symbol `hand.tap.fill` zeigt exklusiven Zugriff.
6. Optional: „Launch at login" im Menü aktivieren.

## Update

```
git pull
Scripts/build-app.sh
Scripts/install.sh
```

Bleibt Bundle-ID und Signatur gleich, bleiben die erteilten Rechte erhalten.

## Deinstallation

1. App im Menü beenden und „Launch at login" ausschalten.
2. `rm -rf ~/Applications/TouchBridge.app`
3. Optional Einstellungen löschen: `rm -rf ~/Library/Application\ Support/TouchBridge`
4. Einträge in Systemeinstellungen → Datenschutz & Sicherheit (Input Monitoring, Bedienungshilfen) entfernen.

## Häufige Probleme

- `codesign` meldet „detritus not allowed": `xattr -cr dist` bzw. in einem Verzeichnis außerhalb von `~/Documents` bauen (iCloud/File Provider).
- Menü zeigt „shared": Input Monitoring fehlt oder exklusiver Zugriff nicht möglich.
