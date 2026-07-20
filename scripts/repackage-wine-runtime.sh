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
if [[ "$(uname -m)" != "$architecture" ]]; then
    print -u2 -- "Repackage on a host matching --architecture."
    exit 1
fi
for command in brew codesign file find install_name_tool openssl otool plutil strings tar; do
    command -v "$command" >/dev/null || {
        print -u2 "Missing required command: $command"
        exit 1
    }
done

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
brew_prefix="$(brew --prefix)"

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

typeset -A bundled_libraries
bundle_homebrew_library() {
    local source="${1:A}" destination dependency
    [[ "$source" == "$brew_prefix/"* ]] || return 0
    destination="$wine_lib/${source:t}"
    bundled_libraries[$destination]=1
    [[ -f "$destination" ]] && return 0
    cp -L "$source" "$destination"
    while IFS= read -r dependency; do
        dependency="${dependency#"${dependency%%[![:space:]]*}"}"
        dependency="${dependency%% \(*}"
        [[ "$dependency" != "$brew_prefix/"* ]] || bundle_homebrew_library "$dependency"
    done < <(otool -L "$source" | tail -n +2)
}

bundle_homebrew_library "$sdl3_source"
bundle_homebrew_library "$(brew --prefix libusb)/lib/libusb-1.0.0.dylib"
bundle_homebrew_library "$(brew --prefix libx11)/lib/libX11.6.dylib"
bundle_homebrew_library "$(brew --prefix libxext)/lib/libXext.6.dylib"

for library in ${(k)bundled_libraries}; do
    file "$library" | grep -q "$architecture"
    install_name_tool -id "@loader_path/${library:t}" "$library"
    while IFS= read -r dependency; do
        dependency="${dependency#"${dependency%%[![:space:]]*}"}"
        dependency="${dependency%% \(*}"
        if [[ "$dependency" == "$brew_prefix/"* ]]; then
            [[ -f "$wine_lib/${dependency:t}" ]] || {
                print -u2 "Missing bundled dependency for $library: $dependency"
                exit 1
            }
            install_name_tool -change "$dependency" "@loader_path/${dependency:t}" "$library"
        fi
    done < <(otool -L "$library" | tail -n +2)
    codesign --force --sign - "$library"
done

while IFS= read -r -d '' module; do
    modified=false
    while IFS= read -r dependency; do
        dependency="${dependency#"${dependency%%[![:space:]]*}"}"
        dependency="${dependency%% \(*}"
        if [[ "$dependency" == "$brew_prefix/"* ]]; then
            [[ -f "$wine_lib/${dependency:t}" ]] || {
                print -u2 "Missing bundled dependency for $module: $dependency"
                exit 1
            }
            install_name_tool -change "$dependency" "@loader_path/../../${dependency:t}" "$module"
            modified=true
        fi
    done < <(otool -L "$module" | tail -n +2)
    $modified && codesign --force --sign - "$module"
done < <(find "$wine_lib/wine" -type f -name '*.so' -print0)

/usr/libexec/PlistBuddy -c 'Delete :sdl3Version' "$provenance" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Delete :sdl3License' "$provenance" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Delete :libusbVersion' "$provenance" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Delete :libusbLicense' "$provenance" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Delete :libX11Version' "$provenance" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Delete :libX11License' "$provenance" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Delete :libXextVersion' "$provenance" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Delete :libXextLicense' "$provenance" 2>/dev/null || true
/usr/libexec/PlistBuddy \
    -c "Add :sdl3Version string $(brew info --json=v2 sdl3 | plutil -extract formulae.0.versions.stable raw -)" \
    -c 'Add :sdl3License string Zlib' \
    -c "Add :libusbVersion string $(brew info --json=v2 libusb | plutil -extract formulae.0.versions.stable raw -)" \
    -c 'Add :libusbLicense string LGPL-2.1-or-later' \
    -c "Add :libX11Version string $(brew info --json=v2 libx11 | plutil -extract formulae.0.versions.stable raw -)" \
    -c 'Add :libX11License string MIT' \
    -c "Add :libXextVersion string $(brew info --json=v2 libxext | plutil -extract formulae.0.versions.stable raw -)" \
    -c 'Add :libXextLicense string MIT' \
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
