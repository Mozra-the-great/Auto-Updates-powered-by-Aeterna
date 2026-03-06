#!/usr/bin/env bash
# =============================================================================
# Debian System Health Check + Interaktiver Fix-Modus
# Ausführen als root: bash debian-healthcheck.sh
# =============================================================================
set -uo pipefail

# --- Farben ---
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()      { echo -e "  ${GREEN}[OK]${NC}       $*"; }
warn()    { echo -e "  ${YELLOW}[WARN]${NC}     $*"; WARNINGS=$((WARNINGS + 1)); }
crit()    { echo -e "  ${RED}[KRITISCH]${NC} $*"; CRITICALS=$((CRITICALS + 1)); }
info()    { echo -e "  ${CYAN}[INFO]${NC}     $*"; }
fixed()   { echo -e "  ${GREEN}[BEHOBEN]${NC}  $*"; }
skipped() { echo -e "  ${CYAN}[SKIP]${NC}     $*"; }
header()  {
    echo -e "\n${BOLD}══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  $*${NC}"
    echo -e "${BOLD}══════════════════════════════════════════════${NC}"
}

[[ $EUID -eq 0 ]] || { echo -e "${RED}Bitte als root ausführen (sudo bash $0)${NC}"; exit 1; }

WARNINGS=0
CRITICALS=0
START_TIME=$(date +%s)

# Fix-Queue: jeder Eintrag = "BESCHREIBUNG|||BEFEHL"
FIXES=()
add_fix() { FIXES+=("${1}|||${2}"); }

# =============================================================================
echo -e "${BOLD}"
echo "  ██████╗ ███████╗██████╗ ██╗ █████╗ ███╗   ██╗"
echo "  ██╔══██╗██╔════╝██╔══██╗██║██╔══██╗████╗  ██║"
echo "  ██║  ██║█████╗  ██████╔╝██║███████║██╔██╗ ██║"
echo "  ██║  ██║██╔══╝  ██╔══██╗██║██╔══██║██║╚██╗██║"
echo "  ██████╔╝███████╗██████╔╝██║██║  ██║██║ ╚████║"
echo "  ╚═════╝ ╚══════╝╚═════╝ ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝"
echo -e "${NC}"
echo -e "  ${CYAN}Debian System Health Check${NC} – $(date '+%d.%m.%Y %H:%M:%S')"
echo -e "  Host: $(hostname -f 2>/dev/null || hostname)"
echo ""
echo -e "  ${BOLD}powered by Aeterna™${NC}"
echo -e "  ${CYAN}Dieses Script wurde mithilfe von KI (Claude by Anthropic) erstellt.${NC}"
echo -e "  ${CYAN}Alle Fixes vor der Ausführung prüfen – keine Haftung für Schäden.${NC}"
echo ""

# =============================================================================
header "1 · SYSTEM INFO"
# =============================================================================

DISTRO=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "Unbekannt")
info "Distro:  $DISTRO"
info "Kernel:  $(uname -r)"
info "Uptime:  $(uptime -p 2>/dev/null || uptime)"
info "Arch:    $(uname -m)"

if ! grep -qi "debian" /etc/os-release 2>/dev/null; then
    warn "Kein Debian-System erkannt – einige Checks könnten ungenau sein"
fi

# =============================================================================
header "2 · UPDATES & PAKETE"
# =============================================================================

info "Paketlisten aktualisieren..."
apt-get update -qq 2>/dev/null || warn "apt-get update fehlgeschlagen"

UPDATES=$(apt-get --just-print upgrade 2>/dev/null | grep "^Inst" | wc -l)
SECURITY_UPDATES=$(apt-get --just-print upgrade 2>/dev/null | grep "^Inst" | grep -i "security" | wc -l)

