#!/usr/bin/env bash
# =============================================================================
# FIX-Script: Korrigiert Systeme auf denen das originale Setup-Script
#             bereits ausgeführt wurde.
#
# Behebt:
#   1. Origins-Pattern Merge-Bug (51er-Datei überschreibt 50er nicht)
#   2. Fehlende ::clear Direktive
#   3. Fehlende Einstellungen: Automatic-Reboot, Mail, Remove-Unused-Deps, Syslog
#   4. needrestart installieren + konfigurieren
#
# Ausführen als root: bash fix-auto-security-updates.sh
# =============================================================================
set -uo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fixed()   { echo -e "${CYAN}[FIXED]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || error "Bitte als root ausführen (sudo bash $0)"

# --- Branding ---
echo -e "\n  \033[1mpowered by Aeterna™\033[0m"
echo -e "  \033[0;36mDieses Script wurde mithilfe von KI (Claude by Anthropic) erstellt.\033[0m\n"

CONF51="/etc/apt/apt.conf.d/51unattended-security-only"
CONF50="/etc/apt/apt.conf.d/50unattended-upgrades"

# --- Konfiguration (hier anpassen) ---
MAIL_ADDRESS="root"
MAIL_REPORT="on-change"
AUTO_REBOOT="false"
AUTO_REBOOT_TIME="02:00"
REMOVE_UNUSED_DEPS="true"
# =============================================================================

echo ""
echo "============================================================"
echo " Vor-Check: Ist das originale Script ausgeführt worden?"
echo "============================================================"

ISSUES=0

# Check 1: 51er-Datei vorhanden?
if [[ ! -f "$CONF51" ]]; then
    warn "51unattended-security-only nicht gefunden – originales Script evtl. nicht gelaufen?"
    warn "Trotzdem weiter mit Fixes..."
else
    info "51unattended-security-only gefunden ✓"
fi

# Check 2: ::clear fehlt?
if [[ -f "$CONF51" ]] && ! grep -q "Origins-Pattern::clear" "$CONF51"; then
    warn "BUG GEFUNDEN: Origins-Pattern::clear fehlt in 51er-Datei → Merge-Bug aktiv"
    ISSUES=$((ISSUES + 1))
else
    info "Origins-Pattern::clear vorhanden ✓"
fi

# Check 3: Automatic-Reboot fehlt?
if [[ -f "$CONF51" ]] && ! grep -q "Automatic-Reboot" "$CONF51"; then
    warn "BUG GEFUNDEN: Automatic-Reboot nicht konfiguriert"
    ISSUES=$((ISSUES + 1))
else
    info "Automatic-Reboot konfiguriert ✓"
fi

# Check 4: needrestart installiert?
if ! dpkg -l needrestart &>/dev/null; then
    warn "needrestart nicht installiert"
    ISSUES=$((ISSUES + 1))
else
    info "needrestart installiert ✓"
fi

echo ""
[[ $ISSUES -eq 0 ]] && { info "Keine bekannten Bugs gefunden. Trotzdem alles neu schreiben? (Ctrl+C zum Abbrechen)"; sleep 3; }
echo ""

# =============================================================================
echo "============================================================"
echo " Fixes anwenden..."
echo "============================================================"
echo ""

# --- FIX 1: 51er-Datei komplett neu schreiben mit allen Fixes ---
info "Fix 1: 51unattended-security-only neu schreiben..."
cat >"$CONF51" <<EOF
// ============================================================
// NUR Sicherheitsupdates – alle anderen Origins deaktivieren
// Neu geschrieben durch fix-auto-security-updates.sh
// ============================================================

// Vorherige Origins-Liste leeren (verhindert Merge-Probleme mit 50er-Datei)
Unattended-Upgrade::Origins-Pattern::clear "";

Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=\${distro_codename}-security,label=Debian-Security";
};

// Verwaiste Abhängigkeiten aufräumen
Unattended-Upgrade::Remove-Unused-Dependencies "${REMOVE_UNUSED_DEPS}";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";

// Neustart-Verhalten (bewusste Entscheidung!)
Unattended-Upgrade::Automatic-Reboot "${AUTO_REBOOT}";
Unattended-Upgrade::Automatic-Reboot-Time "${AUTO_REBOOT_TIME}";

