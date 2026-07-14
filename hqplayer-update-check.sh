#!/usr/bin/env bash
set -euo pipefail

TEXTFILE_DIR="/var/lib/node_exporter/textfile_collector"
_HUMAN_HOME=$(getent passwd | awk -F: '$3>=1000 && $3<65534 && $6~/^\/home/{print $6; exit}')
DOWNLOAD_DIR="${_HUMAN_HOME}/hqplayer-downloads"
STATE_DIR="/etc/hqplayer-update-check"
NAA_STATE_FILE="$STATE_DIR/naa_known_version"
DESKTOP_STATE_FILE="$STATE_DIR/desktop_known_version"
PROM_FILE="$TEXTFILE_DIR/hqplayer_update.prom"
RUNNING_FC=$(rpm -E %fedora)
BINS_ROOT="https://www.signalyst.eu/bins/hqplayerd/"
BINS_URL="${BINS_ROOT}fc${RUNNING_FC}/"
RSS_NAA="https://signalyst.com/category/naa/feed/"
RSS_DESKTOP="https://signalyst.com/category/desktop/feed/"

mkdir -p "$STATE_DIR" "$DOWNLOAD_DIR"

# ── HQPlayer Embedded ────────────────────────────────────────────────────────

# RPM Version-Release minus dist tag, e.g. "5.17.2-48"
INSTALLED_HQP=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}' hqplayerd 2>/dev/null | sed -E 's/\.fc[0-9]+$//' || true)

# Find latest x86_64 rpm from directory listing
LATEST_RPM=$(curl -sf --max-time 15 "$BINS_URL" | python3 -c "
import sys, re
from html.parser import HTMLParser

class P(HTMLParser):
    links = []
    def handle_starttag(self, tag, attrs):
        if tag == 'a':
            for k, v in attrs:
                if k == 'href' and v and v.endswith('.x86_64.rpm'):
                    self.links.append(v)

p = P(); p.feed(sys.stdin.read())

def key(f):
    m = re.search(r'(\d+)\.(\d+)\.(\d+)-(\d+)(?:\.(\d+))?\.fc', f)
    if not m:
        return (0,0,0,0,0)
    g = m.groups()
    return tuple(int(x) if x else 0 for x in g)

if p.links:
    print(sorted(p.links, key=key)[-1])
" 2>/dev/null || true)

LATEST_HQP_VER=$(echo "$LATEST_RPM" | grep -oP '\d+\.\d+\.\d+-\d+(?:\.\d+)?(?=\.fc)' || true)

HQP_UPDATE=0
HQP_SUCCESS=1

if [[ -z "$LATEST_RPM" || -z "$LATEST_HQP_VER" ]]; then
    HQP_SUCCESS=0
elif [[ "$INSTALLED_HQP" != "$LATEST_HQP_VER" ]]; then
    HQP_UPDATE=1
    RPM_PATH="$DOWNLOAD_DIR/$LATEST_RPM"
    if [[ ! -f "$RPM_PATH" ]]; then
        logger -t hqplayer-update "Downloading $LATEST_RPM..."
        curl -sf --max-time 300 -o "$RPM_PATH" "${BINS_URL}${LATEST_RPM}" \
            && logger -t hqplayer-update "Downloaded to $RPM_PATH" \
            || { logger -t hqplayer-update "Download failed"; HQP_SUCCESS=0; }
    fi
fi

# ── Distribution bump ─────────────────────────────────────────────────────────
# Detect when signalyst publishes bins for a newer Fedora than the running one.

LATEST_FC=$(curl -sf --max-time 15 "$BINS_ROOT" | grep -oP 'href="fc\K[0-9]+' | sort -n | tail -1 || true)

DISTRO_BUMP=0
DISTRO_SUCCESS=1
if [[ -z "$LATEST_FC" ]]; then
    DISTRO_SUCCESS=0
    LATEST_FC="unknown"
elif (( LATEST_FC > RUNNING_FC )); then
    DISTRO_BUMP=1
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
    echo "hqplayer_update_available{installed=\"${INSTALLED_HQP:-unknown}\",latest=\"${LATEST_HQP_VER:-unknown}\",file=\"${LATEST_RPM:-unknown}\"} $HQP_UPDATE"
    echo '# HELP hqplayer_update_check_success 1 if version check succeeded'
    echo '# TYPE hqplayer_update_check_success gauge'
    echo "hqplayer_update_check_success $HQP_SUCCESS"
    echo '# HELP hqplayer_distro_bump_available 1 if signalyst publishes hqplayerd bins for a newer Fedora than the running release'
    echo '# TYPE hqplayer_distro_bump_available gauge'
    echo "hqplayer_distro_bump_available{running=\"${RUNNING_FC}\",latest=\"${LATEST_FC}\"} $DISTRO_BUMP"
    echo '# HELP hqplayer_distro_check_success 1 if the bins root listing was fetched'
    echo '# TYPE hqplayer_distro_check_success gauge'
    echo "hqplayer_distro_check_success $DISTRO_SUCCESS"
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
