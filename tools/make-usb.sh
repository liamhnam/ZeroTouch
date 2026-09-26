#!/bin/bash
# Build a ZeroTouch USB drive on macOS (same result as tools/make-usb.ps1 on Windows).
#
#   tools/make-usb.sh <windows.iso> <disk identifier, e.g. disk2>    THE WHOLE USB DRIVE IS ERASED
#   tools/make-usb.sh <windows.iso> --stage <folder>                 only build the USB contents into <folder>
#
# USB layout (FAT32, MBR - boots on any UEFI firmware):
#   <ISO contents>            without install.* and the ISO's own autounattend.xml
#   sources/install*.swm      install.esd exported to WIM (faster to apply), split under 4 GiB
#   autounattend.xml          dist/autounattend.xml
#   AutoInstaller/            payload/AutoInstaller (postinstall.ps1, steps)
#   AutoInstaller/apps/       apps/<name> (folders that contain install.ps1)
#   AutoInstaller/sdio/       drivers/sdio (only if SDIO is present)
#   AutoInstaller/wifi/       Wi-Fi profile generated from secrets.env
#   AutoInstaller/peripherals/ peripherals (tool to pick and install printers, scanners, readers)
#   $WinPEDriver$/            drivers/inject (drivers added to Windows during setup, if any .inf)
#
# Requires wimlib for the ESD -> WIM conversion: brew install wimlib
# The converted image is cached in ~/Library/Caches/ZeroTouch, so only the first run is slow.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="ZEROTOUCH"
FAT32_LIMIT=$((4 * 1024 * 1024 * 1024 - 1))
SWM_SIZE_MB=3800

die() { echo "Error: $*" >&2; exit 1; }

