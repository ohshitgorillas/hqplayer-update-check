#!/usr/bin/env bash
set -euo pipefail

TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector"
_HUMAN_HOME=$(getent passwd | awk -F: '$3>=1000 && $3<65534 && $6~/^\/home/{print $6; exit}')
DOWNLOAD_DIR="${_HUMAN_HOME}/hqplayer-downloads"
STATE_DIR="/etc/hqplayer-update-check"
NAA_STATE_FILE="$STATE_DIR/naa_known_version"
DESKTOP_STATE_FILE="$STATE_DIR/desktop_known_version"
PROM_FILE="$TEXTFILE_DIR/hqplayer_update.prom"
BINS_URL="https://www.signalyst.eu/bins/hqplayerd/noble/"
RSS_NAA="https://signalyst.com/category/naa/feed/"
RSS_DESKTOP="https://signalyst.com/category/desktop/feed/"

mkdir -p "$STATE_DIR" "$DOWNLOAD_DIR"

# ── HQPlayer Embedded ────────────────────────────────────────────────────────

INSTALLED_HQP=$(dpkg-query -W -f='${Version}' hqplayerd 2>/dev/null || true)

# Find latest intel deb from directory listing
LATEST_DEB=$(curl -sf --max-time 15 "$BINS_URL" | python3 -c "
import sys, re
from html.parser import HTMLParser

class P(HTMLParser):
    links = []
    def handle_starttag(self, tag, attrs):
        if tag == 'a':
            for k, v in attrs:
                if k == 'href' and v and v.endswith('intel_amd64.deb'):
                    self.links.append(v)

p = P(); p.feed(sys.stdin.read())

def key(f):
    m = re.search(r'(\d+)\.(\d+)\.(\d+)-(\d+)intel', f)
    return tuple(int(x) for x in m.groups()) if m else (0,0,0,0)

if p.links:
    print(sorted(p.links, key=key)[-1])
" 2>/dev/null || true)

LATEST_HQP_VER=$(echo "$LATEST_DEB" | grep -oP '\d+\.\d+\.\d+-\d+intel' || true)

HQP_UPDATE=0
HQP_SUCCESS=1

if [[ -z "$LATEST_DEB" || -z "$LATEST_HQP_VER" ]]; then
    HQP_SUCCESS=0
elif [[ "$INSTALLED_HQP" != "$LATEST_HQP_VER" ]]; then
    HQP_UPDATE=1
    DEB_PATH="$DOWNLOAD_DIR/$LATEST_DEB"
    if [[ ! -f "$DEB_PATH" ]]; then
        logger -t hqplayer-update "Downloading $LATEST_DEB..."
        curl -sf --max-time 300 -o "$DEB_PATH" "${BINS_URL}${LATEST_DEB}" \
            && logger -t hqplayer-update "Downloaded to $DEB_PATH" \
            || { logger -t hqplayer-update "Download failed"; HQP_SUCCESS=0; }
    fi
fi

# ── NAA ──────────────────────────────────────────────────────────────────────

LATEST_NAA=$(curl -sf --max-time 15 "$RSS_NAA" | python3 -c "
import sys, xml.etree.ElementTree as ET, re
root = ET.fromstring(sys.stdin.read())
for item in root.iter('item'):
    t = item.find('title')
    if t is not None and t.text:
        m = re.search(r'(\d+\.\d+\.\d+)', t.text)
        if m:
            print(m.group(1)); break
" 2>/dev/null || true)

NAA_UPDATE=0
NAA_SUCCESS=1
KNOWN_NAA="unknown"

if [[ -z "$LATEST_NAA" ]]; then
    NAA_SUCCESS=0
else
    if [[ ! -f "$NAA_STATE_FILE" ]]; then
        echo "$LATEST_NAA" > "$NAA_STATE_FILE"
        logger -t hqplayer-update "NAA baseline set to $LATEST_NAA"
    fi
    KNOWN_NAA=$(cat "$NAA_STATE_FILE")
    if [[ "$LATEST_NAA" != "$KNOWN_NAA" ]]; then
        NAA_UPDATE=1
        echo "$LATEST_NAA" > "$NAA_STATE_FILE"
        logger -t hqplayer-update "NAA update: $KNOWN_NAA -> $LATEST_NAA"
    fi
fi

# ── HQPlayer Desktop ─────────────────────────────────────────────────────────

LATEST_DESKTOP=$(curl -sf --max-time 15 "$RSS_DESKTOP" | python3 -c "
import sys, xml.etree.ElementTree as ET, re
root = ET.fromstring(sys.stdin.read())
for item in root.iter('item'):
    t = item.find('title')
    if t is not None and t.text:
        m = re.search(r'(\d+\.\d+\.\d+)', t.text)
        if m:
            print(m.group(1)); break
" 2>/dev/null || true)

DESKTOP_UPDATE=0
DESKTOP_SUCCESS=1
KNOWN_DESKTOP="unknown"

if [[ -z "$LATEST_DESKTOP" ]]; then
    DESKTOP_SUCCESS=0
else
    if [[ ! -f "$DESKTOP_STATE_FILE" ]]; then
        echo "$LATEST_DESKTOP" > "$DESKTOP_STATE_FILE"
        logger -t hqplayer-update "Desktop baseline set to $LATEST_DESKTOP"
    fi
    KNOWN_DESKTOP=$(cat "$DESKTOP_STATE_FILE")
    if [[ "$LATEST_DESKTOP" != "$KNOWN_DESKTOP" ]]; then
        DESKTOP_UPDATE=1
        echo "$LATEST_DESKTOP" > "$DESKTOP_STATE_FILE"
        logger -t hqplayer-update "Desktop update: $KNOWN_DESKTOP -> $LATEST_DESKTOP"
    fi
fi

# ── Metrics ───────────────────────────────────────────────────────────────────

{
    echo '# HELP hqplayer_update_available 1 if new HQPlayer Embedded version downloaded and ready to install'
    echo '# TYPE hqplayer_update_available gauge'
    echo "hqplayer_update_available{installed=\"${INSTALLED_HQP:-unknown}\",latest=\"${LATEST_HQP_VER:-unknown}\"} $HQP_UPDATE"
    echo '# HELP hqplayer_update_check_success 1 if version check succeeded'
    echo '# TYPE hqplayer_update_check_success gauge'
    echo "hqplayer_update_check_success $HQP_SUCCESS"
    echo '# HELP naa_update_available 1 if NAA update available on signalyst.com'
    echo '# TYPE naa_update_available gauge'
    echo "naa_update_available{known=\"${KNOWN_NAA}\",latest=\"${LATEST_NAA:-unknown}\"} $NAA_UPDATE"
    echo '# HELP naa_update_check_success 1 if NAA RSS check succeeded'
    echo '# TYPE naa_update_check_success gauge'
    echo "naa_update_check_success $NAA_SUCCESS"
    echo '# HELP desktop_update_available 1 if HQPlayer Desktop update available on signalyst.com'
    echo '# TYPE desktop_update_available gauge'
    echo "desktop_update_available{known=\"${KNOWN_DESKTOP}\",latest=\"${LATEST_DESKTOP:-unknown}\"} $DESKTOP_UPDATE"
    echo '# HELP desktop_update_check_success 1 if Desktop RSS check succeeded'
    echo '# TYPE desktop_update_check_success gauge'
    echo "desktop_update_check_success $DESKTOP_SUCCESS"
} > "${PROM_FILE}.tmp"
mv "${PROM_FILE}.tmp" "$PROM_FILE"
