#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

# Produce a Whisky runtime from official Wine, DXVK, and MoltenVK tags.
set -euo pipefail

readonly WINE_SOURCE=https://gitlab.winehq.org/wine/wine.git
readonly DXVK_SOURCE=https://github.com/doitsujin/dxvk.git
readonly MOLTENVK_SOURCE=https://github.com/KhronosGroup/MoltenVK.git
readonly SCRIPT_NAME="${0:t}"

usage() {
    print "Usage: $SCRIPT_NAME --wine-tag wine-X.Y --archive-url URL [options]"
    print ""
    print "Options:"
    print "  --output DIR       Output directory (default: ./build/runtime)"
    print "  --workdir DIR      Temporary build directory (default: /tmp/whisky-wine-X.Y)"
    print "  --runtime-id ID    Runtime identifier (default: wine-X.Y-ARCH)"
    print "  --architecture ARCH Build architecture: arm64 or x86_64 (default: arm64)"
    print "  --wine-revision SHA Verify the checked-out Wine revision"
    print "  --dxvk-tag TAG     Build DXVK from source (requires --moltenvk-tag)"
    print "  --dxvk-revision SHA Verify the checked-out DXVK revision"
    print "  --moltenvk-tag TAG Build MoltenVK from source (requires --dxvk-tag)"
    print "  --moltenvk-revision SHA Verify the checked-out MoltenVK revision"
    print "  --code-sign-identity ID Sign Mach-O runtime files with this identity"
    print "  --jobs N           Parallel make jobs (default: 4)"
}

wine_tag=""
wine_revision=""
archive_url=""
output_dir="$PWD/build/runtime"
work_dir=""
runtime_id=""
architecture="arm64"
dxvk_tag=""
dxvk_revision=""
moltenvk_tag=""
moltenvk_revision=""
code_sign_identity="-"
jobs=4

while (( $# )); do
    case "$1" in
        --wine-tag) wine_tag="$2"; shift 2 ;;
        --wine-revision) wine_revision="$2"; shift 2 ;;
        --archive-url) archive_url="$2"; shift 2 ;;
        --output) output_dir="$2"; shift 2 ;;
        --workdir) work_dir="$2"; shift 2 ;;
        --runtime-id) runtime_id="$2"; shift 2 ;;
        --architecture) architecture="$2"; shift 2 ;;
        --dxvk-tag) dxvk_tag="$2"; shift 2 ;;
        --dxvk-revision) dxvk_revision="$2"; shift 2 ;;
        --moltenvk-tag) moltenvk_tag="$2"; shift 2 ;;
        --moltenvk-revision) moltenvk_revision="$2"; shift 2 ;;
        --code-sign-identity) code_sign_identity="$2"; shift 2 ;;
        --jobs) jobs="$2"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) print -u2 "Unknown argument: $1"; usage; exit 2 ;;
    esac
done

