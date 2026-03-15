# Auto-Updates – powered by Aeterna™

> **powered by Aeterna™**  
> Dieses Repository und alle enthaltenen Scripts wurden mithilfe von KI (Claude by Anthropic) erstellt.  
> Alle Scripts vor der Ausführung prüfen – keine Haftung für Schäden.

Automatische Sicherheitsupdates, System-Monitoring und SIEM-Infrastruktur für Debian-Server (11 Bullseye / 12 Bookworm).

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

### `ssh-disable.sh` – SSH deaktivieren (Proxmox CT)
Deaktiviert SSH vollständig – Zugang danach **nur noch über die Proxmox Web UI Console**.

> ⚠️ Sicherstellen dass die Proxmox Web UI erreichbar ist, bevor dieser Script ausgeführt wird!

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mozra-the-great/Auto-Updates-powered-by-Aeterna/main/ssh-disable.sh)
```

**Was es macht:**
- Fragt zur Sicherheit nochmal nach Bestätigung
- Zeigt aktive SSH-Sessions an bevor sie getrennt werden
- Stoppt und deaktiviert SSH-Dienst und SSH-Socket
- Setzt `AllowUsers NOBODY_PLACEHOLDER` als Fallback in sshd_config
- Erstellt ein Backup der sshd_config
- Schreibt Statusdatei nach `/etc/aeterna/ssh-status`

---

### `ssh-enable.sh` – SSH reaktivieren mit Key-only (Proxmox CT)
Reaktiviert SSH mit **ausschließlich Key-Authentifizierung** – kein Passwort-Login möglich.

> ⚠️ Diesen Script immer über die **Proxmox Web UI Console** ausführen, nicht über eine bestehende SSH-Session!

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mozra-the-great/Auto-Updates-powered-by-Aeterna/main/ssh-enable.sh)
```

**Was es macht:**
- Erkennt bereits vorhandene SSH Keys und zeigt sie an
- Fragt nach dem Public Key und validiert das Format (`ssh-ed25519`, `ssh-rsa`, etc.)
- Mehrere Keys können nacheinander hinzugefügt werden
- Fragt nach dem gewünschten SSH-Port (Enter = Standard 22)
- Installiert OpenSSH Server falls nicht vorhanden
- Schreibt eine neue, saubere `sshd_config` mit Key-only Authentifizierung
- Gibt am Ende die fertige Login-Zeile aus

**Public Key auf deinem PC anzeigen:**
```bash
cat ~/.ssh/id_ed25519.pub
# oder
cat ~/.ssh/id_rsa.pub
```

**Falls noch kein Key vorhanden – neuen erstellen:**
```bash
ssh-keygen -t ed25519 -C "mein-server"
```

---

## Wazuh SIEM

Vollständige SIEM-Infrastruktur auf Basis von [Wazuh](https://wazuh.com) – bestehend aus drei Scripts die der Reihe nach ausgeführt werden.

**Kompatibel mit:** Proxmox LXC Containern, VMs, Oracle Cloud (ARM/x86), jedem Debian 11/12 Server.

---

### Schritt 1 – `wazuh-lxc-create.sh` – LXC Container auf Proxmox erstellen

> Ausführen auf dem **Proxmox-Host** als root.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mozra-the-great/Auto-Updates-powered-by-Aeterna/main/wazuh-lxc-create.sh)
```

Das Script fragt alle Parameter interaktiv ab – keine Konfiguration vorab nötig:

| Parameter | Standardwert | Beschreibung |
|---|---|---|
| Container ID | nächste freie ID | Proxmox CT-ID |
| Hostname | `wazuh` | |
| RAM | `8192` MB | mind. 4096, empf. 8192 |
| CPU | `4` Kerne | mind. 2 |
| Disk | `60` GB | mind. 50 |
| IP/CIDR | – | z.B. `10.0.0.10/24` |
| Gateway | – | |
| Storage | `local-lvm` | |
| Bridge | `vmbr0` | |
| VLAN | – | optional |

**Was es macht:**
- Lädt Debian 12 Template herunter falls nicht vorhanden
- Erstellt privilegierten Container mit nötigen LXC-Capabilities für OpenSearch
- Setzt `vm.max_map_count=262144` persistent auf dem Proxmox-Host
- Installiert Grundpakete im Container

> **Sicherheitshinweis:** Wazuh Indexer (OpenSearch/Elasticsearch) benötigt technisch einen privilegierten Container (`unprivileged 0`) und `apparmor=unconfined`. Das erhöht das Risiko bei einem Container-Breakout. Empfehlung: Proxmox-Firewall für den Container aktivieren und nur die nötigen Ports freigeben.

---

### Schritt 2 – `wazuh-install.sh` – Wazuh All-in-One im Container

> Ausführen **im Wazuh-Container** als root (`pct enter <CTID>`).

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mozra-the-great/Auto-Updates-powered-by-Aeterna/main/wazuh-install.sh)
```

