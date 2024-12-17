#!/usr/bin/env ash

# https://openwrt.org/docs/guide-user/troubleshooting/backup_restore

umask go=
bkup_dir="/tmp/"
bkup_filename="backup-$HOSTNAME-$(date +%F).tar.gz"
bkup_abspath="$bkup_dir"/"$bkup_filename"
echo "[*] Backup confs to $bkup_abspath"
sysupgrade -b $bkup_abspath
ls $bkup_abspath
