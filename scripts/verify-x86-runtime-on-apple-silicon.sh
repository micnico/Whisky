#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

# Run the x86_64 Wine runtime smoke test through Rosetta without touching a Bottle.
set -euo pipefail

readonly SCRIPT_NAME="${0:t}"

usage() {
    print "Usage: $SCRIPT_NAME --archive PATH --workdir DIR"
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

if [[ "$(uname -m)" != "arm64" || -z "$archive" || -z "$work_dir" || ! -f "$archive" || -e "$work_dir" ]]; then
    print -u2 -- "Run on Apple silicon with an existing archive and a new work directory."
    usage
    exit 2
fi

for command in arch i686-w64-mingw32-gcc plutil tar; do
    command -v "$command" >/dev/null || {
        print -u2 "Missing required command: $command"
        exit 1
    }
done

arch -x86_64 /usr/bin/true

script_dir="${0:A:h}"
verify_dir="$work_dir/verify"
smoke_dir="$work_dir/smoke"
"$script_dir/verify-graphics-runtime.sh" \
    --archive "$archive" \
    --workdir "$verify_dir" \
    --architecture x86_64

mkdir -p "$smoke_dir"
tar -C "$smoke_dir" -xzf "$archive"
wine="$smoke_dir/Libraries/Wine/bin/wine64"
wine_tag="$(plutil -extract wineTag raw "$smoke_dir/Libraries/WhiskyWineProvenance.plist")"
test "$(arch -x86_64 "$wine" --version)" = "$wine_tag"
i686-w64-mingw32-gcc "$script_dir/fixtures/smoke-win32.c" -o "$smoke_dir/smoke-win32.exe"
export WINEPREFIX="$smoke_dir/prefix"
export VK_ICD_FILENAMES="$smoke_dir/Libraries/Vulkan/MoltenVK_icd.json"
export DYLD_FALLBACK_LIBRARY_PATH="$smoke_dir/Libraries/Vulkan:$smoke_dir/Libraries/Wine/lib${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
arch -x86_64 "$wine" wineboot -u
arch -x86_64 "$wine" "$smoke_dir/smoke-win32.exe"

print "Rosetta smoke test passed for $archive"
