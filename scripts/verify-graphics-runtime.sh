#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

# Verify an unpublished graphics runtime archive without running untrusted code.
set -euo pipefail

usage() {
    print "Usage: ${0:t} --archive PATH --workdir DIR [--architecture ARCH] [--require-developer-id]"
}

archive=""
work_dir=""
require_developer_id=false
architecture="arm64"

while (( $# )); do
    case "$1" in
        --archive) archive="$2"; shift 2 ;;
        --workdir) work_dir="$2"; shift 2 ;;
        --architecture) architecture="$2"; shift 2 ;;
        --require-developer-id) require_developer_id=true; shift ;;
        --help) usage; exit 0 ;;
        *) print -u2 "Unknown argument: $1"; usage; exit 2 ;;
    esac
done

if [[ "$architecture" != "arm64" && "$architecture" != "x86_64" ]]; then
    print -u2 -- "--architecture must be arm64 or x86_64."
    exit 2
fi

if [[ -z "$archive" || -z "$work_dir" || ! -f "$archive" || -e "$work_dir" ]]; then
    print -u2 -- "--archive must exist and --workdir must not exist."
    usage
    exit 2
fi

for command in cmp codesign file find grep openssl otool plutil sort strings tar xargs; do
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

normalize_hashes() {
    sed -E \
        -e 's/^SHA(2-)?256\((.*)\)= ([0-9a-f]+)$/\3 \2/' \
        -e 's/^([0-9a-f]+) \*?(.*)$/\1 \2/' | \
        LC_ALL=C sort
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
wine_lib="$libraries/Wine/lib"
dxvk_x64="$libraries/DXVK/x64"
dxvk_x32="$libraries/DXVK/x32"
vulkan="$libraries/Vulkan"
hashes="$libraries/WhiskyWineBinaries.sha256"

for file in \
    "$libraries/WhiskyWineVersion.plist" \
    "$libraries/WhiskyWineProvenance.plist" \
    "$hashes" \
    "$wine" \
    "$wine_lib/libfreetype.6.dylib" \
    "$wine_lib/libgnutls.30.dylib" \
    "$wine_lib/libSDL2-2.0.0.dylib" \
    "$wine_lib/libSDL3.dylib" \
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
[[ "$(plutil -extract architecture raw "$libraries/WhiskyWineProvenance.plist")" == "$architecture" ]] || {
    print -u2 -- "Runtime provenance architecture does not match $architecture"
    exit 1
}
file -L "$wine" | grep -q "$architecture"
for library in \
    "$wine_lib/libfreetype.6.dylib" \
    "$wine_lib/libgnutls.30.dylib" \
    "$wine_lib/libSDL2-2.0.0.dylib" \
    "$wine_lib/libSDL3.dylib"; do
    file "$library" | grep -q "$architecture"
done
file "$dxvk_x64/d3d11.dll" | grep -q PE32+
file "$dxvk_x64/dxgi.dll" | grep -q PE32+
file "$dxvk_x32/d3d11.dll" | grep -q 'PE32 executable'
file "$dxvk_x32/dxgi.dll" | grep -q 'PE32 executable'
file "$vulkan/libMoltenVK.dylib" | grep -q "$architecture"
file "$vulkan/libvulkan.1.dylib" | grep -q "$architecture"
codesign -v "$vulkan/libMoltenVK.dylib" "$vulkan/libvulkan.1.dylib"

icd_library_path="$(plutil -extract ICD.library_path raw "$vulkan/MoltenVK_icd.json")"
[[ -n "$icd_library_path" && "$icd_library_path" != /* ]] || {
    print -u2 'MoltenVK ICD must use a relative library_path.'
    exit 1
}
icd_library="$vulkan/$icd_library_path"
[[ "${icd_library:A}" == "${vulkan:A}/libMoltenVK.dylib" ]] || {
    print -u2 "MoltenVK ICD resolves outside the bundled driver: $icd_library_path"
    exit 1
}

contains_loader_name() {
    find "$wine_lib/wine" -type f -name '*.so' -exec strings {} + | grep -Fx "$1" >/dev/null
}

contains_loader_name '@loader_path/../../libfreetype.6.dylib' || {
    print -u2 'Wine modules do not resolve FreeType from the bundled runtime path.'
    exit 1
}
contains_loader_name '@loader_path/../../libgnutls.30.dylib' || {
    print -u2 'Wine modules do not resolve GnuTLS from the bundled runtime path.'
    exit 1
}
win32u_module="$(find "$wine_lib/wine" -type f -path '*-unix/win32u.so' -print -quit)"
[[ -n "$win32u_module" ]] || {
    print -u2 'Wine win32u Unix module is missing.'
    exit 1
}
strings "$win32u_module" | grep -Fx '@loader_path/../../../../Vulkan/libvulkan.1.dylib' >/dev/null || {
    print -u2 'Wine win32u does not resolve Vulkan from the bundled runtime path.'
    exit 1
}
while IFS= read -r -d '' native_binary; do
    /usr/bin/file -b "$native_binary" | grep -q 'Mach-O' || continue
    codesign -v "$native_binary"
    if $require_developer_id; then
        codesign -dvv "$native_binary" 2>&1 | grep -q '^Authority=Developer ID Application:' || {
            print -u2 "Mach-O is not signed by Developer ID: $native_binary"
            exit 1
        }
    fi
done < <(find "$libraries" -type f -print0)

while IFS= read -r -d '' library; do
    otool -L "$library" | grep -Eq '/(usr/local|opt/homebrew)/' && {
        print -u2 "Bundled runtime library still references the build host: $library"
        exit 1
    }
done < <(find "$wine_lib" "$vulkan" -type f -name '*.dylib' -print0)

runtime_root="${libraries:A}"
while IFS= read -r -d '' link; do
    [[ "${link:A}" == "$runtime_root"/* ]] || {
        print -u2 "Runtime symlink escapes Libraries: $link"
        exit 1
    }
done < <(find "$libraries" -type l -print0)

(cd "$work_dir" && find Libraries -type f ! -name WhiskyWineBinaries.sha256 -print0 | \
    sort -z | xargs -0 openssl dgst -sha256 -r) | normalize_hashes > "$work_dir/actual.sha256"
normalize_hashes < "$hashes" > "$work_dir/expected.sha256"
cmp "$work_dir/expected.sha256" "$work_dir/actual.sha256"

print "Verified $archive"
