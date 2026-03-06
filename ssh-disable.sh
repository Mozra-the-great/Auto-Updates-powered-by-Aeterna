#!/usr/bin/env bash
# =============================================================================
# SSH Deaktivieren – Proxmox CT
# Deaktiviert SSH vollständig – Zugang nur noch über Proxmox Web UI Shell
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

echo -e "${BOLD}"
echo "  ███████╗███████╗██╗  ██╗"
echo "  ██╔════╝██╔════╝██║  ██║"
echo "  ███████╗███████╗███████║"
echo "  ╚════██║╚════██║██╔══██║"
echo "  ███████║███████║██║  ██║"
echo "  ╚══════╝╚══════╝╚═╝  ╚═╝"
echo -e "${NC}"
echo -e "  ${CYAN}SSH Deaktivieren${NC} – powered by Aeterna™"
echo -e "  ${CYAN}Erstellt mithilfe von KI (Claude by Anthropic)${NC}"
echo ""
echo -e "  ${RED}${BOLD}⚠ ACHTUNG:${NC} Nach diesem Script ist SSH-Zugang nicht mehr möglich!"
echo -e "  ${YELLOW}Stelle sicher dass du Zugang zur Proxmox Web UI hast!${NC}"
echo ""
echo -ne "  ${BOLD}Fortfahren? [j/N]:${NC} "
read -r CONFIRM </dev/tty
echo ""
[[ "$CONFIRM" =~ ^[jJyY]$ ]] || { echo -e "  ${CYAN}Abgebrochen.${NC}"; exit 0; }

echo ""
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Status vor dem Deaktivieren${NC}"
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo ""

# Aktuellen Status anzeigen
if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
    warn "SSH ist aktuell AKTIV"
else
    info "SSH ist bereits inaktiv"
fi

SSH_PORT=$(grep -iE "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
info "SSH Port: ${SSH_PORT:-22}"

ACTIVE_SESSIONS=$(ss -tnp 2>/dev/null | grep ":${SSH_PORT:-22}" | grep ESTABLISHED | wc -l)
if [[ $ACTIVE_SESSIONS -gt 0 ]]; then
    warn "$ACTIVE_SESSIONS aktive SSH-Verbindung(en) – werden getrennt!"
fi

echo ""
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo -e "${BOLD}  SSH deaktivieren${NC}"
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo ""

# --- Schritt 1: Backup der sshd_config ---
info "Backup von sshd_config erstellen..."
if [[ -f /etc/ssh/sshd_config ]]; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup-$(date +%Y%m%d-%H%M%S)
    ok "Backup erstellt: /etc/ssh/sshd_config.backup-$(date +%Y%m%d)"
fi

# --- Schritt 2: SSH Dienst stoppen und deaktivieren ---
info "SSH Dienst stoppen..."
for svc in ssh sshd; do
    if systemctl list-units --type=service --all 2>/dev/null | grep -q "${svc}.service"; then
        systemctl stop "$svc" 2>/dev/null && ok "Dienst $svc gestoppt" || warn "$svc stoppen fehlgeschlagen"
        systemctl disable "$svc" 2>/dev/null && ok "Dienst $svc deaktiviert" || warn "$svc deaktivieren fehlgeschlagen"
    fi
done

# --- Schritt 3: SSH Socket deaktivieren (falls vorhanden) ---
if systemctl list-units --type=socket --all 2>/dev/null | grep -q "ssh.socket"; then
    systemctl stop ssh.socket 2>/dev/null || true
    systemctl disable ssh.socket 2>/dev/null || true
    ok "SSH Socket deaktiviert"
fi

# --- Schritt 4: sshd_config absichern (Login verweigern als Fallback) ---
info "sshd_config absichern (AllowUsers auf nobody setzen)..."
if [[ -f /etc/ssh/sshd_config ]]; then
    # Entferne alte AllowUsers Zeile falls vorhanden
    sed -i '/^AllowUsers/d' /etc/ssh/sshd_config
    sed -i '/^PermitRootLogin/d' /etc/ssh/sshd_config
    sed -i '/^PasswordAuthentication/d' /etc/ssh/sshd_config
    # Füge sichere Werte hinzu
    cat >> /etc/ssh/sshd_config <<'EOF'

# === SSH DEAKTIVIERT durch ssh-disable.sh (Aeterna) ===
PermitRootLogin no
PasswordAuthentication no
AllowUsers NOBODY_PLACEHOLDER
# Kein Login möglich – reaktivieren mit ssh-enable.sh
EOF
    ok "sshd_config abgesichert"
fi

# --- Schritt 5: Statusdatei schreiben (für ssh-enable.sh) ---
mkdir -p /etc/aeterna
cat > /etc/aeterna/ssh-status <<'EOF'
STATUS=disabled
DISABLED_AT=TIMESTAMP_PLACEHOLDER
EOF
sed -i "s/TIMESTAMP_PLACEHOLDER/$(date '+%Y-%m-%d %H:%M:%S')/" /etc/aeterna/ssh-status
ok "Statusdatei geschrieben: /etc/aeterna/ssh-status"

# --- Verifikation ---
echo ""
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Verifikation${NC}"
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo ""

if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
    warn "SSH-Dienst läuft noch – manuell prüfen!"
else
    ok "SSH-Dienst ist gestoppt ✓"
fi

if systemctl is-enabled --quiet ssh 2>/dev/null || systemctl is-enabled --quiet sshd 2>/dev/null; then
    warn "SSH-Dienst ist noch aktiviert – manuell prüfen!"
else
    ok "SSH-Dienst ist deaktiviert ✓"
fi

# Port-Check
if ss -tlnp 2>/dev/null | grep -q ":${SSH_PORT:-22}"; then
    warn "Port ${SSH_PORT:-22} ist noch offen – manuell prüfen!"
else
    ok "Port ${SSH_PORT:-22} ist geschlossen ✓"
fi

echo ""
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}${BOLD}FERTIG – SSH ist deaktiviert.${NC}"
echo ""
echo -e "  Zugang nur noch über:  ${CYAN}Proxmox Web UI → CT → Console${NC}"
echo -e "  Reaktivieren mit:      ${CYAN}bash ssh-enable.sh${NC}"
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo ""
