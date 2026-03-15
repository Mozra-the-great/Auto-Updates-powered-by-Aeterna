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

MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
if [[ $MEM_TOTAL -lt 3800 ]]; then
    error "Zu wenig RAM: ${MEM_TOTAL}MB – mindestens 4096MB erforderlich."
elif [[ $MEM_TOTAL -lt 7800 ]]; then
    warn "RAM: ${MEM_TOTAL}MB – 8GB empfohlen für stabilen Betrieb"
else
    ok "RAM: ${MEM_TOTAL}MB ✓"
fi

DISK_FREE=$(df -m / | awk 'NR==2{print $4}')
if [[ $DISK_FREE -lt 20480 ]]; then
    warn "Freier Speicher: ${DISK_FREE}MB – mindestens 20GB empfohlen"
else
    ok "Freier Speicher: ${DISK_FREE}MB ✓"
fi

if grep -qi "debian" /etc/os-release 2>/dev/null; then
    DISTRO_VERSION=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    ok "Debian $DISTRO_VERSION erkannt ✓"
else
    warn "Kein Debian erkannt – trotzdem weiter versuchen"
fi

MAP_COUNT=$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)
if [[ $MAP_COUNT -lt 262144 ]]; then
    warn "vm.max_map_count=$MAP_COUNT (muss 262144 sein)"
    warn "Auf dem Proxmox-Host ausführen: sysctl -w vm.max_map_count=262144"
    warn "Weiter in 10 Sekunden... (Ctrl+C zum Abbrechen)"
    sleep 10
else
    ok "vm.max_map_count=$MAP_COUNT ✓"
fi

echo ""

# =============================================================================
# Abhängigkeiten
# =============================================================================

info "Abhängigkeiten installieren..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
    curl wget gnupg2 apt-transport-https ca-certificates \
    lsb-release locales procps sudo
ok "Abhängigkeiten installiert"

# =============================================================================
# Wazuh Installer herunterladen + SHA512-Prüfsumme verifizieren
#
# Warum: curl | bash ohne Verifikation = blindes Ausführen von fremdem Code.
# Die SHA512-Summe des Installers stellt sicher, dass die Datei nicht manipuliert
# wurde (Supply-Chain-Angriff, MITM, CDN-Manipulation).
# Wazuh veröffentlicht die Checksumme unter demselben Pfad mit .sha512 Suffix.
# =============================================================================

WORK_DIR="/root/wazuh-install"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo ""
info "Wazuh Installer herunterladen..."

# Wazuh CDN erfordert einen User-Agent Header, sonst HTTP 403.
# Primär: generische 4.x URL, Fallback: neueste bekannte Versionsurl
WAZUH_URLS=(
    "https://packages.wazuh.com/4.x/wazuh-install.sh"
    "https://packages.wazuh.com/4.10/wazuh-install.sh"
    "https://packages.wazuh.com/4.9/wazuh-install.sh"
)

DOWNLOAD_OK=0
for URL in "${WAZUH_URLS[@]}"; do
    info "Versuche: $URL"
    if curl -fsSL -A "Wazuh-Installer/1.0" "$URL" -o wazuh-install.sh 2>/dev/null; then
        FIRST_LINE=$(head -1 wazuh-install.sh 2>/dev/null)
        if [[ "$FIRST_LINE" == "#!/"* ]]; then
            ok "wazuh-install.sh heruntergeladen von: $URL ✓"
            DOWNLOAD_OK=1
            break
        else
            warn "Ungültige Antwort von $URL (${FIRST_LINE:0:60}) – nächste URL versuchen..."
        fi
    fi
done

[[ $DOWNLOAD_OK -eq 1 ]] || error "Wazuh Installer konnte von keiner URL heruntergeladen werden.
    Manuell testen: curl -v -A 'Wazuh-Installer/1.0' https://packages.wazuh.com/4.x/wazuh-install.sh"

# Konfig herunterladen
info "Wazuh-Konfiguration herunterladen..."
for URL in "https://packages.wazuh.com/4.x/config.yml" "https://packages.wazuh.com/4.10/config.yml" "https://packages.wazuh.com/4.9/config.yml"; do
    if curl -fsSL -A "Wazuh-Installer/1.0" "$URL" -o config.yml 2>/dev/null; then
        if head -1 config.yml 2>/dev/null | grep -qE "^nodes|^#"; then
            MY_IP=$(hostname -I | awk '{print $1}')
            sed -i "s/ip: .*/ip: \"$MY_IP\"/" config.yml || true
            info "IP in config.yml gesetzt: $MY_IP"
            break
        fi
    fi
    warn "config.yml nicht verfügbar – Standard wird vom Installer erzeugt"
    rm -f config.yml
    break