if [[ $SECURITY_UPDATES -gt 0 ]]; then
    crit "$SECURITY_UPDATES Sicherheits-Updates ausstehend!"
    apt-get --just-print upgrade 2>/dev/null | grep "^Inst" | grep -i "security" | \
        sed 's/^Inst //;s/ .*$//' | while read -r pkg; do echo -e "         → ${RED}$pkg${NC}"; done
    add_fix "$SECURITY_UPDATES Sicherheits-Updates installieren" \
            "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y"
elif [[ $UPDATES -gt 0 ]]; then
    warn "$UPDATES Updates verfügbar (keine Sicherheitsupdates)"
    add_fix "$UPDATES verfügbare Updates installieren" \
            "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y"
else
    ok "System ist aktuell"
fi

BROKEN=$(dpkg -l 2>/dev/null | grep -cE "^(iF|iU|iH|rH|pH|pF|pU)" || echo 0)
if [[ $BROKEN -gt 0 ]]; then
    crit "$BROKEN beschädigte/hängende Pakete gefunden"
    dpkg -l | grep -E "^(iF|iU|iH|rH|pH|pF|pU)" | awk '{print $2}' | \
        while read -r pkg; do echo -e "         → ${RED}$pkg${NC}"; done
    add_fix "Beschädigte Pakete reparieren" \
            "dpkg --configure -a && DEBIAN_FRONTEND=noninteractive apt-get -f install -y"
else
    ok "Keine beschädigten Pakete"
fi

AUTOREMOVE=$(apt-get --dry-run autoremove 2>/dev/null | grep -c "^Remv" || echo 0)
if [[ $AUTOREMOVE -gt 0 ]]; then
    warn "$AUTOREMOVE verwaiste Pakete vorhanden"
    add_fix "$AUTOREMOVE verwaiste Pakete entfernen" \
            "DEBIAN_FRONTEND=noninteractive apt-get autoremove -y"
else
    ok "Keine verwaisten Pakete"
fi

if [[ -f /var/run/reboot-required ]]; then
    crit "Neustart erforderlich! (Kernel oder kritische Bibliothek aktualisiert)"
    [[ -f /var/run/reboot-required.pkgs ]] && \
        while read -r pkg; do echo -e "         → ${RED}$pkg${NC}"; done </var/run/reboot-required.pkgs
    add_fix "System neu starten" "reboot"
else
    ok "Kein Neustart erforderlich"
fi

# =============================================================================
header "3 · SICHERHEIT"
# =============================================================================

if systemctl is-active --quiet unattended-upgrades 2>/dev/null; then
    ok "unattended-upgrades läuft"
else
    crit "unattended-upgrades ist NICHT aktiv"
    add_fix "unattended-upgrades aktivieren und starten" \
            "systemctl enable --now unattended-upgrades"
fi

UPGRADE_LOG="/var/log/unattended-upgrades/unattended-upgrades.log"
if [[ -f "$UPGRADE_LOG" ]]; then
    LAST_UPGRADE=$(stat -c %y "$UPGRADE_LOG" 2>/dev/null | cut -d'.' -f1 || true)
    info "Letzter unattended-upgrades Lauf: ${LAST_UPGRADE:-unbekannt}"
else
    warn "Kein unattended-upgrades Log gefunden"
fi

