#!/usr/bin/env bash
# =============================================================================
# Wazuh All-in-One Installation
# Installiert Wazuh Manager + Indexer + Dashboard auf Debian 12
#
# Ausführen im Wazuh-Container als root:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Mozra-the-great/Auto-Updates-powered-by-Aeterna/main/wazuh-install.sh)
#
# powered by Aeterna™
# Erstellt mithilfe von KI (Claude by Anthropic)
# =============================================================================
set -uo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()   { echo -e "  ${CYAN}[INFO]${NC}  $*"; }
ok()     { echo -e "  ${GREEN}[OK]${NC}    $*"; }
warn()   { echo -e "  ${YELLOW}[WARN]${NC}  $*"; }
error()  { echo -e "  ${RED}[ERROR]${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || error "Bitte als root ausführen (sudo bash $0)"

echo ""
echo -e "  ${BOLD}powered by Aeterna™${NC}"
echo -e "  ${CYAN}Erstellt mithilfe von KI (Claude by Anthropic)${NC}"
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Wazuh All-in-One Installation${NC}"
echo -e "${BOLD}  Manager · Indexer · Dashboard${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo ""

# =============================================================================
# Systemvoraussetzungen prüfen
# =============================================================================

info "Systemvoraussetzungen prüfen..."

# RAM
MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
if [[ $MEM_TOTAL -lt 3800 ]]; then
    error "Zu wenig RAM: ${MEM_TOTAL}MB gefunden, mindestens 4096MB erforderlich."
elif [[ $MEM_TOTAL -lt 7800 ]]; then
    warn "RAM: ${MEM_TOTAL}MB – 8GB empfohlen für stabilen Betrieb"
else
    ok "RAM: ${MEM_TOTAL}MB ✓"
fi

# Disk
DISK_FREE=$(df -m / | awk 'NR==2{print $4}')
if [[ $DISK_FREE -lt 20480 ]]; then
    warn "Freier Speicher: ${DISK_FREE}MB – mindestens 20GB empfohlen"
else
    ok "Freier Speicher: ${DISK_FREE}MB ✓"
fi

# Debian-Check
if ! grep -qi "debian" /etc/os-release 2>/dev/null; then
    warn "Kein Debian erkannt – Installation trotzdem versuchen"
else
    DISTRO_VERSION=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    ok "Debian $DISTRO_VERSION erkannt ✓"
fi

# vm.max_map_count prüfen
MAP_COUNT=$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)
if [[ $MAP_COUNT -lt 262144 ]]; then
    warn "vm.max_map_count=$MAP_COUNT – muss 262144 sein (auf dem Proxmox-Host setzen!)"
    warn "Auf dem Proxmox-Host ausführen: sysctl -w vm.max_map_count=262144"
    warn "Trotzdem weiter in 10 Sekunden... (Ctrl+C zum Abbrechen)"
    sleep 10
else
    ok "vm.max_map_count=$MAP_COUNT ✓"
fi

echo ""

# =============================================================================
# Abhängigkeiten installieren
# =============================================================================

info "Abhängigkeiten installieren..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
    curl wget gnupg2 apt-transport-https ca-certificates \
    lsb-release locales procps
ok "Abhängigkeiten installiert"

# =============================================================================
# Wazuh Installer herunterladen
# =============================================================================

WORK_DIR="/root/wazuh-install"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo ""
info "Wazuh Installer herunterladen..."
curl -sO https://packages.wazuh.com/4.x/wazuh-install.sh \
    || error "Download von wazuh-install.sh fehlgeschlagen – Internetverbindung prüfen"
ok "wazuh-install.sh heruntergeladen"

# Optionale Konfig-Anpassung (Wazuh generates its own config, but we can use custom)
info "Wazuh-Konfiguration generieren..."
curl -sO https://packages.wazuh.com/4.x/config.yml \
    || warn "config.yml konnte nicht heruntergeladen werden – Standard wird verwendet"

# Prüfen ob config.yml vorhanden ist und IP anpassen
if [[ -f config.yml ]]; then
    # Aktuelle IP ermitteln
    MY_IP=$(hostname -I | awk '{print $1}')
    sed -i "s/ip: .*/ip: \"$MY_IP\"/" config.yml || true
    info "IP in config.yml gesetzt: $MY_IP"
fi

# =============================================================================
# Wazuh All-in-One Installation
# =============================================================================

echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Installation startet jetzt...${NC}"
echo -e "${BOLD}  Das dauert 10–20 Minuten. Bitte nicht unterbrechen!${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo ""