// E-Mail-Berichte
Unattended-Upgrade::Mail "${MAIL_ADDRESS}";
Unattended-Upgrade::MailReport "${MAIL_REPORT}";

// Syslog
Unattended-Upgrade::SyslogEnable "true";
Unattended-Upgrade::SyslogFacility "daemon";
EOF
fixed "51unattended-security-only neu geschrieben"

# --- FIX 2: Kaputte Zeile in 50er-Datei patchen ---
info "Fix 2: Kaputte Zeile in 50unattended-upgrades prüfen..."
if [[ -f "$CONF50" ]]; then
    if grep -qP '^[^/]*"origin=Debian,codename=-security,label=Debian-Security"' "$CONF50"; then
        sed -i 's|^\([[:space:]]*\)"\(origin=Debian,codename=\)-security,label=Debian-Security";|\1// disabled (broken): "\2-security,label=Debian-Security";|g' "$CONF50"
        fixed "Kaputte Zeile in 50unattended-upgrades auskommentiert"
    else
        info "Keine kaputte Zeile in 50unattended-upgrades gefunden ✓"
    fi

    # Außerdem: Nicht-Security Origins aus 50er auskommentieren (werden durch clear ohnehin ignoriert,
    # aber sauber ist sauber)
    info "Fix 2b: Nicht-Security Origins in 50er auskommentieren (redundant, aber sauber)..."
    sed -i 's|^\([[:space:]]*\)"\(origin=Debian,codename=\${distro_codename},.*\)";|\1// disabled by fix-script: "\2";|g' \
        "$CONF50" || true
    sed -i 's|^\([[:space:]]*\)"\(origin=Debian,codename=\${distro_codename}-updates,.*\)";|\1// disabled by fix-script: "\2";|g' \
        "$CONF50" || true
    fixed "50unattended-upgrades bereinigt"
else
    warn "$CONF50 nicht gefunden – übersprungen"
fi

# --- FIX 3: needrestart installieren ---
info "Fix 3: needrestart installieren..."
export DEBIAN_FRONTEND=noninteractive
if ! dpkg -l needrestart &>/dev/null; then
    apt-get install -y -qq needrestart
    fixed "needrestart installiert"
else
    info "needrestart bereits installiert ✓"
fi

# needrestart: Dienste automatisch neu starten
NEEDRESTART_CONF="/etc/needrestart/needrestart.conf"
if [[ -f "$NEEDRESTART_CONF" ]]; then
    if ! grep -q '^\$nrconf{restart}' "$NEEDRESTART_CONF"; then
        sed -i "s|^#\?\$nrconf{restart}.*|\$nrconf{restart} = 'a';|" "$NEEDRESTART_CONF" || true
        fixed "needrestart auf automatischen Dienst-Neustart konfiguriert"
    else
        info "needrestart bereits konfiguriert ✓"
    fi
fi

# --- FIX 4: Dienst neu starten ---
info "Fix 4: unattended-upgrades Dienst neu starten..."
if systemctl restart unattended-upgrades 2>/dev/null; then
    fixed "Dienst neu gestartet"
else
    warn "systemctl restart fehlgeschlagen – manuell prüfen"
fi

# =============================================================================
echo ""
echo "============================================================"
echo " Verifikation"
echo "============================================================"
echo ""

echo "--- Aktive Origins nach Fix ---"
grep -n "codename=.*security\|Origins-Pattern::clear" \
    "$CONF50" "$CONF51" 2>/dev/null || true

echo ""
echo "--- Dry-Run ---"
unattended-upgrades --dry-run --debug 2>&1 | \
    grep -E "Allowed origins|origin=Debian|All upgrades installed|No packages found|Marking not allowed|ERROR" | \
    tail -n 50 || warn "Dry-run Ausgabe leer – Log manuell prüfen"

echo ""
echo "============================================================"
echo -e "${GREEN}FERTIG.${NC} Alle Fixes angewendet."
echo ""
echo "Logs:     journalctl -u unattended-upgrades -f"
echo "          tail -f /var/log/unattended-upgrades/unattended-upgrades.log"
echo "Manuell:  unattended-upgrades --debug"
echo "============================================================"
