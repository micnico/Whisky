#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

# Verify an unpublished graphics runtime archive without running untrusted code.
set -euo pipefail

usage() {
    print "Usage: ${0:t} --archive PATH --workdir DIR"
}

archive=""
work_dir=""

while (( $# )); do
    case "$1" in
        --archive) archive="$2"; shift 2 ;;
        --workdir) work_dir="$2"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) print -u2 "Unknown argument: $1"; usage; exit 2 ;;
    esac
done

if [[ -z "$archive" || -z "$work_dir" || ! -f "$archive" || -e "$work_dir" ]]; then
    print -u2 -- "--archive must exist and --workdir must not exist."
    usage
    exit 2
fi

for command in cmp codesign file find grep openssl plutil sort tar xargs; do
    command -v "$command" >/dev/null || {
        print -u2 "Missing required command: $command"
        exit 1
    }
done

is_safe_archive_path() {
    [[ -n "$1" && "$1" != /* ]] || return 1
    local component
    for component in ${(s:/:)1}; do
        [[ "$component" != . && "$component" != .. ]] || return 1
    done
}

while IFS= read -r entry; do
    is_safe_archive_path "$entry" || {
        print -u2 "Unsafe archive path: $entry"
        exit 1
    }
done < <(LC_ALL=C tar -tzf "$archive")

mkdir -p "$work_dir"
LC_ALL=C tar -C "$work_dir" -xzf "$archive"

libraries="$work_dir/Libraries"
wine="$libraries/Wine/bin/wine64"
dxvk_x64="$libraries/DXVK/x64"
dxvk_x32="$libraries/DXVK/x32"
vulkan="$libraries/Vulkan"
hashes="$libraries/WhiskyWineBinaries.sha256"

for file in \
    "$libraries/WhiskyWineVersion.plist" \
    "$libraries/WhiskyWineProvenance.plist" \
    "$hashes" \
    "$wine" \
    "$dxvk_x64/d3d11.dll" \
    "$dxvk_x64/dxgi.dll" \
    "$dxvk_x32/d3d11.dll" \
    "$dxvk_x32/dxgi.dll" \
    "$vulkan/MoltenVK_icd.json" \
    "$vulkan/libMoltenVK.dylib" \
    "$vulkan/libvulkan.1.dylib"; do
    [[ -f "$file" || -L "$file" ]] || {
        print -u2 "Missing required runtime file: $file"
        exit 1
    }
done

plutil -lint "$libraries/WhiskyWineVersion.plist" "$libraries/WhiskyWineProvenance.plist"
file -L "$wine" | grep -q arm64
file "$dxvk_x64/d3d11.dll" | grep -q PE32+
file "$dxvk_x32/d3d11.dll" | grep -q 'PE32 executable'
file "$vulkan/libMoltenVK.dylib" | grep -q arm64
codesign -v "$vulkan/libMoltenVK.dylib" "$vulkan/libvulkan.1.dylib"

runtime_root="${libraries:A}"
while IFS= read -r -d '' link; do
    [[ "${link:A}" == "$runtime_root"/* ]] || {
        print -u2 "Runtime symlink escapes Libraries: $link"
        exit 1
    }
done < <(find "$libraries" -type l -print0)

(cd "$work_dir" && find Libraries -type f ! -name WhiskyWineBinaries.sha256 -print0 | \
    sort -z | xargs -0 openssl dgst -sha256 | sort) > "$work_dir/actual.sha256"
sort "$hashes" > "$work_dir/expected.sha256"
cmp "$work_dir/expected.sha256" "$work_dir/actual.sha256"

print "Verified $archive"