SSH_CONFIG="/etc/ssh/sshd_config"
if [[ -f "$SSH_CONFIG" ]]; then
    ROOT_LOGIN=$(grep -iE "^PermitRootLogin" "$SSH_CONFIG" | awk '{print $2}' || echo "")
    if [[ "$ROOT_LOGIN" == "yes" ]]; then
        crit "SSH: PermitRootLogin = 'yes' – direkter Root-Login erlaubt!"
        add_fix "SSH: PermitRootLogin auf 'prohibit-password' setzen" \
                "sed -i 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config && systemctl restart sshd"
    elif [[ -z "$ROOT_LOGIN" ]]; then
        warn "SSH: PermitRootLogin nicht explizit gesetzt"
        add_fix "SSH: PermitRootLogin explizit auf 'prohibit-password' setzen" \
                "echo 'PermitRootLogin prohibit-password' >> /etc/ssh/sshd_config && systemctl restart sshd"
    else
        ok "SSH: PermitRootLogin = $ROOT_LOGIN"
    fi

    PASS_AUTH=$(grep -iE "^PasswordAuthentication" "$SSH_CONFIG" | awk '{print $2}' || echo "")
    if [[ "$PASS_AUTH" == "yes" ]]; then
        warn "SSH: PasswordAuthentication aktiv (Key-only empfohlen)"
        add_fix "SSH: PasswordAuthentication deaktivieren (NUR wenn SSH-Keys eingerichtet sind!)" \
                "sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && systemctl restart sshd"
    elif [[ -z "$PASS_AUTH" ]]; then
        warn "SSH: PasswordAuthentication nicht explizit gesetzt"
        add_fix "SSH: PasswordAuthentication explizit auf 'yes' setzen" \
                "echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config && systemctl restart sshd"
    else
        ok "SSH: PasswordAuthentication = $PASS_AUTH"
    fi

    SSH_PORT=$(grep -iE "^Port " "$SSH_CONFIG" | awk '{print $2}' || echo "22")
    if [[ "${SSH_PORT:-22}" == "22" ]]; then
        warn "SSH läuft auf Standard-Port 22"
    else
        ok "SSH: Port $SSH_PORT (nicht Standard)"
    fi
else
    info "Kein SSH-Server gefunden"
fi

info "Offene Ports (listening):"
if command -v ss &>/dev/null; then
    ss -tlnp 2>/dev/null | grep LISTEN | awk '{print $4, $6}' | \
        sed 's/users:((//' | sed 's/,.*//' | sed 's/("/ → /' | sed 's/"//' | \
        while read -r line; do echo -e "         ${CYAN}$line${NC}"; done
fi

if command -v journalctl &>/dev/null; then
    FAILED_LOGINS=$(journalctl --since "24 hours ago" 2>/dev/null | \
        grep -c "Failed password\|authentication failure" 2>/dev/null || echo 0)
    if [[ $FAILED_LOGINS -gt 100 ]]; then
        crit "$FAILED_LOGINS fehlgeschlagene Login-Versuche in 24h – möglicher Brute-Force!"
    elif [[ $FAILED_LOGINS -gt 10 ]]; then
        warn "$FAILED_LOGINS fehlgeschlagene Login-Versuche in den letzten 24h"
    else
        ok "Fehlgeschlagene Logins (24h): $FAILED_LOGINS"
    fi
fi

if systemctl is-active --quiet fail2ban 2>/dev/null; then
    ok "fail2ban läuft"
    BANNED=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $NF}' || echo "?")
    info "fail2ban SSH – aktuell gebannte IPs: $BANNED"
elif command -v fail2ban-client &>/dev/null; then
    warn "fail2ban installiert aber nicht aktiv"
    add_fix "fail2ban aktivieren und starten" \
            "systemctl enable --now fail2ban"
else
    warn "fail2ban nicht installiert (Brute-Force-Schutz fehlt)"
    add_fix "fail2ban installieren und aktivieren" \
            "DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban && systemctl enable --now fail2ban"
fi

if command -v ufw &>/dev/null; then
    UFW_STATUS=$(ufw status 2>/dev/null | head -1 | awk '{print $2}')
    if [[ "$UFW_STATUS" == "active" ]]; then
        ok "UFW Firewall aktiv"
    else
        warn "UFW installiert aber nicht aktiv"
        add_fix "UFW aktivieren (SSH wird automatisch freigegeben)" \
                "ufw allow OpenSSH && ufw --force enable"
    fi
else
    warn "Keine Firewall (ufw) gefunden"
    add_fix "UFW installieren und aktivieren (SSH wird freigegeben)" \
            "DEBIAN_FRONTEND=noninteractive apt-get install -y ufw && ufw allow OpenSSH && ufw --force enable"
fi

