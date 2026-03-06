#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo “Run as root”; exit 1; }

# Stop services

systemctl stop neuron-sentinel neuron-aide.timer neuron-aide 2>/dev/null || true
systemctl disable neuron-sentinel neuron-aide.timer neuron-aide 2>/dev/null || true

# Remove systemd units

rm -f /etc/systemd/system/neuron-sentinel.service
rm -f /etc/systemd/system/neuron-aide.service
rm -f /etc/systemd/system/neuron-aide.timer
rm -f /etc/systemd/coredump.conf.d/neuron.conf
systemctl daemon-reload

# Remove binaries

rm -rf /usr/lib/neuron
rm -f /usr/local/bin/neuron-sentinel
rm -f /usr/local/bin/neuron-verify

# Remove config files

rm -f /etc/sysctl.d/99-neuron.conf
rm -f /etc/modprobe.d/neuron-blacklist.conf
rm -f /etc/ssh/sshd_config.d/99-neuron.conf
rm -f /etc/audit/rules.d/99-neuron.rules
rm -f /etc/ima/ima-policy
rm -f /etc/fail2ban/jail.d/neuron.conf
rm -f /etc/fail2ban/filter.d/neuron-sentinel.conf
rm -f /etc/security/limits.d/99-neuron.conf
rm -f /etc/apt/apt.conf.d/50neuron-unattended

# Restore backups if they exist

BACKUP=$(find /etc/neuron/backups -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -1)
if [[ -n “$BACKUP” ]]; then
for f in sysctl.conf fstab; do
[[ -f “$BACKUP/etc/$f” ]] && cp -a “$BACKUP/etc/$f” “/etc/$f”
done
[[ -f “$BACKUP/etc/default/grub” ]] && cp -a “$BACKUP/etc/default/grub” /etc/default/grub
[[ -f “$BACKUP/etc/security/pwquality.conf” ]] && cp -a “$BACKUP/etc/security/pwquality.conf” /etc/security/pwquality.conf
fi

# Reload services

sysctl –system > /dev/null 2>&1 || true
systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
systemctl reload fail2ban 2>/dev/null || true
command -v augenrules &>/dev/null && augenrules –load > /dev/null 2>&1 || true

# Rebuild initramfs

if command -v update-initramfs &>/dev/null; then
update-initramfs -u -k all > /dev/null 2>&1
elif command -v dracut &>/dev/null; then
dracut –force > /dev/null 2>&1
fi

# Regenerate GRUB

if   command -v grub2-mkconfig &>/dev/null; then grub2-mkconfig -o /boot/grub2/grub.cfg > /dev/null 2>&1
elif command -v update-grub    &>/dev/null; then update-grub > /dev/null 2>&1
elif command -v grub-mkconfig  &>/dev/null; then grub-mkconfig -o /boot/grub/grub.cfg > /dev/null 2>&1
fi

# Remove data

rm -rf /var/lib/neuron /var/log/neuron /run/neuron /etc/neuron

echo “Done. Reboot to complete removal.”