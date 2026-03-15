#!/usr/bin/env bash
# =============================================================================
# Wazuh Agent Installation
# Installiert und registriert den Wazuh Agent auf einem Debian-Server
#
# Verwendung:
#   WAZUH_MANAGER="192.168.0.23" bash <(curl -fsSL https://raw.githubusercontent.com/Mozra-the-great/Auto-Updates-powered-by-Aeterna/main/wazuh-agent-install.sh)
#
# Optionale Variablen:
#   WAZUH_MANAGER="<IP>"         Manager IP (Pflicht)
#   WAZUH_AGENT_NAME="<name>"    Agent-Name (Standard: Hostname)
#   WAZUH_AGENT_GROUP="<group>"  Agent-Gruppe (Standard: default)
#   WAZUH_MANAGER_PORT="1515"    Enrollment-Port (Standard: 1515)
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

# =============================================================================
# Konfiguration (per Umgebungsvariable oder interaktiv)
# =============================================================================

echo ""
echo -e "  ${BOLD}powered by Aeterna™${NC}"
echo -e "  ${CYAN}Erstellt mithilfe von KI (Claude by Anthropic)${NC}"
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Wazuh Agent Installation${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo ""

# Manager-IP prüfen / abfragen
if [[ -z "${WAZUH_MANAGER:-}" ]]; then
    echo -ne "  ${BOLD}Wazuh Manager IP eingeben:${NC} "
    read -r WAZUH_MANAGER </dev/tty
    echo ""
fi
[[ -z "$WAZUH_MANAGER" ]] && error "Keine Manager-IP angegeben."

# Agent-Name
AGENT_NAME="${WAZUH_AGENT_NAME:-$(hostname -s)}"

# Agent-Gruppe
AGENT_GROUP="${WAZUH_AGENT_GROUP:-default}"

# Port
MANAGER_PORT="${WAZUH_MANAGER_PORT:-1515}"

info "Manager:     $WAZUH_MANAGER"
info "Agent-Name:  $AGENT_NAME"
info "Gruppe:      $AGENT_GROUP"
echo ""

# =============================================================================
# Manager erreichbar?
# =============================================================================

info "Verbindung zum Manager prüfen..."
if ! timeout 5 bash -c ">/dev/tcp/${WAZUH_MANAGER}/${MANAGER_PORT}" 2>/dev/null; then
    warn "Port $MANAGER_PORT auf $WAZUH_MANAGER nicht erreichbar."
    warn "Entweder Manager noch nicht bereit, oder Firewall blockiert."
    warn "Trotzdem weiter – Installation kann noch klappen."
else
    ok "Manager erreichbar auf Port $MANAGER_PORT ✓"
fi

# =============================================================================
# Abhängigkeiten
# =============================================================================

info "Abhängigkeiten installieren..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq 2>/dev/null || warn "apt-get update fehlgeschlagen – weiter versuchen"
apt-get install -y -qq curl gnupg2 apt-transport-https ca-certificates lsb-release
ok "Abhängigkeiten installiert"

# =============================================================================
# Wazuh Repository einrichten
# =============================================================================

info "Wazuh Repository einrichten..."

# Vorhandene Installation stoppen falls vorhanden
if systemctl is-active --quiet wazuh-agent 2>/dev/null; then
    warn "Vorhandener Agent gefunden – wird neu konfiguriert"
    systemctl stop wazuh-agent 2>/dev/null || true
fi

# GPG Key
if [[ ! -f /usr/share/keyrings/wazuh.gpg ]]; then
    curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH \
        | gpg --dearmor > /usr/share/keyrings/wazuh.gpg \
        || error "Wazuh GPG-Key konnte nicht importiert werden"
    chmod 644 /usr/share/keyrings/wazuh.gpg
fi

# Repository
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
    > /etc/apt/sources.list.d/wazuh.list

apt-get update -qq 2>/dev/null || warn "apt-get update nach Wazuh-Repo fehlgeschlagen"
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
# ossec.conf prüfen und Manager-IP sicherstellen
# =============================================================================

OSSEC_CONF="/var/ossec/etc/ossec.conf"

if [[ -f "$OSSEC_CONF" ]]; then
    # Manager-IP in Konfiguration setzen (falls ENV-Methode nicht greift)
    if ! grep -q "$WAZUH_MANAGER" "$OSSEC_CONF"; then
        warn "Manager-IP nicht in ossec.conf gefunden – setze manuell..."
        sed -i "s|<address>.*</address>|<address>${WAZUH_MANAGER}</address>|g" "$OSSEC_CONF"
    fi
    ok "ossec.conf Manager-IP: $WAZUH_MANAGER ✓"

    # Agent-Name setzen
    if grep -q "<client>" "$OSSEC_CONF"; then
        # Prüfen ob agent-name schon gesetzt
        if ! grep -q "<agent_name>" "$OSSEC_CONF"; then
            sed -i "s|<client>|<client>\n    <agent_name>${AGENT_NAME}</agent_name>|" "$OSSEC_CONF"
        fi
    fi
fi

# =============================================================================
# Wazuh-Paket vor Auto-Updates schützen
# =============================================================================

info "Wazuh Agent vor automatischen Updates schützen..."
cat > /etc/apt/apt.conf.d/51wazuh-agent-hold <<'EOF'
// Wazuh Agent wird nicht automatisch aktualisiert
Unattended-Upgrade::Package-Blacklist {
    "wazuh-agent";
};
EOF
ok "wazuh-agent von automatischen Updates ausgeschlossen"

# =============================================================================
# Dienst starten
# =============================================================================

info "Wazuh Agent Dienst aktivieren und starten..."
systemctl daemon-reload
systemctl enable wazuh-agent 2>/dev/null && ok "wazuh-agent für Autostart aktiviert"
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

AGENT_ID=$(grep -oP '(?<=<id>)\d+(?=</id>)' /var/ossec/etc/client.keys 2>/dev/null \
    || cat /var/ossec/etc/client.keys 2>/dev/null | awk '{print $1}' | head -1 \
    || echo "")

if [[ -n "$AGENT_ID" ]]; then
    ok "Agent registriert mit ID: $AGENT_ID ✓"
else
    warn "Agent-ID nicht gefunden – Registrierung läuft evtl. noch"
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
[[ -n "$AGENT_ID" ]] && echo -e "  Agent-ID:   ${CYAN}$AGENT_ID${NC}"
echo ""
echo -e "  ${BOLD}Nützliche Befehle:${NC}"
echo -e "  ${YELLOW}systemctl status wazuh-agent${NC}          – Status"
echo -e "  ${YELLOW}systemctl restart wazuh-agent${NC}         – Neustart"
echo -e "  ${YELLOW}tail -f /var/ossec/logs/ossec.log${NC}     – Agent Log"
echo -e "  ${YELLOW}/var/ossec/bin/agent_control -l${NC}       – Alle Agents anzeigen"
echo ""
echo -e "  Dashboard: ${CYAN}https://${WAZUH_MANAGER}${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo ""
