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

# =============================================================================
# ── KONFIGURATION (hier anpassen) ────────────────────────────────────────────
# =============================================================================
CTID=200                        # Container ID (frei wählen, z.B. 200)
HOSTNAME="wazuh"                # Hostname des Containers
STORAGE="local-lvm"             # Storage für das Rootfs (z.B. local-lvm, local-zfs)
TEMPLATE_STORAGE="local"        # Storage wo Templates liegen
MEMORY=8192                     # RAM in MB (mind. 4096, empfohlen 8192)
CORES=4                         # CPU Kerne (mind. 2)
DISK=60                         # Disk in GB (mind. 50)
IP="192.168.0.23/24"            # IP-Adresse / CIDR
GW="192.168.0.1"                # Gateway
DNS="192.168.0.1"               # DNS-Server
VLAN=""                         # VLAN Tag (leer lassen wenn kein VLAN)
BRIDGE="vmbr0"                  # Netzwerk-Bridge
# =============================================================================

echo ""
echo -e "  ${BOLD}powered by Aeterna™${NC}"
echo -e "  ${CYAN}Erstellt mithilfe von KI (Claude by Anthropic)${NC}"
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Wazuh LXC Container Setup${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo ""
info "Container ID:  $CTID"
info "Hostname:      $HOSTNAME"
info "RAM:           ${MEMORY}MB"
info "CPU:           $CORES Cores"
info "Disk:          ${DISK}GB"
info "IP:            $IP"
echo ""

# =============================================================================
# Prüfungen
# =============================================================================

# Proxmox-Check
command -v pct &>/dev/null || error "pct nicht gefunden – läuft dieses Script auf dem Proxmox-Host?"

# Container ID frei?
if pct status "$CTID" &>/dev/null; then
    error "Container $CTID existiert bereits. Andere ID in der Konfiguration wählen."
fi

# Debian 12 Template suchen
info "Suche Debian 12 Template..."
TEMPLATE=$(pvesm list "$TEMPLATE_STORAGE" 2>/dev/null | grep -i "debian-12" | grep "vztmpl" | tail -1 | awk '{print $1}')

if [[ -z "$TEMPLATE" ]]; then
    warn "Kein Debian 12 Template gefunden – wird heruntergeladen..."
    pveam update &>/dev/null || warn "pveam update fehlgeschlagen"
    TEMPLATE_NAME=$(pveam available --section system 2>/dev/null | grep "debian-12" | tail -1 | awk '{print $2}')
    [[ -z "$TEMPLATE_NAME" ]] && error "Debian 12 Template nicht in der Paketliste gefunden"
    pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_NAME" || error "Template-Download fehlgeschlagen"
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

# VLAN-Option zusammenbauen
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

info "LXC-Konfiguration für Wazuh Indexer erweitern..."
LXC_CONF="/etc/pve/lxc/${CTID}.conf"

# Nötige Capabilities für Wazuh Indexer / OpenSearch
cat >> "$LXC_CONF" <<'EOF'

# Wazuh / OpenSearch: benötigte Kernel-Capabilities
lxc.cap.drop =
lxc.apparmor.profile = unconfined
EOF
ok "LXC-Konfiguration angepasst"

# =============================================================================
# vm.max_map_count auf dem Proxmox-Host setzen
# (OpenSearch/Wazuh Indexer braucht dies – muss auf dem HOST gesetzt sein)
# =============================================================================

info "vm.max_map_count auf dem Proxmox-Host setzen..."
CURRENT_MAP=$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)
if [[ $CURRENT_MAP -lt 262144 ]]; then
    sysctl -w vm.max_map_count=262144 &>/dev/null
    # Persistent machen
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
# Container starten
# =============================================================================

echo ""
info "Container starten..."
pct start "$CTID" || error "Container konnte nicht gestartet werden"
sleep 5

# Warten bis Container bereit ist
for i in {1..20}; do
    if pct exec "$CTID" -- echo "ready" &>/dev/null; then
        ok "Container ist bereit"
        break
    fi
    sleep 2
    [[ $i -eq 20 ]] && error "Container antwortet nicht – manuell prüfen: pct enter $CTID"
done

# =============================================================================
# Grundkonfiguration im Container
# =============================================================================

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

echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}${BOLD}FERTIG – Container $CTID ist bereit!${NC}"
echo ""
echo -e "  Container betreten:   ${CYAN}pct enter $CTID${NC}"
echo -e "  Oder per SSH:         ${CYAN}ssh root@${IP%%/*}${NC}"
echo ""
echo -e "  ${BOLD}Nächster Schritt – Wazuh installieren:${NC}"
echo -e "  ${YELLOW}1.${NC} pct enter $CTID"
echo -e "  ${YELLOW}2.${NC} ${CYAN}bash <(curl -fsSL https://raw.githubusercontent.com/Mozra-the-great/Auto-Updates-powered-by-Aeterna/main/wazuh-install.sh)${NC}"
echo ""
echo -e "  ${YELLOW}⚠  Wichtig:${NC}"
echo -e "  Das Wazuh Dashboard läuft auf Port 443."
echo -e "  Erreichbar unter: ${CYAN}https://${IP%%/*}${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
echo ""
