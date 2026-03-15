#!/usr/bin/env bash
# =============================================================================
# Wazuh LXC Container erstellen – Proxmox Host
# Erstellt einen Debian 12 Container optimiert für Wazuh All-in-One
#
# Ausführen auf dem PROXMOX HOST als root: bash wazuh-lxc-create.sh
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

[[ $EUID -eq 0 ]] || error "Bitte auf dem Proxmox-Host als root ausführen"

echo ""
echo -e "  ${BOLD}powered by Aeterna™${NC}"
echo -e "  ${CYAN}Erstellt mithilfe von KI (Claude by Anthropic)${NC}"
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Wazuh LXC Container Setup${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo ""

# Proxmox-Check
command -v pct &>/dev/null || error "pct nicht gefunden – läuft dieses Script auf dem Proxmox-Host?"

# =============================================================================
# ── INTERAKTIVE KONFIGURATION ────────────────────────────────────────────────
# =============================================================================

prompt() {
    local VAR="$1" MSG="$2" DEFAULT="$3"
    if [[ -n "$DEFAULT" ]]; then
        echo -ne "  ${BOLD}${MSG}${NC} ${CYAN}[${DEFAULT}]${NC}: "
    else
        echo -ne "  ${BOLD}${MSG}${NC}: "
    fi
    read -r INPUT </dev/tty
    echo ""
    printf -v "$VAR" '%s' "${INPUT:-$DEFAULT}"
}

echo -e "  ${BOLD}Konfiguration${NC} – Enter übernimmt den Standardwert"
echo ""

NEXT_ID=$(pvesh get /cluster/nextid 2>/dev/null || echo "200")
prompt CTID      "Container ID"                              "$NEXT_ID"
prompt HOSTNAME  "Hostname"                                  "wazuh"
prompt MEMORY    "RAM in MB (mind. 4096, empf. 8192)"        "8192"
prompt CORES     "CPU-Kerne"                                 "4"
prompt DISK      "Disk in GB"                                "60"
prompt IP        "IP-Adresse mit CIDR  (z.B. 10.0.0.10/24)" ""
prompt GW        "Gateway               (z.B. 10.0.0.1)"    ""
prompt DNS       "DNS-Server            (leer = Gateway)"    ""
prompt STORAGE   "Storage für Rootfs"                        "local-lvm"
prompt BRIDGE    "Netzwerk-Bridge"                           "vmbr0"

echo -ne "  ${BOLD}VLAN Tag (leer = kein VLAN)${NC}: "
read -r VLAN </dev/tty
echo ""

TEMPLATE_STORAGE="local"

# Pflichtfelder prüfen
[[ -z "$IP" ]] && error "IP-Adresse ist Pflicht."
[[ -z "$GW" ]] && error "Gateway ist Pflicht."
[[ -z "$DNS" ]] && DNS="$GW"

[[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]] \
    || error "IP-Format ungültig. Erwartet: x.x.x.x/cidr  (z.B. 10.0.0.10/24)"

echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Zusammenfassung${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo ""
info "Container ID:  $CTID"
info "Hostname:      $HOSTNAME"
info "RAM:           ${MEMORY}MB"
info "CPU:           $CORES Kerne"
info "Disk:          ${DISK}GB"
info "IP:            $IP"
info "Gateway:       $GW"
info "DNS:           $DNS"
info "Storage:       $STORAGE"
info "Bridge:        $BRIDGE"
[[ -n "$VLAN" ]] && info "VLAN:          $VLAN"
echo ""
echo -ne "  ${BOLD}Fortfahren? [j/N]:${NC} "
read -r CONFIRM </dev/tty
echo ""
[[ "$CONFIRM" =~ ^[jJyY]$ ]] || { echo -e "  ${CYAN}Abgebrochen.${NC}"; exit 0; }

# =============================================================================
# Container ID frei?
# =============================================================================

if pct status "$CTID" &>/dev/null; then
    error "Container $CTID existiert bereits. Andere ID wählen."
fi

# =============================================================================
# Debian 12 Template suchen / herunterladen
# =============================================================================

info "Suche Debian 12 Template..."
TEMPLATE=$(pvesm list "$TEMPLATE_STORAGE" 2>/dev/null \
    | grep -i "debian-12" | grep "vztmpl" | tail -1 | awk '{print $1}')

if [[ -z "$TEMPLATE" ]]; then
    warn "Kein Debian 12 Template gefunden – wird heruntergeladen..."
    pveam update &>/dev/null || warn "pveam update fehlgeschlagen"
    TEMPLATE_NAME=$(pveam available --section system 2>/dev/null \
        | grep "debian-12" | tail -1 | awk '{print $2}')
    [[ -z "$TEMPLATE_NAME" ]] && error "Debian 12 Template nicht in der Paketliste gefunden"
    pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_NAME" \
        || error "Template-Download fehlgeschlagen"
    TEMPLATE="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE_NAME}"
    ok "Template heruntergeladen: $TEMPLATE_NAME"
else
    ok "Template gefunden: $TEMPLATE"
fi

# =============================================================================
# Container erstellen
# =============================================================================

echo ""
info "Container $CTID erstellen..."

NET_OPTS="name=eth0,bridge=${BRIDGE},ip=${IP},gw=${GW}"
[[ -n "$VLAN" ]] && NET_OPTS="${NET_OPTS},tag=${VLAN}"

pct create "$CTID" "$TEMPLATE" \
    --hostname "$HOSTNAME" \
    --memory "$MEMORY" \
    --cores "$CORES" \
    --rootfs "${STORAGE}:${DISK}" \
    --net0 "$NET_OPTS" \
    --nameserver "$DNS" \
    --ostype debian \
    --unprivileged 0 \
    --features "nesting=1,keyctl=1" \
    --onboot 1 \
    --start 0 \
    || error "Container konnte nicht erstellt werden"

ok "Container $CTID erstellt"

# =============================================================================
# LXC-Konfiguration für Wazuh Indexer (OpenSearch)
# =============================================================================

# SICHERHEITSHINWEIS:
#   'unprivileged 0' = privilegierter Container.
#   Dies ist eine technische Notwendigkeit: Der Wazuh Indexer (OpenSearch /
#   Elasticsearch) benötigt Kernel-Calls (mlock, seccomp-Bypass, etc.), die in
#   unprivilegierten LXC-Containern durch die UID-Remapping-Schicht blockiert
#   werden und nicht konfigurierbar umgangen werden können.
#
#   'apparmor.profile = unconfined': OpenSearch lädt beim Start dynamisch
#   Shared Libraries, die von Debian-Standard-AppArmor-Profilen für Prozesse
#   geblockt werden, die nicht explizit gewhitelistet sind.
#
#   Risiko: Bei einem erfolgreichen Container-Breakout hat ein Angreifer
#   direkten Zugriff auf den Proxmox-Host-Kernel.
#
#   Empfohlene Mitigierung:
#     - Proxmox-Firewall für den Container aktivieren (nur Ports 443, 1514,
#       1515, 55000 freigeben)
#     - Wazuh-Container auf einem separaten Node/VLAN isolieren
#     - Proxmox-Host selbst nicht als Admin-Endpoint nutzen

info "LXC-Konfiguration für Wazuh Indexer anpassen..."
LXC_CONF="/etc/pve/lxc/${CTID}.conf"
cat >> "$LXC_CONF" <<'EOF'

# Wazuh / OpenSearch: benötigte Kernel-Capabilities
# Hinweis: unprivileged=0 + unconfined erhöhen das Host-Risiko bei Breakout.
# Mitigierung: Proxmox-Firewall aktivieren, Container isolieren.
lxc.cap.drop =
lxc.apparmor.profile = unconfined
EOF
ok "LXC-Konfiguration angepasst"

# =============================================================================
# vm.max_map_count auf dem Proxmox-Host setzen
# (OpenSearch braucht dies auf dem HOST – kann nicht im Container gesetzt werden)
# =============================================================================

info "vm.max_map_count auf dem Proxmox-Host setzen..."
CURRENT_MAP=$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)
if [[ $CURRENT_MAP -lt 262144 ]]; then
    sysctl -w vm.max_map_count=262144 &>/dev/null
    if ! grep -q "vm.max_map_count" /etc/sysctl.conf 2>/dev/null; then
        echo "vm.max_map_count=262144" >> /etc/sysctl.conf
    else
        sed -i 's/.*vm.max_map_count.*/vm.max_map_count=262144/' /etc/sysctl.conf
    fi
    ok "vm.max_map_count=262144 gesetzt (persistent in /etc/sysctl.conf)"
else
    ok "vm.max_map_count bereits ausreichend ($CURRENT_MAP)"
fi

# =============================================================================
# Container starten & Grundpakete installieren
# =============================================================================

echo ""
info "Container starten..."
pct start "$CTID" || error "Container konnte nicht gestartet werden"
sleep 5

for i in {1..20}; do
    if pct exec "$CTID" -- echo "ready" &>/dev/null; then
        ok "Container ist bereit"; break
    fi
    sleep 2
    [[ $i -eq 20 ]] && error "Container antwortet nicht – manuell prüfen: pct enter $CTID"
done

info "Grundpakete im Container installieren..."
pct exec "$CTID" -- bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq curl wget gnupg2 ca-certificates apt-transport-https lsb-release locales
    sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    locale-gen > /dev/null 2>&1
" || warn "Grundinstallation mit Fehlern – trotzdem weitermachen"
ok "Grundpakete installiert"

# =============================================================================
# Zusammenfassung
# =============================================================================

CT_IP="${IP%%/*}"
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}${BOLD}FERTIG – Container $CTID ist bereit!${NC}"
echo ""
echo -e "  Container betreten:   ${CYAN}pct enter $CTID${NC}"
echo -e "  Oder per SSH:         ${CYAN}ssh root@${CT_IP}${NC}"
echo ""
echo -e "  ${BOLD}Nächster Schritt – Wazuh installieren:${NC}"
echo -e "  ${YELLOW}1.${NC} pct enter $CTID"
echo -e "  ${YELLOW}2.${NC} ${CYAN}bash <(curl -fsSL https://raw.githubusercontent.com/Mozra-the-great/Auto-Updates-powered-by-Aeterna/main/wazuh-install.sh)${NC}"
echo ""
echo -e "  Dashboard nach Installation: ${CYAN}https://${CT_IP}${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo ""
