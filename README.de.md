# Proxhawk-tui — eine Textkonsole für Proxmox VE

[English](README.md) | [Français](README.fr.md) | [Español](README.es.md) | **Deutsch** | [简体中文](README.zh-CN.md) | [Русский](README.ru.md)

Version 2.2.1 · Lizenz AGPL-3.0-or-later

`proxhawk-tui` ist eine Textversion der Weboberfläche von Proxmox VE (der GUI
auf Port 8006). Sie bildet deren Aufbau, Navigation und die meisten Bereiche
mit Unicode-Rahmen, Braille-Diagrammen, Nerd-Font-Symbolen und ANSI-Farben
nach und benötigt nichts, was nicht bereits auf einem Proxmox-VE-Knoten
installiert ist.

![proxhawk-tui-Demo: Übersicht und HA des Rechenzentrums, Knotenübersicht, Netzwerk, Systemlog, Community-Skripte und Datenträger, Übersicht und Optionen einer VM](docs/demo.gif)

*Demodaten.*

## Highlights

- **Gleicher Aufbau und gleiche Menüs wie die Weboberfläche** (geprüft
  anhand der Menüdefinitionen von Proxmox VE 9): Kopfleiste, Ressourcenbaum
  (Ansichten Server / Ordner / Pool / Speicher), Navigationsmenü pro Objekt,
  Werkzeugleiste, Inhaltsbereich und der Bereich *Aufgaben / Cluster-Log*.
- **Lesen und Schreiben**: Jede Konfigurationstabelle bietet
  *Hinzufügen / Bearbeiten / Entfernen* (`a` / `e` / `d`). Die Dialoge werden
  **aus dem API-Schema** des jeweiligen Aufrufs **erzeugt**: Sie bieten
  dieselben Parameter, Auswahlen und Standardwerte wie die Dialoge der GUI,
  einschließlich der Eigenschaftszeichenketten (`net0`, `scsi0`,
  `rootfs`...), die in Unterformularen bearbeitet werden.
- **Die gesamte GUI**: Rechenzentrum (Cluster, Optionen, Speicher aller
  Typen, Sicherungsaufträge, Replikation, Berechtigungen, Benutzer,
  API-Token, 2FA, Gruppen, Pools, Rollen, Realms, HA und Affinitätsregeln,
  SDN mit Zonen, VNets, Subnetzen, Controllern, IPAM, DNS, VNet-Firewall,
  Fabrics, Route-Maps, Präfixlisten, ACME, Firewall, Metrikserver,
  Ressourcen- und Verzeichniszuordnungen, benutzerdefinierte CPU-Modelle,
  Benachrichtigungen), Knoten (Netzwerk mit Anwenden/Zurücknehmen,
  Zertifikate und ACME-Bestellungen, DNS, Hosts, Zeit, Dienste, Updates,
  Repositorys, Datenträger mit GPT/Löschen, LVM, LVM-Thin, Verzeichnis, ZFS,
  **Ceph** mit Installationsassistent, Monitore, OSDs, CephFS, Pools), VMs
  und Container (Hardware/Ressourcen, Cloud-Init, Optionen, Snapshots,
  Sicherungen, Wiederherstellung, Firewall, Berechtigungen, HA, Klonen,
  Vorlage, Migration).
- **Konsole**: `qm terminal` für VMs mit serieller Schnittstelle, **SSH für
  Linux-VMs ohne serielle Schnittstelle** (IP über den Gast-Agenten, die
  Nachbartabelle oder einen Scan des Bridge-Netzwerks), `pct enter` für
  Container, Shell des Knotens.
- **Minimaler Fußabdruck**: reines bash + das Perl und `pvesh` von Proxmox
  VE. `whiptail` (ebenfalls enthalten) oder `dialog` für die Dialoge. Kein
  Dienst, keine Abhängigkeiten, nichts wird außerhalb von
  `~/.config/proxhawk-tui` und einem temporären Verzeichnis geschrieben.
- **Schnell**: Ein kleiner dauerhafter Perl-Helfer lädt die API nur einmal
  und antwortet in Millisekunden, statt bei jedem Lesezugriff `pvesh`
  (1–2 s) zu starten.
- **Getestet**: `tools/integration-test.sh` steuert jeden Bereich und jede
  Aktion auf einem echten Knoten und prüft jeden Schreibvorgang über die API
  (siehe [docs/TESTING.md](docs/TESTING.md)).
- **Modular**: Jeder Bereich ist eine kleine Funktion in `views/`; Themes,
  Symbolsätze und Sprachen sind einfache Dateien.