**Was es macht:**
- Prüft Systemvoraussetzungen (RAM, Disk, `vm.max_map_count`)
- Lädt den offiziellen Wazuh Installer herunter und **verifiziert die SHA512-Prüfsumme** vor der Ausführung
- Installiert Wazuh Manager, Indexer und Dashboard (All-in-One)
- Sichert alle generierten Passwörter nach `/root/wazuh-passwords.txt` (Rechte: 600)
- Schließt Wazuh-Pakete von `unattended-upgrades` aus (Wazuh-Updates erfordern manuelle Migration)
- Dauer: ca. 10–20 Minuten

Das Wazuh Dashboard ist danach erreichbar unter `https://<Container-IP>` (Zertifikats-Warnung beim ersten Aufruf bestätigen).

**Wazuh Ports (in Proxmox-Firewall freigeben):**

| Port | Protokoll | Verwendung |
|---|---|---|
| `443` | TCP | Dashboard (HTTPS) |
| `1514` | TCP+UDP | Agent Kommunikation |
| `1515` | TCP | Agent Enrollment |
| `55000` | TCP | Manager API |

---

### Schritt 3 – `wazuh-agent-install.sh` – Agent auf überwachten Servern

> Ausführen auf **jedem Server der überwacht werden soll** als root.

```bash
WAZUH_MANAGER="<Wazuh-IP>" bash <(curl -fsSL https://raw.githubusercontent.com/Mozra-the-great/Auto-Updates-powered-by-Aeterna/main/wazuh-agent-install.sh)
```

Die Manager-IP kann auch weggelassen werden – das Script fragt sie dann interaktiv ab.

**Was es macht:**
- Lädt den Wazuh GPG-Key herunter und **verifiziert den Fingerabdruck** gegen den offiziell publizierten Wert
- Richtet das Wazuh-Repository ein
- Installiert und registriert den Agent automatisch beim Manager
- Schließt `wazuh-agent` von automatischen Updates aus
- Aktiviert den Agent-Dienst mit Autostart

---

## Nach der Installation

```bash
# Wazuh Logs live verfolgen
journalctl -u wazuh-manager -f

# Agent-Status auf einem Server
systemctl status wazuh-agent
tail -f /var/ossec/logs/ossec.log

# Alle registrierten Agents anzeigen
/var/ossec/bin/agent_control -l

# Wazuh manuell aktualisieren (nie automatisch!)
# https://documentation.wazuh.com/current/upgrade-guide/
```

---

## Logs & Diagnose (Auto-Updates)

```bash
# Logs live verfolgen
journalctl -u unattended-upgrades -f

# Update-Log ansehen
tail -f /var/log/unattended-upgrades/unattended-upgrades.log

# Manuell testen
unattended-upgrades --debug
```

---

## Konfiguration anpassen (Auto-Updates)

Die Setup- und Fix-Scripts haben oben einen Konfigurationsblock:

```bash
MAIL_ADDRESS="root"        # E-Mail für Fehlerberichte
MAIL_REPORT="on-change"    # always | on-change | only-on-error | never
AUTO_REBOOT="false"        # true = Neustart nach Kernel-Updates
AUTO_REBOOT_TIME="02:00"   # Uhrzeit für automatischen Neustart
REMOVE_UNUSED_DEPS="true"  # Verwaiste Pakete automatisch entfernen
```

Einfach vor dem Ausführen anpassen oder die Datei lokal bearbeiten.