# =============================================================================
header "4 · RESSOURCEN"
# =============================================================================

LOAD=$(awk '{print $1}' /proc/loadavg)
CORES=$(nproc)
if (( $(echo "$LOAD > $CORES * 2" | bc -l 2>/dev/null || echo 0) )); then
    crit "CPU Auslastung sehr hoch: Load $LOAD bei $CORES Cores"
elif (( $(echo "$LOAD > $CORES" | bc -l 2>/dev/null || echo 0) )); then
    warn "CPU Auslastung erhöht: Load $LOAD bei $CORES Cores"
else
    ok "CPU Load: $LOAD (Cores: $CORES)"
fi

MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
MEM_USED=$(free -m | awk '/^Mem:/{print $3}')
MEM_PCT=$(( MEM_USED * 100 / MEM_TOTAL ))
if [[ $MEM_PCT -gt 90 ]]; then
    crit "RAM Auslastung: ${MEM_PCT}% (${MEM_USED}MB / ${MEM_TOTAL}MB)"
elif [[ $MEM_PCT -gt 75 ]]; then
    warn "RAM Auslastung: ${MEM_PCT}% (${MEM_USED}MB / ${MEM_TOTAL}MB)"
else
    ok "RAM: ${MEM_PCT}% belegt (${MEM_USED}MB / ${MEM_TOTAL}MB)"
fi

SWAP_TOTAL=$(free -m | awk '/^Swap:/{print $2}')
SWAP_USED=$(free -m | awk '/^Swap:/{print $3}')
if [[ $SWAP_TOTAL -eq 0 ]]; then
    warn "Kein Swap konfiguriert"
    add_fix "512MB Swap-Datei erstellen und aktivieren" \
            "fallocate -l 512M /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile && echo '/swapfile none swap sw 0 0' >> /etc/fstab"
else
    SWAP_PCT=$(( SWAP_USED * 100 / SWAP_TOTAL ))
    if [[ $SWAP_PCT -gt 50 ]]; then
        warn "Swap Nutzung: ${SWAP_PCT}% (${SWAP_USED}MB / ${SWAP_TOTAL}MB)"
    else
        ok "Swap: ${SWAP_PCT}% genutzt (${SWAP_USED}MB / ${SWAP_TOTAL}MB)"
    fi
fi

