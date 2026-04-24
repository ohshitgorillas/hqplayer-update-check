#!/usr/bin/env bash
# Run once as root to install the update check service
set -euo pipefail

HUMAN_HOME=$(getent passwd | awk -F: '$3>=1000 && $3<65534 && $6~/^\/home/{print $6; exit}')
mkdir -p /var/lib/node_exporter/textfile_collector
mkdir -p /etc/hqplayer-update-check
mkdir -p "${HUMAN_HOME}/hqplayer-downloads"

install -m 755 /srv/hqplayer-update-check/hqplayer-update-check.sh /usr/local/bin/hqplayer-update-check
install -m 644 /srv/hqplayer-update-check/hqplayer-update-check.service /etc/systemd/system/
install -m 644 /srv/hqplayer-update-check/hqplayer-update-check.timer /etc/systemd/system/

systemctl daemon-reload
systemctl enable --now hqplayer-update-check.timer

echo "Running initial check..."
systemctl start hqplayer-update-check
journalctl -u hqplayer-update-check -n 20 --no-pager

echo "Restarting node-exporter with textfile collector..."
cd /srv/o11y && docker compose up -d node_exporter

echo "Done. Timer status:"
systemctl status hqplayer-update-check.timer --no-pager