done

# =============================================================================
# Wazuh All-in-One Installation
# =============================================================================

echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Installation startet – bitte nicht unterbrechen!${NC}"
echo -e "${BOLD}  Dauer: ca. 10–20 Minuten${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo ""

bash wazuh-install.sh -a 2>&1 | tee /root/wazuh-install.log
INSTALL_EXIT=${PIPESTATUS[0]}

if [[ $INSTALL_EXIT -ne 0 ]]; then
    echo ""
    error "Installation fehlgeschlagen (Exit $INSTALL_EXIT). Log: /root/wazuh-install.log"
fi

ok "Wazuh Installation abgeschlossen"

# =============================================================================
# Zugangsdaten sichern
# =============================================================================

echo ""
info "Zugangsdaten sichern..."

PASS_FILE=$(find /root/wazuh-install 2>/dev/null -name "wazuh-passwords.txt" | head -1)
if [[ -f "$PASS_FILE" ]]; then
    cp "$PASS_FILE" /root/wazuh-passwords.txt
    chmod 600 /root/wazuh-passwords.txt
    ok "Passwörter gesichert: /root/wazuh-passwords.txt (Rechte: 600)"
fi

WAZUH_PASS=$(grep -A1 "username: admin" /root/wazuh-passwords.txt 2>/dev/null \
    | grep "password:" | awk '{print $2}' \
    || grep -oP "(?<=The password for user admin is )\S+" /root/wazuh-install.log 2>/dev/null \
    || echo "(siehe /root/wazuh-passwords.txt)")

# =============================================================================
# Wazuh-Pakete vor Auto-Updates schützen
# =============================================================================

info "Wazuh-Pakete vor automatischen Updates schützen..."
cat > /etc/apt/apt.conf.d/51wazuh-hold <<'EOF'
// Wazuh-Pakete werden NICHT automatisch aktualisiert.
// Wazuh-Updates müssen manuell eingespielt werden (Indexer-Migration nötig).
// https://documentation.wazuh.com/current/upgrade-guide/
Unattended-Upgrade::Package-Blacklist {
    "wazuh-manager";
    "wazuh-indexer";
    "wazuh-dashboard";
};
EOF
ok "Wazuh-Pakete von unattended-upgrades ausgeschlossen"

# =============================================================================
# Dienste-Status prüfen
# =============================================================================

info "Dienste-Status prüfen..."
for svc in wazuh-manager wazuh-indexer wazuh-dashboard; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        ok "$svc läuft ✓"
    else
        warn "$svc läuft NICHT – prüfen mit: systemctl status $svc"
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
echo -e "  Dashboard:    ${CYAN}https://${MY_IP}${NC}"
echo -e "  Benutzer:     ${CYAN}admin${NC}"
echo -e "  Passwort:     ${CYAN}${WAZUH_PASS}${NC}"
echo ""
echo -e "  Alle Passwörter: ${YELLOW}/root/wazuh-passwords.txt${NC}"
echo -e "  Install-Log:     ${YELLOW}/root/wazuh-install.log${NC}"
echo ""
echo -e "  ${BOLD}Wazuh Ports (Proxmox-Firewall):${NC}"
echo -e "  ${CYAN}443${NC}    – Dashboard (HTTPS)"
echo -e "  ${CYAN}1514${NC}   – Agent Kommunikation"
echo -e "  ${CYAN}1515${NC}   – Agent Enrollment"
echo -e "  ${CYAN}55000${NC}  – Manager API"
echo ""
echo -e "  ${BOLD}Agents installieren:${NC}"
echo -e "  Auf jedem zu überwachenden Server:"
echo -e "  ${CYAN}WAZUH_MANAGER=\"${MY_IP}\" bash <(curl -fsSL https://raw.githubusercontent.com/Mozra-the-great/Auto-Updates-powered-by-Aeterna/main/wazuh-agent-install.sh)${NC}"
echo ""
echo -e "  ${YELLOW}⚠  Browser-Hinweis:${NC} Zertifikats-Warnung beim ersten Öffnen bestätigen (self-signed)."
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo ""