echo ""
info "Festplatten-Auslastung:"
while read -r mount pct size used avail; do
    PCT_NUM=${pct//%/}
    if [[ $PCT_NUM -gt 90 ]]; then
        echo -e "         ${RED}[KRITISCH]${NC} $mount → ${pct} (${used} / ${size})"
        CRITICALS=$((CRITICALS + 1))
        add_fix "Festplatte $mount aufräumen (Paket-Cache + Journal leeren)" \
                "apt-get clean && journalctl --vacuum-size=100M"
    elif [[ $PCT_NUM -gt 75 ]]; then
        echo -e "         ${YELLOW}[WARN]${NC}    $mount → ${pct} (${used} / ${size})"
    else
        echo -e "         ${GREEN}[OK]${NC}      $mount → ${pct} (${used} / ${size})"
    fi
done < <(df -h --output=target,pcent,size,used,avail 2>/dev/null | grep -v "tmpfs\|udev\|cgrou" | tail -n +2)

# =============================================================================
header "5 · DIENSTE"
# =============================================================================

FAILED_SERVICES=$(systemctl --failed --no-legend 2>/dev/null | grep -c "failed" || echo 0)
if [[ $FAILED_SERVICES -gt 0 ]]; then
    crit "$FAILED_SERVICES fehlgeschlagene Dienste:"
    while read -r svc; do
        echo -e "         → ${RED}$svc${NC}"
        add_fix "Dienst '$svc' neu starten" "systemctl restart $svc"
    done < <(systemctl --failed --no-legend 2>/dev/null | grep "failed" | awk '{print $2}')
else
    ok "Keine fehlgeschlagenen Dienste"
fi

for svc in ssh sshd cron rsyslog systemd-timesyncd; do
    if systemctl list-units --type=service --all 2>/dev/null | grep -q "${svc}.service"; then
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            ok "Dienst $svc läuft"
        else
            warn "Dienst $svc ist nicht aktiv"
            add_fix "Dienst '$svc' starten und aktivieren" "systemctl enable --now $svc"
        fi
    fi
done

# =============================================================================
header "6 · LOGS & FEHLER"
# =============================================================================

KERNEL_ERRORS=$(journalctl -k --since "24 hours ago" -p err 2>/dev/null | grep -vc "^-- " || echo 0)
if [[ $KERNEL_ERRORS -gt 0 ]]; then
    warn "$KERNEL_ERRORS Kernel-Fehler in den letzten 24h"
    journalctl -k --since "24 hours ago" -p err 2>/dev/null | grep -v "^-- " | tail -5 | \
        while read -r line; do echo -e "         ${YELLOW}$line${NC}"; done
else
    ok "Keine Kernel-Fehler in den letzten 24h"
fi

OOM=$(journalctl --since "7 days ago" 2>/dev/null | grep -c "Out of memory\|oom_kill" || echo 0)
if [[ $OOM -gt 0 ]]; then
    crit "OOM-Killer war in den letzten 7 Tagen ${OOM}x aktiv (RAM-Mangel!)"
else
    ok "OOM-Killer: keine Aktivität in den letzten 7 Tagen"
fi

IO_ERRORS=$(journalctl --since "7 days ago" 2>/dev/null | grep -cE "I/O error|hard resetting|Buffer I/O" || echo 0)
if [[ $IO_ERRORS -gt 0 ]]; then
    crit "$IO_ERRORS Festplatten I/O-Fehler in den letzten 7 Tagen – Hardware prüfen!"
else
    ok "Keine Festplatten I/O-Fehler"
fi

JOURNAL_BYTES=$(journalctl --disk-usage 2>/dev/null | grep -oP '\d+(?= bytes)' | head -1 || echo 0)
JOURNAL_MB=$(( ${JOURNAL_BYTES:-0} / 1024 / 1024 ))
info "Journal Log-Größe: ${JOURNAL_MB}MB"
if [[ $JOURNAL_MB -gt 500 ]]; then
    warn "Journal-Log sehr groß (${JOURNAL_MB}MB)"
    add_fix "Journal-Log auf 200MB reduzieren" "journalctl --vacuum-size=200M"
fi

# =============================================================================
header "7 · ZEITSERVER (NTP)"
# =============================================================================

if systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
    SYNC_STATUS=$(timedatectl show 2>/dev/null | grep NTPSynchronized | cut -d= -f2 || echo "unknown")
    if [[ "$SYNC_STATUS" == "yes" ]]; then
        ok "NTP synchronisiert (systemd-timesyncd)"
        timedatectl 2>/dev/null | grep "System clock\|NTP service\|Time zone" | \
            while read -r line; do echo -e "         ${CYAN}$line${NC}"; done
    else
        warn "NTP läuft aber nicht synchronisiert"
        add_fix "NTP Synchronisation erzwingen" \
                "systemctl restart systemd-timesyncd && timedatectl set-ntp true"
    fi
elif command -v ntpq &>/dev/null && systemctl is-active --quiet ntp 2>/dev/null; then
    ok "NTP läuft (ntpd)"
else
    warn "Kein NTP-Dienst aktiv"
    add_fix "NTP aktivieren (systemd-timesyncd)" \
            "timedatectl set-ntp true && systemctl enable --now systemd-timesyncd"
fi

# =============================================================================
header "8 · ZUSAMMENFASSUNG"
# =============================================================================

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo ""
echo -e "  Laufzeit: ${DURATION}s  |  Host: $(hostname)  |  $(date '+%d.%m.%Y %H:%M:%S')"
echo ""

[[ $CRITICALS -gt 0 ]] && echo -e "  ${RED}${BOLD}● KRITISCH: $CRITICALS kritische Probleme${NC}"
[[ $WARNINGS  -gt 0 ]] && echo -e "  ${YELLOW}${BOLD}● WARNUNG:  $WARNINGS Warnungen${NC}"
[[ $CRITICALS -eq 0 && $WARNINGS -eq 0 ]] && echo -e "  ${GREEN}${BOLD}● ALLES OK – System ist gesund!${NC}"

# =============================================================================
# FIX-MODUS
# =============================================================================

TOTAL_FIXES=${#FIXES[@]}

if [[ $TOTAL_FIXES -eq 0 ]]; then
    echo ""
    echo -e "  ${GREEN}Keine behebbaren Probleme gefunden.${NC}"
    echo -e "\n══════════════════════════════════════════════\n"
    exit 0
fi

echo ""
echo -e "  ${BOLD}$TOTAL_FIXES behebbare(s) Problem(e) gefunden.${NC}"
echo ""
echo -ne "  ${BOLD}Sollen Probleme interaktiv behoben werden? [j/N]:${NC} "
read -r ANSWER </dev/tty
echo ""

if [[ ! "$ANSWER" =~ ^[jJyY]$ ]]; then
    echo -e "  Fix-Modus übersprungen. Befehle zur manuellen Ausführung:\n"
    for fix_entry in "${FIXES[@]}"; do
        echo -e "  ${CYAN}→ ${fix_entry%%|||*}${NC}"
        echo -e "    ${YELLOW}${fix_entry##*|||}${NC}\n"
    done
    echo -e "══════════════════════════════════════════════\n"
    exit 0
fi

header "9 · INTERAKTIVER FIX-MODUS"
echo -e "  ${CYAN}[j] Ja   [n/Enter] Überspringen   [a] Alle   [q] Abbrechen${NC}"

FIXED_COUNT=0
SKIPPED_COUNT=0
FIX_NUM=0
RUN_ALL=0

for fix_entry in "${FIXES[@]}"; do
    DESC="${fix_entry%%|||*}"
    CMD="${fix_entry##*|||}"
    FIX_NUM=$((FIX_NUM + 1))

    echo ""
    echo -e "  ${BOLD}[$FIX_NUM/$TOTAL_FIXES]${NC} ${YELLOW}$DESC${NC}"
    echo -e "  ${CYAN}▶ $CMD${NC}"

    if [[ $RUN_ALL -eq 1 ]]; then
        CHOICE="j"
    else
        echo ""
        echo -ne "  Ausführen? [j/n/a=alle/q=abbrechen]: "
        read -r CHOICE </dev/tty
    fi

    case "$CHOICE" in
        a|A)
            RUN_ALL=1
            CHOICE="j"
            echo -e "  ${CYAN}Alle verbleibenden Fixes werden ausgeführt...${NC}"
            ;;&
        j|J|y|Y)
            echo ""
            if eval "$CMD"; then
                fixed "$DESC"
                FIXED_COUNT=$((FIXED_COUNT + 1))
            else
                echo -e "  ${RED}[FEHLER]${NC} Befehl fehlgeschlagen – bitte manuell prüfen"
            fi
            ;;
        q|Q)
            echo ""
            echo -e "  ${CYAN}Fix-Modus abgebrochen.${NC}"
            break
            ;;
        *)
            skipped "$DESC"
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            ;;
    esac
done

echo ""
echo "══════════════════════════════════════════════"
echo -e "  ${GREEN}Behoben: $FIXED_COUNT${NC}  |  ${YELLOW}Übersprungen: $SKIPPED_COUNT${NC}  |  Gesamt: $TOTAL_FIXES"
if [[ $FIXED_COUNT -gt 0 ]]; then
    echo ""
    echo -e "  ${CYAN}Tipp: Script erneut ausführen um den neuen Status zu prüfen.${NC}"
fi
echo -e "══════════════════════════════════════════════\n"
