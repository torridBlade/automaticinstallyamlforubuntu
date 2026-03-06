#!/usr/bin/env bash

# ╔══════════════════════════════════════════════════════════════════════════╗

# ║   ΝΞURØN LINUX — UNINSTALL SCRIPT v1.0                                 ║

# ║   Removes all ΝΞURØN hardening and restores original configuration     ║

# ║                                                                          ║

# ║   Usage: sudo bash uninstall.sh                                         ║

# ║   ⚠  A REBOOT is required at the end.                                  ║

# ╚══════════════════════════════════════════════════════════════════════════╝

set -euo pipefail

GRN=’\033[0;32m’ RED=’\033[0;31m’ YLW=’\033[1;33m’ CYN=’\033[0;36m’
BLD=’\033[1m’ DIM=’\033[2m’ RST=’\033[0m’

ok()   { echo -e “  ${GRN}✓${RST}  $*”; }
warn() { echo -e “  ${YLW}⚠${RST}  $*”; }
info() { echo -e “  ${CYN}→${RST}  $*”; }
skip() { echo -e “  ${DIM}·  $* (skipped — not found)${RST}”; }

[[ $EUID -eq 0 ]] || { echo “Must run as root”; exit 1; }

clear
echo -e “${YLW}${BLD}”
cat << ‘BANNER’
██╗   ██╗███╗   ██╗██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗
██║   ██║████╗  ██║██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║
██║   ██║██╔██╗ ██║██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║
██║   ██║██║╚██╗██║██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║
╚██████╔╝██║ ╚████║██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗
╚═════╝ ╚═╝  ╚═══╝╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝

```
          ΝΞURØN LINUX — UNINSTALL & RESTORE
```

BANNER
echo -e “${RST}”

echo -e “  This will remove all ΝΞURØN hardening and restore your”
echo -e “  original system configuration from backups.”
echo “”
echo -e “  ${YLW}A reboot is required when complete.${RST}”
echo “”
read -rp “  Continue? [y/N] “ confirm
[[ “${confirm,,}” == “y” ]] || { echo “Aborted.”; exit 0; }
echo “”

# Find the most recent backup

BACKUP_BASE=”/etc/neuron/backups”
BACKUP_DIR=””
if [[ -d “$BACKUP_BASE” ]]; then
BACKUP_DIR=$(find “$BACKUP_BASE” -mindepth 1 -maxdepth 1 -type d | sort | tail -1)
fi
if [[ -n “$BACKUP_DIR” ]]; then
info “Using backups from: ${BACKUP_DIR}”
else
warn “No backup directory found at ${BACKUP_BASE} — will remove files only, no restore”
fi

restore() {
# Restores a file from backup if it exists, otherwise just removes the target
local target=”$1”
local backed_up=”${BACKUP_DIR}${target}”
if [[ -n “$BACKUP_DIR” ]] && [[ -e “$backed_up” ]]; then
cp -a “$backed_up” “$target” && ok “Restored: ${target}”
elif [[ -e “$target” ]]; then
rm -f “$target” && ok “Removed:  ${target}”
else
skip “$target”
fi
}

remove() {
local target=”$1”
if [[ -e “$target” ]]; then
rm -rf “$target” && ok “Removed:  ${target}”
else
skip “$target”
fi
}

# ─────────────────────────────────────────────────────────────────────────────

echo -e “\n${BLD}[1/10] Stopping & disabling services${RST}”
echo -e “  ${DIM}────────────────────────────────────────────────${RST}”

for svc in neuron-sentinel neuron-aide.timer neuron-aide; do
if systemctl is-active –quiet “$svc” 2>/dev/null; then
systemctl stop “$svc” > /dev/null 2>&1 && info “Stopped: ${svc}”
fi
if systemctl is-enabled –quiet “$svc” 2>/dev/null; then
systemctl disable “$svc” > /dev/null 2>&1 && info “Disabled: ${svc}”
fi
done
ok “Services stopped and disabled”

# ─────────────────────────────────────────────────────────────────────────────

echo -e “\n${BLD}[2/10] Removing systemd units${RST}”
echo -e “  ${DIM}────────────────────────────────────────────────${RST}”

remove /etc/systemd/system/neuron-sentinel.service
remove /etc/systemd/system/neuron-aide.service
remove /etc/systemd/system/neuron-aide.timer
remove /etc/systemd/coredump.conf.d/neuron.conf

systemctl daemon-reload > /dev/null 2>&1
ok “systemd daemon reloaded”

# ─────────────────────────────────────────────────────────────────────────────

echo -e “\n${BLD}[3/10] Removing AI Sentinel & ΝΞURØN binaries${RST}”
echo -e “  ${DIM}────────────────────────────────────────────────${RST}”

remove /usr/lib/neuron
remove /usr/local/bin/neuron-sentinel
remove /usr/local/bin/neuron-verify

ok “ΝΞURØN binaries removed”

# ─────────────────────────────────────────────────────────────────────────────

echo -e “\n${BLD}[4/10] Restoring sysctl configuration${RST}”
echo -e “  ${DIM}────────────────────────────────────────────────${RST}”

remove /etc/sysctl.d/99-neuron.conf
restore /etc/sysctl.conf

# Re-apply the now-restored (or default) sysctl

sysctl –system > /dev/null 2>&1 && ok “Sysctl restored and reloaded” || warn “sysctl reload needs reboot”

# ─────────────────────────────────────────────────────────────────────────────

echo -e “\n${BLD}[5/10] Restoring kernel module policy${RST}”
echo -e “  ${DIM}────────────────────────────────────────────────${RST}”

remove /etc/modprobe.d/neuron-blacklist.conf

# Rebuild initramfs without neuron blacklist

if command -v update-initramfs &>/dev/null; then
update-initramfs -u -k all > /dev/null 2>&1 && ok “initramfs rebuilt” || warn “initramfs rebuild failed”
elif command -v dracut &>/dev/null; then
dracut –force > /dev/null 2>&1 && ok “initramfs rebuilt (dracut)” || warn “dracut failed”
fi

# ─────────────────────────────────────────────────────────────────────────────

echo -e “\n${BLD}[6/10] Restoring GRUB bootloader config${RST}”
echo -e “  ${DIM}────────────────────────────────────────────────${RST}”

GRUB_DEFAULT_FILE=””
for f in /etc/default/grub /etc/default/grub2; do
[[ -f “$f” ]] && GRUB_DEFAULT_FILE=”$f” && break
done

if [[ -n “$GRUB_DEFAULT_FILE” ]]; then
restore “$GRUB_DEFAULT_FILE”

```
# Regenerate GRUB
if   command -v grub2-mkconfig &>/dev/null; then
    grub2-mkconfig -o /boot/grub2/grub.cfg > /dev/null 2>&1
elif command -v update-grub &>/dev/null; then
    update-grub > /dev/null 2>&1
elif command -v grub-mkconfig &>/dev/null; then
    grub-mkconfig -o /boot/grub/grub.cfg > /dev/null 2>&1
fi
ok "GRUB config restored and regenerated"
```

else
skip “GRUB default config not found”
fi

# ─────────────────────────────────────────────────────────────────────────────

echo -e “\n${BLD}[7/10] Restoring SSH, PAM, and security configs${RST}”
echo -e “  ${DIM}────────────────────────────────────────────────${RST}”

remove /etc/ssh/sshd_config.d/99-neuron.conf
remove /etc/neuron/ssh-banner

# Restart SSH with original config

if systemctl is-active –quiet sshd 2>/dev/null; then
systemctl reload sshd > /dev/null 2>&1 && ok “sshd reloaded”
elif systemctl is-active –quiet ssh 2>/dev/null; then
systemctl reload ssh > /dev/null 2>&1 && ok “ssh reloaded”
fi

restore /etc/security/pwquality.conf
restore /etc/security/faillock.conf
remove  /etc/security/limits.d/99-neuron.conf

ok “SSH, PAM, and limits restored”

# ─────────────────────────────────────────────────────────────────────────────

echo -e “\n${BLD}[8/10] Restoring audit, IMA, fstab, and firewall${RST}”
echo -e “  ${DIM}────────────────────────────────────────────────${RST}”

remove /etc/audit/rules.d/99-neuron.rules
if command -v augenrules &>/dev/null; then
augenrules –load > /dev/null 2>&1 || true
fi

remove /etc/ima/ima-policy

restore /etc/fstab

# Restore nftables

if [[ -n “$BACKUP_DIR” ]] && [[ -e “${BACKUP_DIR}/etc/nftables.conf” ]]; then
restore /etc/nftables.conf
nft -f /etc/nftables.conf > /dev/null 2>&1 && ok “nftables ruleset restored” || warn “nftables restore failed”
else
warn “No nftables backup — leaving current ruleset in place”
info “Run ‘nft flush ruleset’ to clear all rules manually if needed”
fi

# Restore fail2ban

remove /etc/fail2ban/jail.d/neuron.conf
remove /etc/fail2ban/filter.d/neuron-sentinel.conf
if systemctl is-active –quiet fail2ban 2>/dev/null; then
systemctl reload fail2ban > /dev/null 2>&1 || true
fi

# Restore AIDE config

restore /etc/aide/aide.conf 2>/dev/null || true

# Restore apt unattended-upgrades config (if we wrote it)

remove /etc/apt/apt.conf.d/50neuron-unattended

ok “Audit rules, IMA, fstab, firewall, fail2ban restored”

# ─────────────────────────────────────────────────────────────────────────────

echo -e “\n${BLD}[9/10] Removing ΝΞURØN data & logs${RST}”
echo -e “  ${DIM}────────────────────────────────────────────────${RST}”

echo “”
read -rp “  Delete forensics, logs, and AI model data? [y/N] “ del_data
if [[ “${del_data,,}” == “y” ]]; then
remove /var/lib/neuron
remove /var/log/neuron
remove /run/neuron
ok “Neuron data and logs deleted”
else
info “Keeping /var/lib/neuron/forensics and /var/log/neuron (delete manually if needed)”
fi

# ─────────────────────────────────────────────────────────────────────────────

echo -e “\n${BLD}[10/10] Removing ΝΞURØN config directory${RST}”
echo -e “  ${DIM}────────────────────────────────────────────────${RST}”

echo “”
read -rp “  Delete /etc/neuron (including all backups)? [y/N] “ del_etc
if [[ “${del_etc,,}” == “y” ]]; then
remove /etc/neuron
ok “/etc/neuron removed”
else
info “Keeping /etc/neuron/backups — delete manually with: sudo rm -rf /etc/neuron”
fi

# ─────────────────────────────────────────────────────────────────────────────

echo “”
echo -e “${GRN}${BLD}”
cat << ‘DONE’
╔══════════════════════════════════════════════════════════════════════════╗
║   ΝΞURØN LINUX UNINSTALL COMPLETE                                       ║
╚══════════════════════════════════════════════════════════════════════════╝
DONE
echo -e “${RST}”
echo -e “  All ΝΞURØN hardening has been removed and your original”
echo -e “  configuration has been restored from backups.”
echo “”
echo -e “  ${YLW}${BLD}⚡ REBOOT NOW to fully restore default kernel behavior:${RST}”
echo -e “     ${CYN}sudo reboot${RST}”
echo “”