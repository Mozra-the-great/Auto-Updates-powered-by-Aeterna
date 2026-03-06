#!/usr/bin/env bash
# =============================================================================
# SSH Aktivieren – Proxmox CT
# Aktiviert SSH mit Key-only Authentifizierung (kein Passwort-Login)
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
echo -e "  ${CYAN}SSH Aktivieren (Key-only)${NC} – powered by Aeterna™"
echo -e "  ${CYAN}Erstellt mithilfe von KI (Claude by Anthropic)${NC}"
echo ""

# =============================================================================
# Schritt 1: SSH Public Key abfragen
# =============================================================================

echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo -e "${BOLD}  SSH Public Key einrichten${NC}"
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${YELLOW}Deinen SSH Public Key eingeben (ssh-ed25519 ... oder ssh-rsa ...).${NC}"
echo -e "  ${YELLOW}Den Key bekommst du auf deinem PC mit:${NC}"
echo -e "  ${CYAN}  cat ~/.ssh/id_ed25519.pub${NC}  oder  ${CYAN}cat ~/.ssh/id_rsa.pub${NC}"
echo ""

# Prüfen ob bereits Keys vorhanden
EXISTING_KEYS=0
if [[ -f /root/.ssh/authorized_keys ]]; then
    EXISTING_KEYS=$(grep -c "ssh-" /root/.ssh/authorized_keys 2>/dev/null || echo 0)
fi

if [[ $EXISTING_KEYS -gt 0 ]]; then
    echo -e "  ${GREEN}$EXISTING_KEYS vorhandene(r) Key(s) in authorized_keys gefunden:${NC}"
    grep "ssh-" /root/.ssh/authorized_keys 2>/dev/null | while read -r line; do
        KEY_TYPE=$(echo "$line" | awk '{print $1}')
        KEY_COMMENT=$(echo "$line" | awk '{print $3}')
        echo -e "    ${CYAN}→ $KEY_TYPE ... $KEY_COMMENT${NC}"
    done
    echo ""
    echo -ne "  ${BOLD}Einen weiteren Key hinzufügen? [j/N]:${NC} "
    read -r ADD_MORE </dev/tty
    echo ""
    ADD_KEY=false
    [[ "$ADD_MORE" =~ ^[jJyY]$ ]] && ADD_KEY=true
else
    ADD_KEY=true
fi

if [[ "$ADD_KEY" == "true" ]]; then
    while true; do
        echo -ne "  ${BOLD}Public Key einfügen (Enter zum Bestätigen):${NC} "
        read -r PUBLIC_KEY </dev/tty
        echo ""

        # Validierung
        if [[ -z "$PUBLIC_KEY" ]]; then
            warn "Kein Key eingegeben."
            if [[ $EXISTING_KEYS -gt 0 ]]; then
                info "Vorhandene Keys werden verwendet."
                break
            fi
            echo -ne "  Nochmal versuchen? [j/N]: "
            read -r RETRY </dev/tty
            [[ "$RETRY" =~ ^[jJyY]$ ]] || error "Kein SSH Key – Abbruch. SSH bleibt deaktiviert."
            continue
        fi

        if [[ ! "$PUBLIC_KEY" =~ ^(ssh-ed25519|ssh-rsa|ssh-ecdsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|sk-ssh-ed25519) ]]; then
            warn "Ungültiges Key-Format. Erwartet: ssh-ed25519, ssh-rsa, ecdsa-sha2-*"
            echo -ne "  Nochmal versuchen? [j/N]: "
            read -r RETRY </dev/tty
            [[ "$RETRY" =~ ^[jJyY]$ ]] || error "Kein gültiger Key – Abbruch."
            continue
        fi

        # Key speichern
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        echo "$PUBLIC_KEY" >> /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
        ok "Key gespeichert in /root/.ssh/authorized_keys"

        echo ""
        echo -ne "  ${BOLD}Noch einen weiteren Key hinzufügen? [j/N]:${NC} "
        read -r ANOTHER </dev/tty
        echo ""
        [[ "$ANOTHER" =~ ^[jJyY]$ ]] || break
    done
fi

# Sicherstellen dass mindestens ein Key vorhanden
TOTAL_KEYS=$(grep -c "ssh-" /root/.ssh/authorized_keys 2>/dev/null || echo 0)
[[ $TOTAL_KEYS -gt 0 ]] || error "Keine SSH Keys vorhanden – SSH wird nicht aktiviert!"

# =============================================================================
# Schritt 2: Optionalen SSH-Port abfragen
# =============================================================================

echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo -e "${BOLD}  SSH Port konfigurieren${NC}"
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo ""
echo -ne "  ${BOLD}SSH Port (Enter = Standard 22):${NC} "
read -r SSH_PORT_INPUT </dev/tty
echo ""

if [[ -z "$SSH_PORT_INPUT" ]]; then
    SSH_PORT=22
    info "Standard-Port 22 wird verwendet"
elif [[ "$SSH_PORT_INPUT" =~ ^[0-9]+$ ]] && [[ $SSH_PORT_INPUT -ge 1 ]] && [[ $SSH_PORT_INPUT -le 65535 ]]; then
    SSH_PORT=$SSH_PORT_INPUT
    ok "Port $SSH_PORT wird verwendet"
else
    warn "Ungültiger Port – Standard 22 wird verwendet"
    SSH_PORT=22
