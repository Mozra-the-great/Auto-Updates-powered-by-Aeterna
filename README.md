# Auto-Updates – powered by Aeterna™

Automatische Sicherheitsupdates für Debian-Server (11 Bullseye / 12 Bookworm).  
Installiert und konfiguriert `unattended-upgrades` so, dass **ausschließlich Sicherheitspatches** automatisch eingespielt werden – ohne manuelle Eingriffe.

---

## Voraussetzungen

- Debian 11 (Bullseye) oder 12 (Bookworm)
- Ausführung als `root`
- `curl` verfügbar (`apt-get install -y curl`)

---

## Scripts

### `setup-auto-security-updates.sh` – Frische Systeme
Für Server auf denen noch **kein** Auto-Update eingerichtet ist.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mozra-the-great/Auto-Updates-powered-by-Aeterna/main/setup-auto-security-updates.sh)
```

**Was es macht:**
- Installiert `unattended-upgrades`, `needrestart`, `apt-listchanges`
- Konfiguriert tägliche Sicherheitsupdates (nur Security-Repo)
- Behebt den Origins-Pattern Merge-Bug mit `::clear`
- Konfiguriert automatischen Dienst-Neustart nach Updates (`needrestart`)
- Setzt `Automatic-Reboot "false"` – kein ungewollter Serverneustart
- Aktiviert Syslog-Ausgabe
- Führt abschließend einen Dry-Run zur Verifikation durch

---

### `fix-auto-security-updates.sh` – Bereits eingerichtete Systeme
Für Server auf denen das **alte Script** bereits ausgeführt wurde und die bekannten Bugs noch aktiv sind.

Das alte Script war nie auf GitHub der fix ist also nur für mich (:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mozra-the-great/Auto-Updates-powered-by-Aeterna/main/fix-auto-security-updates.sh)
```

**Was es behebt:**
- Origins-Pattern Merge-Bug (51er-Datei hat 50er nicht überschrieben)
- Fehlende `::clear` Direktive
- Fehlende Einstellungen: `Automatic-Reboot`, `Mail`, `Remove-Unused-Dependencies`, `SyslogEnable`
- Installiert `needrestart` falls fehlend

Das Script führt zuerst einen **Vor-Check** durch und zeigt gefundene Probleme an, bevor es Änderungen macht.

---

## Nach der Installation

```bash
# Logs live verfolgen
journalctl -u unattended-upgrades -f

# Update-Log ansehen
tail -f /var/log/unattended-upgrades/unattended-upgrades.log

# Manuell testen
unattended-upgrades --debug
```

---

## Konfiguration anpassen

Beide Scripts haben oben einen Konfigurationsblock:

```bash
MAIL_ADDRESS="root"        # E-Mail für Fehlerberichte
MAIL_REPORT="on-change"    # always | on-change | only-on-error | never
AUTO_REBOOT="false"        # true = Neustart nach Kernel-Updates
AUTO_REBOOT_TIME="02:00"   # Uhrzeit für automatischen Neustart
REMOVE_UNUSED_DEPS="true"  # Verwaiste Pakete automatisch entfernen
```

Einfach vor dem Ausführen anpassen oder die Datei lokal bearbeiten.