[ $# -ge 2 ] || { sed -n '2,19p' "$0"; exit 1; }
ISO="$1"
STAGE=""
DISK=""
if [ "$2" = "--stage" ]; then
    [ $# -eq 3 ] || die "Usage: $0 <windows.iso> --stage <folder>"
    STAGE="$3"
else
    DISK="${2#/dev/}"
    [[ "$DISK" =~ ^disk[0-9]+$ ]] || die "Expected a whole disk identifier like disk2, got: $DISK"
fi

[ -f "$ISO" ] || die "ISO not found: $ISO"
[ -f "$ROOT/dist/autounattend.xml" ] || die "dist/autounattend.xml is missing - run: python3 build.py"

# --- Safety: only ever touch an external USB disk ---
if [ -n "$DISK" ]; then
    info="$(diskutil info "$DISK")" || die "No such disk: $DISK"
    field() { echo "$info" | awk -F': *' -v k="$1" '$1 ~ "^ *"k"$" {print $2; exit}'; }
    [ "$(field 'Device Location')" = "External" ] || die "$DISK is not an external disk"
    [ "$(field 'Protocol')" = "USB" ] || die "$DISK is not a USB disk"
    [ "$(field 'Part of Whole')" = "$DISK" ] || die "$DISK is not a whole disk"
    size_bytes="$(echo "$info" | sed -n 's/.*Disk Size:.*(\([0-9]*\) Bytes).*/\1/p')"
    [ -n "$size_bytes" ] || die "Could not read the size of $DISK"
    [ "$size_bytes" -le $((256 * 1000 * 1000 * 1000)) ] || die "$DISK is larger than 256 GB - refusing, is this really a USB stick?"
fi

# --- Mount the ISO ---
iso_mount="$(hdiutil attach -readonly -nobrowse "$ISO" | awk -F'\t' 'END {print $NF}')"
trap 'hdiutil detach "$iso_mount" >/dev/null 2>&1 || true' EXIT

# --- Windows image: ESD -> WIM (cached), split into SWM when over the FAT32 limit ---
iso_size=$(stat -f %z "$ISO"); iso_mtime=$(stat -f %m "$ISO")
cache="$HOME/Library/Caches/ZeroTouch/$(basename "$ISO" .iso)-$iso_size-$iso_mtime"
mkdir -p "$cache"
image_files=()
if ls "$iso_mount"/sources/install*.swm >/dev/null 2>&1; then
    image_files=("$iso_mount"/sources/install*.swm)
else
    wim="$cache/install.wim"
    if [ -f "$iso_mount/sources/install.esd" ]; then
        if [ ! -f "$wim" ]; then
            command -v wimlib-imagex >/dev/null || die "wimlib is required: brew install wimlib"
            echo "Converting install.esd to install.wim (first run only, takes a while)..."
            wimlib-imagex export "$iso_mount/sources/install.esd" 1 "$wim.tmp" --compress=maximum
            mv "$wim.tmp" "$wim"
        fi
    else
        wim="$iso_mount/sources/install.wim"
        [ -f "$wim" ] || die "The ISO has no sources/install.wim, install.esd or install.swm"
    fi
    if [ "$(stat -f %z "$wim")" -le "$FAT32_LIMIT" ]; then
        image_files=("$wim")
    else
        swm_dir="$cache/swm"
        if [ ! -f "$swm_dir/install.swm" ]; then
            command -v wimlib-imagex >/dev/null || die "wimlib is required: brew install wimlib"
            echo "Splitting install.wim for FAT32..."
            rm -rf "$swm_dir"; mkdir -p "$swm_dir"
            wimlib-imagex split "$wim" "$swm_dir/install.swm" "$SWM_SIZE_MB"
        fi
        image_files=("$swm_dir"/install*.swm)
    fi

fi

# --- Optional parts ---
apps=()
for dir in "$ROOT"/apps/*/; do
    [ -f "$dir/install.ps1" ] && apps+=("$(basename "$dir")")
done
has_sdio=0; ls "$ROOT"/drivers/sdio/SDIO_x64_R*.exe >/dev/null 2>&1 && has_sdio=1
has_inject=0; [ -n "$(find "$ROOT/drivers/inject" -iname '*.inf' -print -quit)" ] && has_inject=1
secret() { [ -f "$ROOT/secrets.env" ] && sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$ROOT/secrets.env" | tail -1 | sed 's/[[:space:]]*$//'; }
wifi_ssid="$(secret WIFI_SSID || true)"
peripherals_cfg="$(secret PERIPHERALS || true)"

# --- FAT32 and capacity checks ---
check_paths=("$iso_mount" "${image_files[@]}" "$ROOT/apps" "$ROOT/peripherals")
[ $has_sdio = 1 ] && check_paths+=("$ROOT/drivers/sdio")
big="$(find "${check_paths[@]}" -type f -size +"$FAT32_LIMIT"c ! -name 'install.esd' ! -name 'install.wim' 2>/dev/null || true)"
for file in "${image_files[@]}"; do
    [ "$(stat -f %z "$file")" -le "$FAT32_LIMIT" ] || big+=$'\n'"$file"
done
[ -z "${big//[[:space:]]/}" ] || die "Files over 4 GiB cannot be stored on FAT32:"$'\n'"$big"
if [ -n "$DISK" ]; then
    need_kb=$(( $(du -sk "$iso_mount" | cut -f1) + $(du -skc "${image_files[@]}" | tail -1 | cut -f1) + 102400 ))
    [ $has_sdio = 1 ] && need_kb=$(( need_kb + $(du -sk "$ROOT/drivers/sdio" | cut -f1) ))
    need_kb=$(( need_kb + $(du -sk "$ROOT/peripherals" "$ROOT/apps" | awk '{s+=$1} END {print s}') ))
    [ $((need_kb * 1024)) -lt "$size_bytes" ] || die "Not enough space: need ~$((need_kb / 1024)) MB"
fi

# --- Confirmation / target ---
echo
echo "ISO:    $ISO"
echo "Image:  $(for f in "${image_files[@]}"; do printf '%s ' "$(basename "$f")"; done)"
echo "Apps:   ${apps[*]:-none}"
echo "SDIO:   $([ $has_sdio = 1 ] && echo yes || echo 'NO - drivers will not be installed (see drivers/sdio/README.md)')"
echo "Wi-Fi:  ${wifi_ssid:-none (secrets.env missing)}"
echo "Peripherals: ${peripherals_cfg:-auto-detect plugged USB devices}"
echo "Inject: $([ $has_inject = 1 ] && find "$ROOT/drivers/inject" -iname '*.inf' -exec dirname {} \; | xargs -n1 basename | sort -u | tr '\n' ' ' || echo none)"
if [ -n "$DISK" ]; then
    echo "USB:    /dev/$DISK - $(field 'Device / Media Name'), $((size_bytes / 1000000000)) GB"
    echo
    diskutil list "$DISK"
    echo
    read -r -p "ALL DATA on /dev/$DISK will be erased. Type '$DISK' to continue: " answer
    [ "$answer" = "$DISK" ] || die "Aborted"
    diskutil eraseDisk FAT32 "$LABEL" MBRFormat "/dev/$DISK"
    target="/Volumes/$LABEL"
    [ -d "$target" ] || die "Formatted volume not mounted at $target"
    mdutil -i off "$target" >/dev/null 2>&1 || true
    touch "$target/.metadata_never_index"
else
    echo "Stage:  $STAGE"
    mkdir -p "$STAGE"
    target="$(cd "$STAGE" && pwd)"
fi

# --- Copy ---
echo "Copying Windows setup files..."
rsync -r --exclude '/autounattend.xml' --exclude '/sources/install.esd' --exclude '/sources/install.wim' \
    --exclude '/sources/install*.swm' "$iso_mount/" "$target/"
chmod -R u+w "$target"
echo "Copying Windows image..."
for file in "${image_files[@]}"; do rsync --progress "$file" "$target/sources/"; done
cp "$ROOT/dist/autounattend.xml" "$target/autounattend.xml"
rsync -r "$ROOT/payload/" "$target/"
for app in "${apps[@]}"; do
    mkdir -p "$target/AutoInstaller/apps/$app"
    rsync -r "$ROOT/apps/$app/" "$target/AutoInstaller/apps/$app/"
done
echo "Copying peripherals..."
mkdir -p "$target/AutoInstaller/peripherals"
rsync -r --exclude '.gitignore' "$ROOT/peripherals/" "$target/AutoInstaller/peripherals/"
if [ -n "$peripherals_cfg" ]; then
    printf '%s\n' "$peripherals_cfg" > "$target/AutoInstaller/peripherals/config.txt"
fi
if [ $has_sdio = 1 ]; then
    echo "Copying SDIO..."
    mkdir -p "$target/AutoInstaller/sdio"
    rsync -r --progress --exclude '.gitignore' --exclude 'README.md' "$ROOT/drivers/sdio/" "$target/AutoInstaller/sdio/"
fi
if [ $has_inject = 1 ]; then
    mkdir -p "$target/\$WinPEDriver\$"
    rsync -r --exclude '.gitignore' --exclude 'README.md' "$ROOT/drivers/inject/" "$target/\$WinPEDriver\$/"
fi
if [ -n "$wifi_ssid" ]; then
    xml_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"; }
    ssid_xml="$(printf '%s' "$wifi_ssid" | xml_escape)"
    key_xml="$(secret WIFI_PASSWORD | xml_escape)"
    auth="$(secret WIFI_AUTH || true)"; auth="${auth:-WPA2PSK}"
    mkdir -p "$target/AutoInstaller/wifi"
    cat > "$target/AutoInstaller/wifi/$(printf '%s' "$wifi_ssid" | tr -c 'A-Za-z0-9_.-' '_').xml" <<EOF
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$ssid_xml</name>
    <SSIDConfig>
        <SSID><name>$ssid_xml</name></SSID>
        <nonBroadcast>false</nonBroadcast>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>$auth</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$key_xml</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
EOF
fi

dot_clean -m "$target" 2>/dev/null || true
find "$target" -name '._*' -delete 2>/dev/null || true
find "$target" -name '.DS_Store' -delete 2>/dev/null || true
sync
echo
if [ -n "$DISK" ]; then
    echo "Done. USB '$LABEL' is ready - boot the target machine from it in UEFI mode."
else
    echo "Done. USB contents staged in $target"
fi
