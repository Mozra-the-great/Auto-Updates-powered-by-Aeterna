#!/usr/bin/env bash
# =============================================================================
# Wazuh Agent Installation
# Installiert und registriert den Wazuh Agent auf einem Debian-Server
#
# Verwendung:
#   WAZUH_MANAGER="<IP>" bash <(curl -fsSL https://raw.githubusercontent.com/Mozra-the-great/Auto-Updates-powered-by-Aeterna/main/wazuh-agent-install.sh)
#
# Optionale Variablen:
#   WAZUH_MANAGER="<IP>"          Manager IP (Pflicht)
#   WAZUH_AGENT_NAME="<name>"     Agent-Name (Standard: Hostname)
#   WAZUH_AGENT_GROUP="<group>"   Agent-Gruppe (Standard: default)
#   WAZUH_MANAGER_PORT="1515"     Enrollment-Port (Standard: 1515)
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
echo -e "${BOLD}  Wazuh Agent Installation${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo ""

# =============================================================================
# Manager-IP prüfen / abfragen
# =============================================================================

if [[ -z "${WAZUH_MANAGER:-}" ]]; then
    echo -ne "  ${BOLD}Wazuh Manager IP eingeben:${NC} "
    read -r WAZUH_MANAGER </dev/tty
    echo ""
fi
[[ -z "$WAZUH_MANAGER" ]] && error "Keine Manager-IP angegeben."

AGENT_NAME="${WAZUH_AGENT_NAME:-$(hostname -s)}"
AGENT_GROUP="${WAZUH_AGENT_GROUP:-default}"
MANAGER_PORT="${WAZUH_MANAGER_PORT:-1515}"

info "Manager:     $WAZUH_MANAGER"
info "Agent-Name:  $AGENT_NAME"
info "Gruppe:      $AGENT_GROUP"
echo ""

# =============================================================================
# Manager erreichbar?
# =============================================================================

info "Verbindung zum Manager prüfen (Port $MANAGER_PORT)..."
if ! timeout 5 bash -c ">/dev/tcp/${WAZUH_MANAGER}/${MANAGER_PORT}" 2>/dev/null; then
    warn "Port $MANAGER_PORT auf $WAZUH_MANAGER nicht erreichbar."
    warn "Mögliche Ursachen: Manager noch nicht fertig, Firewall, falshe IP."
    warn "Trotzdem weiter – Agent-Dienst verbindet sich nach dem Start."
else
    ok "Manager erreichbar auf Port $MANAGER_PORT ✓"
fi

# =============================================================================
# OS-Erkennung
# =============================================================================

OS_ID=$(grep "^ID=" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
OS_CODENAME=$(grep "^VERSION_CODENAME=" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')

case "$OS_ID" in
    debian|ubuntu|linuxmint|pop)
        ok "OS erkannt: $OS_ID ($OS_CODENAME) – apt wird verwendet ✓"
        ;;
    *)
        warn "OS '$OS_ID' nicht getestet – versuche trotzdem apt-basierte Installation"
        ;;
esac

# =============================================================================
# Abhängigkeiten
# =============================================================================

info "Abhängigkeiten installieren..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq 2>/dev/null || warn "apt-get update fehlgeschlagen"
apt-get install -y -qq curl gnupg2 apt-transport-https ca-certificates lsb-release
ok "Abhängigkeiten installiert"

# =============================================================================
# Wazuh GPG-Key importieren + Fingerabdruck verifizieren
#
# Warum: Der GPG-Key authentifiziert alle Pakete aus dem Wazuh-Repository.
# Ein manipulierter Key könnte dazu führen, dass ein Angreifer beliebigen Code
# als "Wazuh-Paket" verkleidet installiert.
#
# Der offizielle Wazuh GPG-Fingerabdruck laut https://documentation.wazuh.com/
# (Stand: 2025) – bei Releases prüfen ob sich dieser geändert hat.
# =============================================================================

# Bekannter Wazuh GPG-Fingerabdruck (offiziell publiziert auf wazuh.com/resources)
EXPECTED_FINGERPRINT="0DCFCA5547B19D2A6099506096B3EE5F29111145"

