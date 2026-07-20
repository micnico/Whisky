#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

# Add runtime-only dependencies to an existing candidate without rebuilding Wine.
set -euo pipefail

usage() {
    print "Usage: ${0:t} --archive PATH --workdir DIR --output DIR --architecture ARCH"
}

archive=""
work_dir=""
output_dir=""
architecture=""

while (( $# )); do
    case "$1" in
        --archive) archive="$2"; shift 2 ;;
        --workdir) work_dir="$2"; shift 2 ;;
        --output) output_dir="$2"; shift 2 ;;
        --architecture) architecture="$2"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) print -u2 "Unknown argument: $1"; usage; exit 2 ;;
    esac
done

if [[ ! -f "$archive" || ! -f "$archive.sha256" || -e "$work_dir" || -z "$output_dir" ]]; then
    print -u2 -- "--archive and its checksum must exist, --workdir must not exist, and --output is required."
    usage
    exit 2
fi
if [[ "$architecture" != "arm64" && "$architecture" != "x86_64" ]]; then
    print -u2 -- "--architecture must be arm64 or x86_64."
    exit 2
fi

expected="$(awk '{print $1}' "$archive.sha256")"
actual="$(openssl dgst -sha256 "$archive" | awk '{print $NF}')"
[[ "$expected" == "$actual" ]] || {
    print -u2 'Source archive checksum mismatch.'
    exit 1
}

while IFS= read -r entry; do
    [[ -n "$entry" && "$entry" != /* && "/$entry/" != *'/../'* && "/$entry/" != *'/./'* ]] || {
        print -u2 "Unsafe archive path: $entry"
        exit 1
    }
done < <(LC_ALL=C tar -tzf "$archive")

mkdir -p "$work_dir" "$output_dir"
LC_ALL=C tar -C "$work_dir" -xzf "$archive"

libraries="$work_dir/Libraries"
wine_lib="$libraries/Wine/lib"
provenance="$libraries/WhiskyWineProvenance.plist"
sdl2="$wine_lib/libSDL2-2.0.0.dylib"
sdl3_source="$(brew --prefix sdl3)/lib/libSDL3.dylib"
sdl3="$wine_lib/libSDL3.dylib"

for file in "$provenance" "$sdl2" "$sdl3_source"; do
    [[ -f "$file" ]] || {
        print -u2 "Missing repackage input: $file"
        exit 1
    }
done
strings "$sdl2" | grep -F 'libSDL3.dylib' >/dev/null || {
    print -u2 'Bundled SDL2 does not use the SDL3 compatibility runtime.'
    exit 1
}

cp -L "$sdl3_source" "$sdl3"
install_name_tool -id '@loader_path/libSDL3.dylib' "$sdl3"
otool -L "$sdl3" | grep -Eq '/(usr/local|opt/homebrew)/' && {
    print -u2 'SDL3 still references the Homebrew installation.'
    exit 1
}
file "$sdl3" | grep -q "$architecture"
codesign --force --sign - "$sdl3"

/usr/libexec/PlistBuddy -c 'Delete :sdl3Version' "$provenance" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Delete :sdl3License' "$provenance" 2>/dev/null || true
/usr/libexec/PlistBuddy \
    -c "Add :sdl3Version string $(brew info --json=v2 sdl3 | plutil -extract formulae.0.versions.stable raw -)" \
    -c 'Add :sdl3License string Zlib' \
    "$provenance"

(cd "$work_dir" && find Libraries -type f ! -name WhiskyWineBinaries.sha256 -print0 | \
    sort -z | xargs -0 openssl dgst -sha256 -r | sed -E 's/^([0-9a-f]+) \*?(.*)$/\1 \2/') \
    > "$libraries/WhiskyWineBinaries.sha256"

output_archive="$output_dir/${archive:t}"
tar -C "$work_dir" -czf "$output_archive" Libraries
output_checksum="$(openssl dgst -sha256 "$output_archive" | awk '{print $NF}')"
print "$output_checksum  ${output_archive:t}" > "$output_archive.sha256"

"${0:A:h}/verify-graphics-runtime.sh" \
    --archive "$output_archive" \
    --workdir "$work_dir.verify" \
    --architecture "$architecture"

print "Repackaged $output_archive"