# Installer ausführen
# -a = all-in-one (Manager + Indexer + Dashboard)
bash wazuh-install.sh -a 2>&1 | tee /root/wazuh-install.log

INSTALL_EXIT=${PIPESTATUS[0]}

if [[ $INSTALL_EXIT -ne 0 ]]; then
    echo ""
    error "Installation fehlgeschlagen (Exit $INSTALL_EXIT). Log: /root/wazuh-install.log"
fi

ok "Wazuh Installation abgeschlossen"

# =============================================================================
# Passwort aus dem Installer-Output extrahieren
# =============================================================================

echo ""
info "Zugangsdaten aus Log extrahieren..."
WAZUH_PASS=$(grep -oP "(?<=The password for user admin is )\S+" /root/wazuh-install.log 2>/dev/null \
    || grep -oP "(?<=admin ).*" /root/wazuh-install/wazuh-passwords.txt 2>/dev/null \
    || echo "(nicht gefunden – siehe /root/wazuh-install/wazuh-passwords.txt)")

# Passwort-Datei sichern
if [[ -d /root/wazuh-install ]]; then
    PASS_FILE=$(find /root/wazuh-install -name "wazuh-passwords.txt" 2>/dev/null | head -1)
    if [[ -f "$PASS_FILE" ]]; then
        cp "$PASS_FILE" /root/wazuh-passwords.txt
        chmod 600 /root/wazuh-passwords.txt
        ok "Passwörter gesichert: /root/wazuh-passwords.txt"
    fi
fi

# =============================================================================
# Auto-Updates für den Wazuh-Container einrichten
# =============================================================================

echo ""
info "Automatische Sicherheitsupdates einrichten..."
# Wazuh-Pakete von Auto-Updates ausschließen (würden Wazuh brechen!)
cat > /etc/apt/apt.conf.d/51wazuh-hold <<'EOF'
// Wazuh-Pakete werden NICHT automatisch aktualisiert
// (Wazuh-Updates müssen manuell eingespielt werden)
Unattended-Upgrade::Package-Blacklist {
    "wazuh-manager";
    "wazuh-indexer";
    "wazuh-dashboard";
};
EOF
ok "Wazuh-Pakete von automatischen Updates ausgeschlossen"

# =============================================================================
# Firewall-Ports dokumentieren
# =============================================================================

echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Wazuh Ports (in Proxmox Firewall freigeben falls aktiv)${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}1514/tcp+udp${NC}  – Wazuh Agents (Syslog)"
echo -e "  ${CYAN}1515/tcp${NC}      – Wazuh Agent Enrollment"
echo -e "  ${CYAN}1516/tcp${NC}      – Wazuh Cluster"
echo -e "  ${CYAN}443/tcp${NC}       – Wazuh Dashboard (HTTPS)"
echo -e "  ${CYAN}9200/tcp${NC}      – Wazuh Indexer API (intern)"
echo -e "  ${CYAN}55000/tcp${NC}     – Wazuh Manager API"
echo ""

# =============================================================================
# Dienste-Status prüfen
# =============================================================================

info "Dienste-Status prüfen..."
for svc in wazuh-manager wazuh-indexer wazuh-dashboard; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        ok "$svc läuft ✓"
    else
        warn "$svc läuft NICHT – manuell prüfen: systemctl status $svc"
    fi
done

# =============================================================================
# Fertig
# =============================================================================

MY_IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}${BOLD}FERTIG – Wazuh ist installiert!${NC}"
echo ""
echo -e "  Dashboard:   ${CYAN}https://${MY_IP}${NC}"
echo -e "  Benutzer:    ${CYAN}admin${NC}"
echo -e "  Passwort:    ${CYAN}${WAZUH_PASS}${NC}"
echo ""
echo -e "  Alle Passwörter: ${YELLOW}/root/wazuh-passwords.txt${NC}"
echo -e "  Install-Log:     ${YELLOW}/root/wazuh-install.log${NC}"
echo ""
echo -e "  ${BOLD}Nächster Schritt – Agents installieren:${NC}"
echo -e "  Auf jedem zu überwachenden Server:"
echo -e "  ${CYAN}WAZUH_MANAGER=\"${MY_IP}\" bash <(curl -fsSL https://raw.githubusercontent.com/Mozra-the-great/Auto-Updates-powered-by-Aeterna/main/wazuh-agent-install.sh)${NC}"
echo ""
echo -e "  ${YELLOW}⚠  Browser-Hinweis:${NC} Zertifikat-Warnung beim ersten Öffnen bestätigen."
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo ""