if [[ ! "$wine_tag" =~ '^wine-[0-9]+\.[0-9]+$' || "$archive_url" != https://* ]]; then
    print -u2 -- "--wine-tag must name a stable Wine tag and --archive-url must use HTTPS."
    usage
    exit 2
fi
if [[ ! "$jobs" =~ '^[1-9][0-9]*$' ]]; then
    print -u2 -- "--jobs must be a positive integer."
    exit 2
fi
if [[ "$architecture" != "arm64" && "$architecture" != "x86_64" ]]; then
    print -u2 -- "--architecture must be arm64 or x86_64."
    exit 2
fi
if [[ "$(uname -m)" != "$architecture" ]]; then
    print -u2 -- "Build this runtime with: arch -$architecture $SCRIPT_NAME ..."
    exit 1
fi
for revision in "$wine_revision" "$dxvk_revision" "$moltenvk_revision"; do
    [[ -z "$revision" || "$revision" =~ '^[0-9a-f]{40}$' ]] || {
        print -u2 -- "Expected revisions must be 40 lowercase hexadecimal characters."
        exit 2
    }
done

graphics_runtime=false
if [[ -n "$dxvk_tag" || -n "$moltenvk_tag" ]]; then
    if [[ -z "$dxvk_tag" || -z "$moltenvk_tag" ]]; then
        print -u2 -- "--dxvk-tag and --moltenvk-tag must be provided together."
        exit 2
    fi
    if [[ ! "$dxvk_tag" =~ '^v[0-9]+\.[0-9]+(\.[0-9]+)?$' ||
          ! "$moltenvk_tag" =~ '^v[0-9]+\.[0-9]+(\.[0-9]+)?$' ]]; then
        print -u2 -- "--dxvk-tag and --moltenvk-tag must name stable vX.Y or vX.Y.Z tags."
        exit 2
    fi
    graphics_runtime=true
fi

version="${wine_tag#wine-}"
runtime_id="${runtime_id:-wine-${version}-${architecture}}"
work_dir="${work_dir:-${TMPDIR:-/tmp}/whisky-${runtime_id}}"
if [[ ! "$runtime_id" =~ '^[A-Za-z0-9._-]+$' ]]; then
    print -u2 -- "--runtime-id may contain only letters, digits, '.', '-', and '_'."
    exit 2
fi

for command in brew git make openssl tar; do
    command -v "$command" >/dev/null || {
        print -u2 "Missing required command: $command"
        exit 1
    }
done
if [[ "$code_sign_identity" != "-" ]]; then
    for command in codesign file; do
        command -v "$command" >/dev/null || {
            print -u2 "Missing required command for runtime signing: $command"
            exit 1
        }
    done
fi

bison_prefix="$(brew --prefix bison)"
llvm_prefix="$(brew --prefix llvm)"
lld_prefix="$(brew --prefix lld)"
export PATH="$llvm_prefix/bin:$lld_prefix/bin:$bison_prefix/bin:$PATH"

if $graphics_runtime; then
    for command in meson ninja cmake xcodebuild install_name_tool codesign; do
        command -v "$command" >/dev/null || {
            print -u2 "Missing required command for graphics runtime: $command"
            exit 1
        }
    done
    vulkan_headers_prefix="$(brew --prefix vulkan-headers)"
    vulkan_loader_prefix="$(brew --prefix vulkan-loader)"
fi

source_dir="$work_dir/source"
build_dir="$work_dir/build"
stage_dir="$work_dir/stage"
runtime_dir="$work_dir/runtime"
dxvk_source_dir="$work_dir/dxvk"
dxvk_output_dir="$work_dir/dxvk-output"
moltenvk_source_dir="$work_dir/moltenvk"
archive="$output_dir/${runtime_id}.tar.gz"
manifest="$output_dir/WhiskyWineVersion.plist"

report_failure() {
    local exit_code=$?
    for log in "$work_dir"/*.log(N); do
        print -u2 -- "\nLast 200 lines of $log:"
        tail -n 200 "$log" >&2
    done
    exit "$exit_code"
}
trap report_failure ERR

if [[ -e "$work_dir" ]]; then
    print -u2 "Work directory already exists: $work_dir"
    exit 1
fi
mkdir -p "$work_dir" "$output_dir"
for artifact in "$archive" "$archive.sha256" "$manifest"; do
    if [[ -e "$artifact" ]]; then
        print -u2 "Refusing to overwrite existing release artifact: $artifact"
        exit 1
    fi
done
print "Cloning Wine $wine_tag"
git clone --quiet --depth 1 --branch "$wine_tag" "$WINE_SOURCE" "$source_dir"
if $graphics_runtime; then
    print "Cloning DXVK $dxvk_tag and MoltenVK $moltenvk_tag"
    git clone --quiet --depth 1 --branch "$dxvk_tag" --recursive "$DXVK_SOURCE" "$dxvk_source_dir"
    git clone --quiet --depth 1 --branch "$moltenvk_tag" "$MOLTENVK_SOURCE" "$moltenvk_source_dir"
fi

verify_revision() {
    local source="$1" expected="$2" actual
    actual="$(git -C "$source" rev-parse HEAD)"
    [[ -z "$expected" || "$actual" == "$expected" ]] || {
        print -u2 -- "Revision mismatch for $source: expected $expected, got $actual"
        exit 1
    }
}
verify_revision "$source_dir" "$wine_revision"
if $graphics_runtime; then
    verify_revision "$dxvk_source_dir" "$dxvk_revision"
    verify_revision "$moltenvk_source_dir" "$moltenvk_revision"
fi

mkdir "$build_dir" "$stage_dir" "$runtime_dir"
wine_configure_args=()
if [[ "$architecture" == "x86_64" ]]; then
    wine_configure_args=(--build=x86_64-apple-darwin --enable-archs=i386,x86_64)
fi
if $graphics_runtime; then
    print "Configuring Wine for $architecture"
    (
        cd "$build_dir"
        PKG_CONFIG_PATH="$vulkan_loader_prefix/lib/pkgconfig:$vulkan_headers_prefix/share/pkgconfig" \
        CPPFLAGS="-I$vulkan_headers_prefix/include" \
        LDFLAGS="-L$vulkan_loader_prefix/lib" \
        "$source_dir/configure" "${wine_configure_args[@]}"
    ) > "$work_dir/configure.log" 2>&1
else
    print "Configuring Wine for $architecture"
    (
        cd "$build_dir"
        "$source_dir/configure" "${wine_configure_args[@]}"
    ) > "$work_dir/configure.log" 2>&1
fi
print "Building Wine"
make -C "$build_dir" -j"$jobs" > "$work_dir/build.log" 2>&1
print "Installing Wine"
make -C "$build_dir" install DESTDIR="$stage_dir" > "$work_dir/install.log" 2>&1

mkdir -p "$runtime_dir/Libraries"
mv "$stage_dir/usr/local" "$runtime_dir/Libraries/Wine"
ln -s wine "$runtime_dir/Libraries/Wine/bin/wine64"

if $graphics_runtime; then
    print "Building MoltenVK"
    (
        cd "$moltenvk_source_dir"
        ./fetchDependencies --macos
        make macos
    ) > "$work_dir/moltenvk.log" 2>&1

    print "Building DXVK"
    mkdir "$dxvk_output_dir"
    meson setup "$work_dir/dxvk-x64" "$dxvk_source_dir" --cross-file "$dxvk_source_dir/build-win64.txt" \
        --buildtype release --prefix "$dxvk_output_dir/x64" > "$work_dir/dxvk-x64.log" 2>&1
    ninja -C "$work_dir/dxvk-x64" install >> "$work_dir/dxvk-x64.log" 2>&1
    meson setup "$work_dir/dxvk-x32" "$dxvk_source_dir" --cross-file "$dxvk_source_dir/build-win32.txt" \
        --buildtype release --prefix "$dxvk_output_dir/x32" > "$work_dir/dxvk-x32.log" 2>&1
    ninja -C "$work_dir/dxvk-x32" install >> "$work_dir/dxvk-x32.log" 2>&1

    mkdir -p "$runtime_dir/Libraries/DXVK/x64" "$runtime_dir/Libraries/DXVK/x32" "$runtime_dir/Libraries/Vulkan"
    cp "$dxvk_output_dir/x64/bin/"*.dll "$runtime_dir/Libraries/DXVK/x64/"
    cp "$dxvk_output_dir/x32/bin/"*.dll "$runtime_dir/Libraries/DXVK/x32/"
    cp -L "$vulkan_loader_prefix/lib/libvulkan.1.dylib" "$runtime_dir/Libraries/Vulkan/libvulkan.1.dylib"
    install_name_tool -id @rpath/libvulkan.1.dylib "$runtime_dir/Libraries/Vulkan/libvulkan.1.dylib"
    cp "$moltenvk_source_dir/Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib" \
        "$runtime_dir/Libraries/Vulkan/"
    cp "$moltenvk_source_dir/Package/Release/MoltenVK/dynamic/dylib/macOS/MoltenVK_icd.json" \
        "$runtime_dir/Libraries/Vulkan/"
    codesign --force --sign - "$runtime_dir/Libraries/Vulkan/libvulkan.1.dylib" \
        "$runtime_dir/Libraries/Vulkan/libMoltenVK.dylib"
fi

if [[ "$code_sign_identity" != "-" ]]; then
    while IFS= read -r -d '' binary; do
        if /usr/bin/file -b "$binary" | grep -q 'Mach-O'; then
            codesign --force --timestamp --sign "$code_sign_identity" "$binary"
        fi
    done < <(find "$runtime_dir/Libraries" -type f -print0)
fi

IFS=. read -r major minor <<< "$version"
version_plist="$runtime_dir/Libraries/WhiskyWineVersion.plist"
provenance_plist="$runtime_dir/Libraries/WhiskyWineProvenance.plist"
plutil -create xml1 "$version_plist"
plutil -create xml1 "$provenance_plist"
/usr/libexec/PlistBuddy -c 'Add :version dict' "$version_plist"
/usr/libexec/PlistBuddy -c "Add :version:major integer $major" "$version_plist"
/usr/libexec/PlistBuddy -c "Add :version:minor integer $minor" "$version_plist"
/usr/libexec/PlistBuddy -c 'Add :version:patch integer 0' "$version_plist"
/usr/libexec/PlistBuddy -c 'Add :version:preRelease string' "$version_plist"
if $graphics_runtime; then
    /usr/libexec/PlistBuddy -c 'Add :version:build string dxvk-moltenvk' "$version_plist"
else
    /usr/libexec/PlistBuddy -c 'Add :version:build string' "$version_plist"
fi

/usr/libexec/PlistBuddy -c "Add :wineSource string $WINE_SOURCE" "$provenance_plist"
/usr/libexec/PlistBuddy -c "Add :wineTag string $wine_tag" "$provenance_plist"
/usr/libexec/PlistBuddy -c "Add :wineRevision string $(git -C "$source_dir" rev-parse HEAD)" "$provenance_plist"
/usr/libexec/PlistBuddy -c 'Add :wineLicense string LGPL-2.1-or-later' "$provenance_plist"
/usr/libexec/PlistBuddy -c "Add :architecture string $architecture" "$provenance_plist"
if $graphics_runtime; then
    /usr/libexec/PlistBuddy -c "Add :dxvkSource string $DXVK_SOURCE" "$provenance_plist"
    /usr/libexec/PlistBuddy -c "Add :dxvkTag string $dxvk_tag" "$provenance_plist"
    /usr/libexec/PlistBuddy -c "Add :dxvkRevision string $(git -C "$dxvk_source_dir" rev-parse HEAD)" "$provenance_plist"
    /usr/libexec/PlistBuddy -c 'Add :dxvkLicense string zlib' "$provenance_plist"
    /usr/libexec/PlistBuddy -c "Add :moltenVKSource string $MOLTENVK_SOURCE" "$provenance_plist"
    /usr/libexec/PlistBuddy -c "Add :moltenVKTag string $moltenvk_tag" "$provenance_plist"
    /usr/libexec/PlistBuddy -c "Add :moltenVKRevision string $(git -C "$moltenvk_source_dir" rev-parse HEAD)" "$provenance_plist"
    /usr/libexec/PlistBuddy -c 'Add :moltenVKLicense string Apache-2.0' "$provenance_plist"
    /usr/libexec/PlistBuddy -c "Add :vulkanLoaderVersion string $(brew info --json=v2 vulkan-loader | plutil -extract formulae.0.versions.stable raw -)" "$provenance_plist"
    /usr/libexec/PlistBuddy -c 'Add :vulkanLoaderLicense string Apache-2.0' "$provenance_plist"
    (cd "$runtime_dir" && find Libraries -type f ! -name WhiskyWineBinaries.sha256 -print0 | \
        sort -z | xargs -0 openssl dgst -sha256 -r | sed -E 's/^([0-9a-f]+) \*?(.*)$/\1 \2/') \
        > "$runtime_dir/Libraries/WhiskyWineBinaries.sha256"
fi

tar -C "$runtime_dir" -czf "$archive" Libraries
checksum="$(openssl dgst -sha256 "$archive" | awk '{print $NF}')"
print "$checksum  ${archive:t}" > "$archive.sha256"

plutil -create xml1 "$manifest"
/usr/libexec/PlistBuddy -c "Add :id string $runtime_id" "$manifest"
/usr/libexec/PlistBuddy -c 'Add :version dict' "$manifest"
/usr/libexec/PlistBuddy -c "Add :version:major integer $major" "$manifest"
/usr/libexec/PlistBuddy -c "Add :version:minor integer $minor" "$manifest"
/usr/libexec/PlistBuddy -c 'Add :version:patch integer 0' "$manifest"
/usr/libexec/PlistBuddy -c 'Add :version:preRelease string' "$manifest"
if $graphics_runtime; then
    /usr/libexec/PlistBuddy -c 'Add :version:build string dxvk-moltenvk' "$manifest"
else
    /usr/libexec/PlistBuddy -c 'Add :version:build string' "$manifest"
fi
/usr/libexec/PlistBuddy -c "Add :archiveURL string $archive_url" "$manifest"
/usr/libexec/PlistBuddy -c "Add :sha256 string $checksum" "$manifest"

print "Built $archive"
print "SHA-256: $checksum"
