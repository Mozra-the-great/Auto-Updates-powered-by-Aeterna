#!/usr/bin/env bash
# =============================================================================
# Debian – Automatische Sicherheitsupdates einrichten
# Getestet auf: Debian 11 (Bullseye), 12 (Bookworm)
# Ausführen als root: bash setup-auto-security-updates.sh
# =============================================================================
set -euo pipefail

# --- Farben für Ausgabe ---
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# --- Root-Check ---
[[ $EUID -eq 0 ]] || error "Bitte als root ausführen (sudo bash $0)"

# --- Konfiguration (hier anpassen) ---
MAIL_ADDRESS="root"             # E-Mail für Fehlerberichte (z.B. "admin@example.com")
MAIL_REPORT="on-change"        # "always" | "on-change" | "only-on-error" | "never"
AUTO_REBOOT="false"            # "true" = Automatisch neu starten nach Kernel-Updates
AUTO_REBOOT_TIME="02:00"       # Uhrzeit für Neustart (nur relevant wenn AUTO_REBOOT=true)
REMOVE_UNUSED_DEPS="true"      # Verwaiste Abhängigkeiten automatisch entfernen
AUTOCLEAN_INTERVAL="7"         # Cache alle X Tage bereinigen

# =============================================================================

export DEBIAN_FRONTEND=noninteractive

info "Paketlisten aktualisieren..."
apt-get update -qq

info "Pakete installieren..."
apt-get install -y -qq \
    unattended-upgrades \
    apt-listchanges \
    needrestart \
    locales

# -----------------------------------------------------------------------------
info "Locale konfigurieren..."
sed -i "s/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" /etc/locale.gen || true
locale-gen >/dev/null 2>&1
update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# -----------------------------------------------------------------------------
info "APT Periodic-Zeitplan schreiben..."
cat >/etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "${AUTOCLEAN_INTERVAL}";
EOF

# -----------------------------------------------------------------------------
info "Security-only Konfiguration schreiben..."
cat >/etc/apt/apt.conf.d/51unattended-security-only <<EOF
// ============================================================
// NUR Sicherheitsupdates – alle anderen Origins deaktivieren
// ============================================================

// Vorherige Origins-Liste leeren (verhindert Merge-Probleme)
Unattended-Upgrade::Origins-Pattern::clear "";

Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=\${distro_codename}-security,label=Debian-Security";
};

// Pakete die NIE automatisch aktualisiert werden sollen (Regex)
// Unattended-Upgrade::Package-Blacklist {
//     "linux-image-.*";
//     "libc6";
// };

// Verwaiste Abhängigkeiten aufräumen
Unattended-Upgrade::Remove-Unused-Dependencies "${REMOVE_UNUSED_DEPS}";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";

// Neustart-Verhalten
Unattended-Upgrade::Automatic-Reboot "${AUTO_REBOOT}";
Unattended-Upgrade::Automatic-Reboot-Time "${AUTO_REBOOT_TIME}";

// E-Mail-Berichte
Unattended-Upgrade::Mail "${MAIL_ADDRESS}";
Unattended-Upgrade::MailReport "${MAIL_REPORT}";

// Logs schreiben
Unattended-Upgrade::SyslogEnable "true";
Unattended-Upgrade::SyslogFacility "daemon";
EOF

# -----------------------------------------------------------------------------
info "Bugfix: Kaputte Zeile in 50unattended-upgrades auskommentieren..."
CONF50="/etc/apt/apt.conf.d/50unattended-upgrades"
if [[ -f "$CONF50" ]]; then
    sed -i 's|^\([[:space:]]*\)"\(origin=Debian,codename=\)-security,label=Debian-Security";|\1// disabled (broken): "\2-security,label=Debian-Security";|g' \
        "$CONF50" || warn "Konnte $CONF50 nicht patchen – ggf. manuell prüfen"
fi

# -----------------------------------------------------------------------------
info "needrestart konfigurieren (automatischer Dienst-Neustart nach Updates)..."
NEEDRESTART_CONF="/etc/needrestart/needrestart.conf"
if [[ -f "$NEEDRESTART_CONF" ]]; then
    # Dienste automatisch neu starten, aber NICHT den Kernel
    sed -i "s|^#\?\$nrconf{restart}.*|\$nrconf{restart} = 'a';|" "$NEEDRESTART_CONF" || true
fi

# -----------------------------------------------------------------------------
info "apt-listchanges konfigurieren..."
cat >/etc/apt/listchanges.conf <<EOF
[apt]
frontend=mail
email_address=${MAIL_ADDRESS}
confirm=0
save_seen=/var/lib/apt/listchanges.db
which=news
EOF

# -----------------------------------------------------------------------------
info "Dienst aktivieren..."
if systemctl enable --now unattended-upgrades >/dev/null 2>&1; then
    info "unattended-upgrades Dienst aktiv"
else
    warn "systemctl enable fehlgeschlagen – auf systemd-losen Systemen normal"
fi

# =============================================================================
echo ""
echo "============================================================"
info "Konfiguration überprüfen..."
echo "============================================================"

echo ""
echo "--- Aktive Origins-Pattern ---"
grep -rn "codename=.*-security" \
    /etc/apt/apt.conf.d/50unattended-upgrades \
    /etc/apt/apt.conf.d/51unattended-security-only \
    2>/dev/null || warn "Keine Treffer gefunden"

echo ""
echo "--- Dry-Run ---"
if unattended-upgrades --dry-run --debug 2>&1 | \
    grep -E "Allowed origins|origin=Debian|All upgrades installed|No packages found|Marking not allowed|fetch|ERROR" | \
    tail -n 50; then
    :
else
    warn "Dry-run lieferte keine gefilterten Ausgaben – Log manuell prüfen"
fi

echo ""
echo "============================================================"
echo -e "${GREEN}FERTIG.${NC}"
echo ""
echo "Logs:     journalctl -u unattended-upgrades -f"
echo "          tail -f /var/log/unattended-upgrades/unattended-upgrades.log"
echo "Manuell:  unattended-upgrades --debug"
echo "============================================================"
