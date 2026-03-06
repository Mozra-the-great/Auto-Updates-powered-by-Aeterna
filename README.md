# Auto-Updates – powered by Aeterna™

> **powered by Aeterna™**  
> Dieses Repository und alle enthaltenen Scripts wurden mithilfe von KI (Claude by Anthropic) erstellt.  
> Alle Scripts vor der Ausführung prüfen – keine Haftung für Schäden.

Automatische Sicherheitsupdates und System-Monitoring für Debian-Server (11 Bullseye / 12 Bookworm).

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

Das alte Script war nie auf GitHub – der Fix ist also nur für mich (:

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

### `debian-healthcheck.sh` – System-Diagnose & interaktiver Fix-Modus
Prüft das System auf Probleme und bietet an, gefundene Probleme **einzeln mit Bestätigung** zu beheben.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mozra-the-great/Auto-Updates-powered-by-Aeterna/main/debian-healthcheck.sh)
```

**Was geprüft wird:**

| Bereich | Checks |
|---|---|
| Updates & Pakete | Ausstehende Sicherheits-Updates, beschädigte Pakete, Neustart-Bedarf |
| Sicherheit | SSH-Konfiguration, offene Ports, Brute-Force-Versuche, fail2ban, Firewall |
| Ressourcen | CPU Load, RAM, Swap, alle Festplatten |
| Dienste | Fehlgeschlagene systemd-Dienste, wichtige Kern-Dienste |
| Logs | Kernel-Fehler, OOM-Killer, Festplatten I/O-Fehler |
| NTP | Zeitsynchronisation |

**Fix-Modus:**  
Nach dem Check werden alle behebbaren Probleme gesammelt und einzeln zur Bestätigung angeboten.

```
[1/4] 3 Sicherheits-Updates installieren
▶ DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
Ausführen? [j/n/a=alle/q=abbrechen]:
```

Mit `a` werden alle verbleibenden Fixes ohne weitere Nachfrage ausgeführt. Mit `n` oder Enter wird ein Fix übersprungen. Mit `q` wird der Fix-Modus abgebrochen.

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

Die Setup- und Fix-Scripts haben oben einen Konfigurationsblock:

```bash
MAIL_ADDRESS="root"        # E-Mail für Fehlerberichte
MAIL_REPORT="on-change"    # always | on-change | only-on-error | never
AUTO_REBOOT="false"        # true = Neustart nach Kernel-Updates
AUTO_REBOOT_TIME="02:00"   # Uhrzeit für automatischen Neustart
REMOVE_UNUSED_DEPS="true"  # Verwaiste Pakete automatisch entfernen
```

Einfach vor dem Ausführen anpassen oder die Datei lokal bearbeiten.