info "Wazuh GPG-Key herunterladen..."

if [[ ! -f /usr/share/keyrings/wazuh.gpg ]]; then
    TMP_KEY=$(mktemp)
    curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH > "$TMP_KEY" \
        || error "Wazuh GPG-Key konnte nicht heruntergeladen werden"

    # Fingerabdruck extrahieren und prüfen
    info "GPG-Fingerabdruck verifizieren..."
    ACTUAL_FINGERPRINT=$(gpg --with-colons --with-fingerprint --import-options show-only \
        --import < "$TMP_KEY" 2>/dev/null \
        | grep "^fpr" | head -1 | cut -d: -f10 | tr -d ' ')

    if [[ -z "$ACTUAL_FINGERPRINT" ]]; then
        warn "Fingerabdruck konnte nicht extrahiert werden – gpg Ausgabe prüfen"
    elif [[ "$ACTUAL_FINGERPRINT" == "$EXPECTED_FINGERPRINT" ]]; then
        ok "GPG-Fingerabdruck verifiziert ✓  ($ACTUAL_FINGERPRINT)"
    else
        rm -f "$TMP_KEY"
        error "GPG-Fingerabdruck stimmt NICHT ÜBEREIN!
        Erwartet: $EXPECTED_FINGERPRINT
        Erhalten: $ACTUAL_FINGERPRINT
        Key wird NICHT importiert. Verbindung und Quelle prüfen."
    fi

    gpg --dearmor < "$TMP_KEY" > /usr/share/keyrings/wazuh.gpg \
        || error "GPG-Key konnte nicht konvertiert werden"
    chmod 644 /usr/share/keyrings/wazuh.gpg
    rm -f "$TMP_KEY"
    ok "GPG-Key importiert"
else
    ok "GPG-Key bereits vorhanden"
fi

# =============================================================================
# Wazuh Repository einrichten
# =============================================================================

info "Wazuh Repository einrichten..."

if systemctl is-active --quiet wazuh-agent 2>/dev/null; then
    warn "Vorhandener Agent gefunden – wird neu konfiguriert"
    systemctl stop wazuh-agent 2>/dev/null || true
fi

# Repo für Debian und Ubuntu gleich – Wazuh nutzt "stable" für beide
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
    > /etc/apt/sources.list.d/wazuh.list

apt-get update -qq 2>/dev/null || warn "apt-get update nach Repo-Einrichtung fehlgeschlagen"
ok "Wazuh Repository eingerichtet"

# =============================================================================
# Agent installieren
# =============================================================================

info "Wazuh Agent installieren..."
WAZUH_MANAGER="$WAZUH_MANAGER" \
WAZUH_MANAGER_PORT="$MANAGER_PORT" \
WAZUH_AGENT_NAME="$AGENT_NAME" \
WAZUH_AGENT_GROUP="$AGENT_GROUP" \
    apt-get install -y wazuh-agent \
    || error "Wazuh Agent Installation fehlgeschlagen"

ok "Wazuh Agent installiert"

# =============================================================================
# ossec.conf – Manager-IP sicherstellen
# =============================================================================

OSSEC_CONF="/var/ossec/etc/ossec.conf"
if [[ -f "$OSSEC_CONF" ]]; then
    # Manager-IP sicherstellen
    if ! grep -q "$WAZUH_MANAGER" "$OSSEC_CONF"; then
        warn "Manager-IP nicht in ossec.conf – setze manuell..."
        sed -i "s|<address>.*</address>|<address>${WAZUH_MANAGER}</address>|g" "$OSSEC_CONF"
    fi
    ok "ossec.conf Manager-IP: $WAZUH_MANAGER ✓"

    # Kommunikations-Port auf 1514 setzen (nicht 1515 = Enrollment-Port)
    # Der apt-Installer setzt manchmal 1515 – das verhindert die Verbindung nach Enrollment.
    sed -i 's|<port>1515</port>|<port>1514</port>|g' "$OSSEC_CONF"
    ok "ossec.conf Kommunikations-Port: 1514 ✓"

    # Enrollment-Block sauber schreiben – verhindert doppelte <enabled>-Einträge
    # wenn das Script mehrfach auf demselben Host läuft
    python3 -c "