fi

# =============================================================================
# Schritt 3: SSH installieren falls nötig
# =============================================================================

echo ""
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo -e "${BOLD}  SSH einrichten${NC}"
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo ""

if ! command -v sshd &>/dev/null; then
    info "OpenSSH Server nicht installiert – wird installiert..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq openssh-server
    ok "OpenSSH Server installiert"
else
    ok "OpenSSH Server bereits installiert"
fi

# =============================================================================
# Schritt 4: Backup der aktuellen sshd_config
# =============================================================================

info "Backup von sshd_config erstellen..."
if [[ -f /etc/ssh/sshd_config ]]; then
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup-$(date +%Y%m%d-%H%M%S)
    ok "Backup erstellt"
fi

# =============================================================================
# Schritt 5: Saubere sshd_config schreiben
# =============================================================================

info "Sichere sshd_config schreiben..."
cat > /etc/ssh/sshd_config <<EOF
# =============================================================
# sshd_config – Key-only, kein Passwort
# Konfiguriert durch ssh-enable.sh (Aeterna™)
# $(date '+%Y-%m-%d %H:%M:%S')
# =============================================================

Port ${SSH_PORT}
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::

# Host Keys
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Authentifizierung
LoginGraceTime 30
PermitRootLogin prohibit-password
StrictModes yes
MaxAuthTries 3
MaxSessions 5

# Nur Key-Authentifizierung
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

# Alles andere deaktiviert
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
UsePAM yes

# Sicherheit
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server

# Verbindungs-Timeout
ClientAliveInterval 300
ClientAliveCountMax 2

# Banner (optional)
# Banner /etc/ssh/banner
EOF
ok "sshd_config geschrieben (Key-only, Port $SSH_PORT)"

# =============================================================================
# Schritt 6: Host Keys generieren falls fehlend
# =============================================================================

if [[ ! -f /etc/ssh/ssh_host_ed25519_key ]]; then
    info "SSH Host Keys generieren..."
    ssh-keygen -A >/dev/null 2>&1
    ok "Host Keys generiert"
fi

# =============================================================================
# Schritt 7: SSH Dienst starten und aktivieren
# =============================================================================

info "SSH Dienst starten..."
# Socket reaktivieren falls vorhanden
if systemctl list-units --type=socket --all 2>/dev/null | grep -q "ssh.socket"; then
    systemctl enable ssh.socket 2>/dev/null || true
fi

# Dienst aktivieren
SSH_SVC=""
for svc in ssh sshd; do
    if systemctl list-units --type=service --all 2>/dev/null | grep -q "${svc}.service"; then
        SSH_SVC="$svc"
        break
    fi
done

if [[ -n "$SSH_SVC" ]]; then
    systemctl enable "$SSH_SVC" 2>/dev/null && ok "Dienst $SSH_SVC aktiviert (Autostart)"
    systemctl restart "$SSH_SVC" 2>/dev/null && ok "Dienst $SSH_SVC gestartet"
else
    warn "SSH-Dienst nicht gefunden – manuell mit 'systemctl start ssh' starten"
fi

# =============================================================================
# Schritt 8: Statusdatei aktualisieren
# =============================================================================

mkdir -p /etc/aeterna
cat > /etc/aeterna/ssh-status <<EOF
STATUS=enabled
KEY_AUTH_ONLY=true
PORT=${SSH_PORT}
ENABLED_AT=$(date '+%Y-%m-%d %H:%M:%S')
KEYS_CONFIGURED=${TOTAL_KEYS}
EOF
ok "Statusdatei aktualisiert"

# =============================================================================
# Verifikation
# =============================================================================

echo ""
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Verifikation${NC}"
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo ""

# Dienst läuft?
if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
    ok "SSH-Dienst läuft ✓"
else
    warn "SSH-Dienst läuft nicht – manuell prüfen!"
fi

# Port offen?
sleep 1
if ss -tlnp 2>/dev/null | grep -q ":${SSH_PORT}"; then
    ok "Port $SSH_PORT ist offen ✓"
else
    warn "Port $SSH_PORT nicht offen – manuell prüfen (ss -tlnp)"
fi

# Keys vorhanden?
ok "$TOTAL_KEYS SSH Key(s) konfiguriert ✓"

# Config-Check
if sshd -t 2>/dev/null; then
    ok "sshd_config Syntax korrekt ✓"
else
    warn "sshd_config hat Syntaxfehler – 'sshd -t' manuell prüfen!"
fi

# Passwort-Auth wirklich deaktiviert?
if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
    ok "Passwort-Login deaktiviert ✓"
fi

echo ""
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}${BOLD}FERTIG – SSH ist aktiv (Key-only).${NC}"
echo ""
echo -e "  Port:          ${CYAN}$SSH_PORT${NC}"
echo -e "  Login als:     ${CYAN}root@$(hostname -I | awk '{print $1}') -p $SSH_PORT${NC}"
echo -e "  Authentif.:    ${CYAN}Nur SSH Key – kein Passwort${NC}"
echo -e "  Keys:          ${CYAN}$TOTAL_KEYS Key(s) in /root/.ssh/authorized_keys${NC}"
echo ""
echo -e "  ${YELLOW}Teste den Login in einem NEUEN Terminal bevor du diese Session schließt!${NC}"
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo ""