- **Tastatur und Maus**, 256 Farben, Truecolor oder 8 Farben, Nerd-Font-,
  Unicode-, reine ASCII- oder keine Symbole. Tastenbelegung und Farben sind
  konfigurierbar; zehn Themes (Dracula, Nord, Gruvbox, Catppuccin, Tokyo
  Night...).
- **34 Sprachen**: Englisch, Französisch, Spanisch, Deutsch, Chinesisch
  (vereinfacht) und Russisch vollständig; die übrigen Sprachen der GUI über
  den offiziellen Katalog von Proxmox VE auf dem Knoten (dieselben Begriffe
  wie in der GUI). Siehe [docs/I18N.md](docs/I18N.md).
- **Sammelaktionen und Warteschlange**: Gäste in den Suchrastern mit
  `Leertaste` markieren, um sie gemeinsam zu starten, zu stoppen oder zu
  sichern; Aktionen auf einem beschäftigten Gast werden eingereiht.
- **Skriptfähig**: `proxhawk-tui guests list -o table`,
  `proxhawk-tui guests start 101`, `proxhawk-tui api get /version`...
  (Ausgabe als JSON oder Tabelle, siehe [docs/CLI.md](docs/CLI.md)).
- **Plugins**: optionale Menüeinträge (Installer der community-scripts,
  Ansible-Inventar) — siehe [docs/EXTENDING.md](docs/EXTENDING.md#plugins).

## Voraussetzungen

| Komponente | Hinweise |
|-----------|-------|
| Proxmox-VE-Knoten 7, 8 oder 9 | als `root` auf dem Knoten ausführen, direkt oder mit `sudo` (siehe [Wer es ausführen kann](#wer-es-ausführen-kann)) |
| bash ≥ 4.3 | Standard |
| perl + PVE-Perl-Module | Teil von Proxmox VE |
| `whiptail` oder `dialog` | `whiptail` ist standardmäßig installiert; sonst eingebaute Abfragen |
| `less` | optional, zur Anzeige von Logs |
| Ein UTF-8-Terminal, ≥ 80×18 | 256 Farben empfohlen; eine Nerd Font für die Originalsymbole |

## Installation

### In einer Zeile (Paket der neuesten Version)

Auf einem Proxmox-VE-Knoten installiert eine Zeile als root (oder mit
`sudo`) die neueste Version (das `.deb` wird anhand seiner SHA-256-Summe
geprüft, bevor `apt` es installiert):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Mrdindon/proxhawk-tui/main/install.sh)"
proxhawk-tui
```

Mit sudo: `sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/Mrdindon/proxhawk-tui/main/install.sh)"`,
dann `sudo proxhawk-tui`.

Entfernen: `apt remove proxhawk-tui`. Sie können
[install.sh](install.sh) vor dem Ausführen lesen; die Pakete stehen auch auf
der [Release-Seite](https://github.com/Mrdindon/proxhawk-tui/releases).

### Mit git clone

Der Branch `main` enthält die veröffentlichten Versionen (Tags `vX.Y.Z`);
`develop` ist die laufende Entwicklung.

```bash
apt install git            # falls git noch nicht installiert ist
git clone https://github.com/Mrdindon/proxhawk-tui.git /opt/proxhawk-tui
cd /opt/proxhawk-tui
./proxhawk-tui             # direkt ausführen, oder:
./install.sh               # Befehl "proxhawk-tui" (Symlink in /usr/local/bin)
```

- **Aktualisieren**: `proxhawk-tui upgrade` (siehe [Aktualisierung](#aktualisierung)).
- **Eine bestimmte Version**: `git checkout vX.Y.Z` (zurück zur neuesten: `git checkout main`).
- **Entfernen**: `./install.sh --uninstall`, dann das Verzeichnis löschen.
- Jedes Verzeichnis ist möglich; `./install.sh --prefix DIR` legt den
  Befehl woanders als in `/usr/local/bin` ab.
- Beide Methoden nicht mischen: das Paket entfernen
  (`apt remove proxhawk-tui`), bevor ein Klon verwendet wird, oder
  umgekehrt.

### Aktualisierung

```bash
proxhawk-tui upgrade --check    # gibt es eine neue Version? (Exit-Code 10, falls ja)
proxhawk-tui upgrade            # aktualisieren (fragt nach Bestätigung; --yes überspringt)
```

`upgrade` erkennt, wie proxhawk-tui installiert wurde:

| Installiert mit | Was `upgrade` tut |
|---|---|
| der Installationszeile (`.deb`-Paket) | lädt das `.deb` der neuesten Version herunter, prüft seine SHA-256-Summe und installiert es mit `apt` (als root oder mit `sudo`) |
| `git clone` | `git fetch`, zeigt die neue Version und ihre Commits, dann `git pull --ff-only` des aktuellen Branches (abgelehnt bei lokalen Änderungen) |
| einem von Hand entpackten Archiv | zeigt die verfügbare Version und wie sie installiert wird |

`--version X.Y.Z` installiert eine bestimmte Version (Paket). Erneutes
Ausführen der Installationszeile aktualisiert das Paket ebenfalls.

### Wer es ausführen kann

proxhawk-tui nutzt direkt den lokalen API-Stack von Proxmox VE, wie `pvesh`
(kein HTTP, kein Ticket): Auf dem Knoten muss es als **root** laufen, direkt
oder mit `sudo`. Die **Berechtigungen von Proxmox VE** sind eine eigene
Ebene: Beim Start fragt proxhawk-tui, als welcher Proxmox-VE-Benutzer es
handeln soll (`root@pam`, `alice@pve`...), und es gelten die Berechtigungen
dieses Benutzers, wie in der GUI (siehe
[Running as another user](docs/CONFIGURATION.md#running-as-another-user)).
proxhawk-tui von einem Linux-Konto ohne root-Rechte auszuführen, würde die
API über HTTPS mit einem Token erfordern: noch nicht unterstützt.

Nützliche Optionen:

```bash
proxhawk-tui --glyphs nerd       # Font-Awesome-Symbole der GUI (erfordert eine Nerd Font
                                 # in IHREM Terminal, siehe docs/CONFIGURATION.md)
proxhawk-tui --theme dark        # Aussehen „Proxmox Dark“
proxhawk-tui --lang de           # Sprache der Oberfläche (Standard: automatisch)
proxhawk-tui --select qemu/100   # direkt bei VM 100 öffnen
proxhawk-tui --backend pvesh     # den dauerhaften API-Helfer nicht verwenden
```

## Wichtige Tasten

| Taste | Aktion |
|-----|--------|
| `↑` `↓` / `j` `k`, `PgUp` `PgDn`, `Home` `End` | im aktiven Bereich bewegen |
| `Tab` / `Shift+Tab` | nächster / vorheriger Bereich (Baum → Menü → Inhalt → Aufgaben) |
| `←` `→` | im Baum ein-/ausklappen, zwischen Bereichen wechseln |
| `Eingabe` | ausgewählte Zeile öffnen / bearbeiten |
| `/` | Ressourcen suchen |
| `v` | Baumansicht wechseln (Server, Ordner, Pool, Speicher) |
| `a` `e` `d` | Hinzufügen, Bearbeiten, Entfernen in Konfigurationstabellen |
| `s` `h` `c` `H` `m` | Starten, Menü Herunterfahren, Konsole, SSH, Mehr (Gäste) |
| `b` `h` `S` `B` | Neustart, Herunterfahren, Shell, Massenaktionen (Knoten) |
| `t` | Zeitraum der Diagramme in den Übersichten ändern |
| `l` | zwischen *Aufgaben* / *Cluster-Log* umschalten |
| `r` / `F5` | aktualisieren |
| `F1` / `?` | Hilfefenster: Tasten des aktuellen Bereichs |
| `F2` `F3` `F4` | Schaltflächen der Kopfleiste: VM erstellen, CT erstellen, Benutzermenü (Einstellungen, Symbole, Sprache...) |
| `Leertaste` `m` `f` | Gast markieren, Sammelaktionen, Filter (Suchraster) |
| `w` | URL der Browser-Konsole (noVNC / xterm.js) eines Gasts oder Knotens |
| `F6` | automatische Aktualisierung pausieren / fortsetzen |
| `q` / `F10` | beenden |

Die vollständige Liste steht in [docs/USAGE.md](docs/USAGE.md).

## Dokumentation

Die ausführliche Dokumentation ist auf Englisch.

| Dokument | Inhalt |
|----------|---------|
| [docs/USAGE.md](docs/USAGE.md) | Benutzerhandbuch: Bildschirm, Navigation, jeder Bereich und jede Aktion |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | Konfigurationsdatei, Tastenbelegung, Farben, Befehlszeile, Plugins, Themes, Symbolsätze |
| [docs/CLI.md](docs/CLI.md) | nicht interaktive Befehle (JSON / Tabelle) |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Module, Datenfluss, Protokoll des API-Helfers, Darstellung |
| [docs/EXTENDING.md](docs/EXTENDING.md) | einen Bereich, eine Aktion, ein Theme oder einen Symbolsatz hinzufügen |
| [docs/I18N.md](docs/I18N.md) | Sprachen, Übersetzungen, eine Sprache hinzufügen |
| [docs/TESTING.md](docs/TESTING.md) | Lint, Selbsttest, Bildschirmtests, Integrationstests (Lesen/Schreiben) |
| [AGENTS.md](AGENTS.md) | kurzer Leitfaden für Coding-Agenten |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | interne Notizen: Designentscheidungen, Verhalten von Proxmox VE, Release-Ablauf |
| [CHANGELOG.md](CHANGELOG.md) | Versionen |
| [docs/COMPARISON-devnullvoid-pvetui.md](docs/COMPARISON-devnullvoid-pvetui.md) | Analyse von devnullvoid/pvetui und Verbesserungsideen |

## Projektaufbau

```
proxhawk-tui     Einstiegspunkt (Argumente, Hauptschleife, Tastatur/Maus)
install.sh       Installation / Deinstallation (Paket von GitHub oder Symlink)
lib/             Module (Terminal, API, Widgets, Layout, Aktionen...)
lib/broker.pl    dauerhafter API-Helfer (Perl, PVE-Module)
views/           eine Datei pro Objekttyp (datacenter, node, qemu, lxc...)
themes/          Farbthemes
plugins/         optionale Plugins (in F4 > Plugins aktiviert)
lang/            Sprachen (en, fr, es, de, zh_CN, ru + TEMPLATE.sh)
fonts/           Schriften für die Linux-Konsole des Knotens
conf/            Beispielkonfiguration
tests/screens/   Szenarien der Bildschirmtests, aufgezeichnete API-Antworten, Referenzbildschirme
tools/           lint.sh, selftest.sh, screen-test.sh, integration-test.sh,
                 i18n-extract.sh, i18n-check.sh, make-release.sh, make-deb.sh
docs/            Dokumentation
```

## Einschränkungen

- Die grafischen Konsolen (noVNC, SPICE) können nicht in einem Terminal
  angezeigt werden: stattdessen serielle Konsole, SSH oder `pct enter` (`w`
  liefert die URL der noVNC-Konsole für den Browser).
- Läuft nur auf einem Knoten des Clusters (noch keine entfernte Verbindung
  zur API).
- proxhawk-tui läuft als `root` auf einem Knoten des Clusters (direkt oder
  mit `sudo`): Es nutzt direkt den lokalen API-Stack (kein HTTP, kein
  Ticket), genau wie `pvesh`; es gelten die Proxmox-VE-Berechtigungen des
  beim Start gewählten Benutzers.
- Uploads (ISO, Vorlagen, Snippets) verwenden eine Datei des Knotens selbst.
- Auf der Linux-Konsole des Knotens (Bildschirm/Tastatur, IPMI) kann keine
  Nerd Font verwendet werden: proxhawk-tui lädt dort seine eigene
  Konsolenschrift (Symbole und Diagramme, beim Beenden wiederhergestellt);
  Chinesisch, Japanisch, Koreanisch und von rechts nach links geschriebene
  Sprachen fallen dort auf Englisch zurück. Siehe
  [docs/CONFIGURATION.md](docs/CONFIGURATION.md#linux-console).

## Wie es entstanden ist

proxhawk-tui wurde mit [Claude Code](https://claude.com/claude-code)
geschrieben, dem KI-Programmieragenten von Anthropic, vom Autor gesteuert
und geprüft und auf einem echten Proxmox-VE-Knoten getestet (siehe
[docs/TESTING.md](docs/TESTING.md)). Die Designnotizen und die gewonnenen
Erkenntnisse stehen in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md);
[AGENTS.md](AGENTS.md) ist der Leitfaden für Coding-Agenten, die daran
arbeiten.

## Lizenz und Name

proxhawk-tui ist freie Software unter der **GNU Affero General Public
License v3.0 oder später** (siehe [LICENSE](LICENSE)), der Lizenz von
Proxmox VE selbst, dessen Perl-Module der API-Helfer lädt.

Proxmox® ist eine eingetragene Marke der Proxmox Server Solutions GmbH.
proxhawk-tui ist ein unabhängiges Projekt, weder mit der Proxmox Server
Solutions GmbH verbunden noch von ihr unterstützt. Es hieß *pvetui*
(1.0 – 1.1), dann *pvetty* (1.2 – 1.3); die Einstellungen dieser Versionen
werden automatisch übernommen.