import re
with open('$OSSEC_CONF', 'r') as f:
    c = f.read()
# Enrollment-Block komplett neu schreiben mit sauberem <enabled>yes</enabled>
c = re.sub(
    r'<enrollment>.*?</enrollment>',
    '<enrollment>\n      <enabled>yes</enabled>\n      <agent_name>${AGENT_NAME}</agent_name>\n      <groups>${AGENT_GROUP}</groups>\n    </enrollment>',
    c, flags=re.DOTALL)
with open('$OSSEC_CONF', 'w') as f:
    f.write(c)
" && ok "ossec.conf Enrollment-Block bereinigt" || warn "Enrollment-Bereinigung fehlgeschlagen – ossec.conf manuell prüfen" 
fi

# =============================================================================
# Wazuh-Paket vor Auto-Updates schützen
# =============================================================================

info "Wazuh Agent vor automatischen Updates schützen..."
cat > /etc/apt/apt.conf.d/51wazuh-agent-hold <<'EOF'
// Wazuh Agent wird nicht automatisch aktualisiert.
// Manuell aktualisieren: apt-get install --only-upgrade wazuh-agent
Unattended-Upgrade::Package-Blacklist {
    "wazuh-agent";
};
EOF
ok "wazuh-agent von unattended-upgrades ausgeschlossen"

# =============================================================================
# Dienst starten
# =============================================================================

info "Wazuh Agent aktivieren und starten..."
systemctl daemon-reload
systemctl enable wazuh-agent 2>/dev/null && ok "Autostart aktiviert"
systemctl start wazuh-agent 2>/dev/null

sleep 3

if systemctl is-active --quiet wazuh-agent 2>/dev/null; then
    ok "wazuh-agent läuft ✓"
else
    warn "wazuh-agent läuft nicht – Status prüfen:"
    systemctl status wazuh-agent --no-pager 2>/dev/null | tail -10 || true
fi

# =============================================================================
# Registrierungsstatus prüfen
# =============================================================================

sleep 5
info "Registrierungsstatus prüfen..."

AGENT_ID=$(awk 'NR==1{print $1}' /var/ossec/etc/client.keys 2>/dev/null || echo "")
if [[ -n "$AGENT_ID" && "$AGENT_ID" != "0" ]]; then
    ok "Agent registriert mit ID: $AGENT_ID ✓"
else
    warn "Agent-ID noch nicht vergeben – Registrierung läuft evtl. noch"
    warn "Prüfen mit: /var/ossec/bin/agent_control -l"
fi

# =============================================================================
# Zusammenfassung
# =============================================================================

echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}${BOLD}FERTIG – Wazuh Agent installiert!${NC}"
echo ""
echo -e "  Manager:    ${CYAN}$WAZUH_MANAGER${NC}"
echo -e "  Agent:      ${CYAN}$AGENT_NAME${NC}"
echo -e "  Gruppe:     ${CYAN}$AGENT_GROUP${NC}"
[[ -n "$AGENT_ID" && "$AGENT_ID" != "0" ]] && echo -e "  Agent-ID:   ${CYAN}$AGENT_ID${NC}"
echo ""
echo -e "  ${BOLD}Nützliche Befehle:${NC}"
echo -e "  ${YELLOW}systemctl status wazuh-agent${NC}           – Status"
echo -e "  ${YELLOW}systemctl restart wazuh-agent${NC}          – Neustart"
echo -e "  ${YELLOW}tail -f /var/ossec/logs/ossec.log${NC}      – Agent Log"
echo -e "  ${YELLOW}/var/ossec/bin/agent_control -l${NC}        – Alle registrierten Agents"
echo ""
echo -e "  Dashboard: ${CYAN}https://${WAZUH_MANAGER}${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo ""
