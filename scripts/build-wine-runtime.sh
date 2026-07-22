#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

# Produce a Whisky runtime from official Wine, DXVK-macOS, and MoltenVK tags.
set -euo pipefail

readonly WINE_SOURCE=https://gitlab.winehq.org/wine/wine.git
readonly CROSSOVER_WINE_SOURCE=https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz
readonly CROSSOVER_WINE_SOURCE_SHA256=ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872
readonly DXVK_SOURCE=https://github.com/Gcenx/DXVK-macOS.git
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
    print "  --crossover-source-archive FILE Use a verified CrossOver FOSS Wine source bundle"
    print "  --dxvk-tag TAG     Build DXVK from source (requires --moltenvk-tag)"
    print "  --dxvk-revision SHA Verify the checked-out DXVK revision"
    print "  --moltenvk-tag TAG Build MoltenVK from source (requires --dxvk-tag)"
    print "  --moltenvk-revision SHA Verify the checked-out MoltenVK revision"
    print "  --prebuilt-dxvk DIR Reuse a verified DXVK-macOS component artifact"
    print "  --code-sign-identity ID Sign Mach-O runtime files with this identity"
    print "  --jobs N           Parallel make jobs (default: 4)"
}

wine_tag=""
wine_revision=""
crossover_source_archive=""
archive_url=""
output_dir="$PWD/build/runtime"
work_dir=""
runtime_id=""
architecture="arm64"
dxvk_tag=""
dxvk_revision=""
moltenvk_tag=""
moltenvk_revision=""
prebuilt_dxvk=""
code_sign_identity="-"
jobs=4

while (( $# )); do
    case "$1" in
        --wine-tag) wine_tag="$2"; shift 2 ;;
        --wine-revision) wine_revision="$2"; shift 2 ;;
        --crossover-source-archive) crossover_source_archive="$2"; shift 2 ;;
        --archive-url) archive_url="$2"; shift 2 ;;
        --output) output_dir="$2"; shift 2 ;;
        --workdir) work_dir="$2"; shift 2 ;;
        --runtime-id) runtime_id="$2"; shift 2 ;;
        --architecture) architecture="$2"; shift 2 ;;
        --dxvk-tag) dxvk_tag="$2"; shift 2 ;;
        --dxvk-revision) dxvk_revision="$2"; shift 2 ;;
        --moltenvk-tag) moltenvk_tag="$2"; shift 2 ;;
        --moltenvk-revision) moltenvk_revision="$2"; shift 2 ;;
        --prebuilt-dxvk) prebuilt_dxvk="$2"; shift 2 ;;
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
wine_source="$WINE_SOURCE"
wine_distribution=winehq
if [[ -n "$crossover_source_archive" ]]; then
    if [[ ! -f "$crossover_source_archive" ]]; then
        print -u2 -- "--crossover-source-archive must name the pinned CrossOver 26.3 source bundle."
        exit 2
    fi
    if [[ -n "$wine_revision" ]]; then
        print -u2 -- "--wine-revision cannot be combined with a CrossOver source archive."
        exit 2
    fi
    crossover_source_archive="${crossover_source_archive:A}"
    wine_source="$CROSSOVER_WINE_SOURCE"
    wine_distribution=crossover
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
    if [[ ! "$dxvk_tag" =~ '^v[0-9]+\.[0-9]+(\.[0-9]+)?(-[A-Za-z0-9.-]+)?$' ||
          ! "$moltenvk_tag" =~ '^v[0-9]+\.[0-9]+(\.[0-9]+)?$' ]]; then
        print -u2 -- "--dxvk-tag and --moltenvk-tag must name stable vX.Y or vX.Y.Z tags."
        exit 2
    fi
    graphics_runtime=true
fi
if [[ -n "$prebuilt_dxvk" ]]; then
    [[ "$graphics_runtime" == true && -d "$prebuilt_dxvk" ]] || {
        print -u2 -- "--prebuilt-dxvk requires a graphics runtime and an existing directory."
        exit 2
    }
    prebuilt_dxvk="${prebuilt_dxvk:A}"
fi

version="${wine_tag#wine-}"
runtime_id="${runtime_id:-wine-${version}-${architecture}}"
work_dir="${work_dir:-${TMPDIR:-/tmp}/whisky-${runtime_id}}"
if [[ ! "$runtime_id" =~ '^[A-Za-z0-9._-]+$' ]]; then
    print -u2 -- "--runtime-id may contain only letters, digits, '.', '-', and '_'."
    exit 2
fi

for command in brew git make openssl tar codesign file install_name_tool otool; do
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
freetype_prefix="$(brew --prefix freetype)"
gnutls_prefix="$(brew --prefix gnutls)"
sdl2_prefix="$(brew --prefix sdl2)"
sdl3_prefix="$(brew --prefix sdl3)"
sdl2_library="$sdl2_prefix/lib/libSDL2-2.0.0.dylib"
if [[ ! -f "$sdl2_library" ]]; then
    sdl2_installed=("${(z)$(brew list --versions sdl2)}")
    (( ${#sdl2_installed} >= 2 )) || {
        print -u2 "Homebrew reports no installed SDL2 formula."
        exit 1
    }
    sdl2_library="$(brew --cellar)/${sdl2_installed[1]}/${sdl2_installed[2]}/lib/libSDL2-2.0.0.dylib"
    [[ -n "$sdl2_library" && -f "$sdl2_library" ]] || {
        print -u2 "Missing libSDL2-2.0.0.dylib after installing sdl2."
        exit 1
    }
    sdl2_prefix="${sdl2_library:h:h}"
fi
brew_prefix="$(brew --prefix)"
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
if [[ -n "$crossover_source_archive" ]]; then
    "${0:A:h}/verify-crossover-wine-source.sh" \
        --archive "$crossover_source_archive" \
        --sha256 "$CROSSOVER_WINE_SOURCE_SHA256" \
        --version "$version"
    print "Extracting CrossOver Wine $version"
    mkdir "$source_dir"
    tar -xzf "$crossover_source_archive" -C "$source_dir" --strip-components=2 sources/wine
else
    print "Cloning Wine $wine_tag"
    git clone --quiet --depth 1 --branch "$wine_tag" "$WINE_SOURCE" "$source_dir"
fi
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
if [[ -z "$crossover_source_archive" ]]; then
    verify_revision "$source_dir" "$wine_revision"
fi
if $graphics_runtime; then
    verify_revision "$dxvk_source_dir" "$dxvk_revision"
    verify_revision "$moltenvk_source_dir" "$moltenvk_revision"
fi

mkdir "$build_dir" "$stage_dir" "$runtime_dir"
wine_configure_args=()
if [[ "$architecture" == "x86_64" ]]; then
    wine_configure_args=(--build=x86_64-apple-darwin --enable-archs=i386,x86_64)
fi
wine_pkg_config_path="$freetype_prefix/lib/pkgconfig:$gnutls_prefix/lib/pkgconfig:$sdl2_prefix/lib/pkgconfig"
wine_cppflags="-I$freetype_prefix/include -I$gnutls_prefix/include -I$sdl2_prefix/include"
wine_ldflags="-L$freetype_prefix/lib -L$gnutls_prefix/lib -L$sdl2_prefix/lib"
wine_soname_cache=(
    "ac_cv_lib_soname_freetype=@loader_path/../../libfreetype.6.dylib"
    "ac_cv_lib_soname_gnutls=@loader_path/../../libgnutls.30.dylib"
)
if $graphics_runtime; then
    wine_soname_cache+=("ac_cv_lib_soname_vulkan=@loader_path/../../../../Vulkan/libvulkan.1.dylib")
    print "Configuring Wine for $architecture"
    (
        cd "$build_dir"
        env "${wine_soname_cache[@]}" \
        PKG_CONFIG_PATH="$wine_pkg_config_path:$vulkan_loader_prefix/lib/pkgconfig:$vulkan_headers_prefix/share/pkgconfig" \
        CPPFLAGS="$wine_cppflags -I$vulkan_headers_prefix/include" \
        LDFLAGS="$wine_ldflags -L$vulkan_loader_prefix/lib" \
        "$source_dir/configure" "${wine_configure_args[@]}"
    ) > "$work_dir/configure.log" 2>&1
else
    print "Configuring Wine for $architecture"
    (
        cd "$build_dir"
        env "${wine_soname_cache[@]}" \
        PKG_CONFIG_PATH="$wine_pkg_config_path" \
        CPPFLAGS="$wine_cppflags" \
        LDFLAGS="$wine_ldflags" \
        "$source_dir/configure" "${wine_configure_args[@]}"
    ) > "$work_dir/configure.log" 2>&1
fi

# MoltenVK and DXVK do not depend on Wine's compiled output. Build them before
# the long Wine make so a graphics-toolchain failure cannot waste that time.
if $graphics_runtime; then
    print "Building MoltenVK"
    (
        cd "$moltenvk_source_dir"
        ./fetchDependencies --macos
        make macos
    ) > "$work_dir/moltenvk.log" 2>&1

    if [[ -n "$prebuilt_dxvk" ]]; then
        print "Reusing verified DXVK-macOS"
        "${0:A:h}/verify-dxvk-macos-output.sh" \
            --output "$prebuilt_dxvk" \
            --revision "$dxvk_revision" \
            --tag "$dxvk_tag" > "$work_dir/dxvk.log" 2>&1
        cp -R "$prebuilt_dxvk" "$dxvk_output_dir"
    else
        print "Building DXVK-macOS"
        "${0:A:h}/build-dxvk-macos.sh" \
            --source "$dxvk_source_dir" \
            --workdir "$work_dir/dxvk-build" \
            --output "$dxvk_output_dir" > "$work_dir/dxvk.log" 2>&1
    fi
fi

print "Building Wine"
make -C "$build_dir" -j"$jobs" > "$work_dir/build.log" 2>&1
print "Installing Wine"
make -C "$build_dir" install DESTDIR="$stage_dir" > "$work_dir/install.log" 2>&1

mkdir -p "$runtime_dir/Libraries"
mv "$stage_dir/usr/local" "$runtime_dir/Libraries/Wine"
ln -s wine "$runtime_dir/Libraries/Wine/bin/wine64"

# Wine loads FreeType and GnuTLS by name at runtime. Bundle their complete
# Homebrew dependency closure so the archive does not depend on the builder.
wine_library_dir="$runtime_dir/Libraries/Wine/lib"
bundle_homebrew_library() {
    local source="$1" destination dependency
    [[ "$source" == "$brew_prefix/"* ]] || return 0
    destination="$wine_library_dir/${source:t}"
    [[ -f "$destination" ]] && return 0
    cp -L "$source" "$destination"
    while IFS= read -r dependency; do
        dependency="${dependency#"${dependency%%[![:space:]]*}"}"
        dependency="${dependency%% \(*}"
        if [[ "$dependency" == "$brew_prefix/"* ]]; then
            bundle_homebrew_library "$dependency"
        fi
    done < <(otool -L "$source" | tail -n +2)
    true
}

bundle_homebrew_library "$freetype_prefix/lib/libfreetype.6.dylib"
bundle_homebrew_library "$gnutls_prefix/lib/libgnutls.30.dylib"
bundle_homebrew_library "$(brew --prefix libusb)/lib/libusb-1.0.0.dylib"
bundle_homebrew_library "$(brew --prefix libx11)/lib/libX11.6.dylib"
bundle_homebrew_library "$(brew --prefix libxext)/lib/libXext.6.dylib"
bundle_homebrew_library "$sdl2_library"
# Homebrew's current sdl2 formula is sdl2-compat, which loads SDL3 with
# dlopen instead of a Mach-O load command. Bundle that runtime-only dependency.
bundle_homebrew_library "$sdl3_prefix/lib/libSDL3.dylib"

while IFS= read -r -d '' library; do
    install_name_tool -id "@loader_path/${library:t}" "$library"
    while IFS= read -r dependency; do
        dependency="${dependency#"${dependency%%[![:space:]]*}"}"
        dependency="${dependency%% \(*}"
        if [[ "$dependency" == "$brew_prefix/"* && -f "$wine_library_dir/${dependency:t}" ]]; then
            install_name_tool -change "$dependency" "@loader_path/${dependency:t}" "$library"
        fi
    done < <(otool -L "$library" | tail -n +2)
done < <(find "$wine_library_dir" -type f -name '*.dylib' -print0)
true

while IFS= read -r -d '' module; do
    while IFS= read -r dependency; do
        dependency="${dependency#"${dependency%%[![:space:]]*}"}"
        dependency="${dependency%% \(*}"
        if [[ "$dependency" == "$brew_prefix/"* ]]; then
            [[ -f "$wine_library_dir/${dependency:t}" ]] || {
                print -u2 "Missing bundled dependency for $module: $dependency"
                exit 1
            }
            install_name_tool -change "$dependency" "@loader_path/../../${dependency:t}" "$module"
        fi
    done < <(otool -L "$module" | tail -n +2)
done < <(find "$wine_library_dir/wine" -type f -name '*.so' -print0)

if $graphics_runtime; then
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

while IFS= read -r -d '' binary; do
    if /usr/bin/file -b "$binary" | grep -q 'Mach-O'; then
        if [[ "$code_sign_identity" == "-" ]]; then
            codesign --force --sign - "$binary"
        else
            codesign --force --timestamp --sign "$code_sign_identity" "$binary"
        fi
    fi
done < <(find "$runtime_dir/Libraries" -type f -print0)

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

/usr/libexec/PlistBuddy -c "Add :wineSource string $wine_source" "$provenance_plist"
/usr/libexec/PlistBuddy -c "Add :wineTag string $wine_tag" "$provenance_plist"
/usr/libexec/PlistBuddy -c "Add :wineDistribution string $wine_distribution" "$provenance_plist"
if [[ -n "$crossover_source_archive" ]]; then
    /usr/libexec/PlistBuddy -c "Add :wineSourceArchiveSHA256 string $CROSSOVER_WINE_SOURCE_SHA256" "$provenance_plist"
else
    /usr/libexec/PlistBuddy -c "Add :wineRevision string $(git -C "$source_dir" rev-parse HEAD)" "$provenance_plist"
fi
/usr/libexec/PlistBuddy -c 'Add :wineLicense string LGPL-2.1-or-later' "$provenance_plist"
/usr/libexec/PlistBuddy -c "Add :architecture string $architecture" "$provenance_plist"
/usr/libexec/PlistBuddy -c 'Add :runtimeDependencySource string Homebrew' "$provenance_plist"
/usr/libexec/PlistBuddy -c "Add :freetypeVersion string $(brew info --json=v2 freetype | plutil -extract formulae.0.versions.stable raw -)" "$provenance_plist"
/usr/libexec/PlistBuddy -c 'Add :freetypeLicense string FTL' "$provenance_plist"
/usr/libexec/PlistBuddy -c "Add :gnutlsVersion string $(brew info --json=v2 gnutls | plutil -extract formulae.0.versions.stable raw -)" "$provenance_plist"
/usr/libexec/PlistBuddy -c 'Add :gnutlsLicense string LGPL-2.1-or-later' "$provenance_plist"
/usr/libexec/PlistBuddy -c "Add :libusbVersion string $(brew info --json=v2 libusb | plutil -extract formulae.0.versions.stable raw -)" "$provenance_plist"
/usr/libexec/PlistBuddy -c 'Add :libusbLicense string LGPL-2.1-or-later' "$provenance_plist"
/usr/libexec/PlistBuddy -c "Add :libX11Version string $(brew info --json=v2 libx11 | plutil -extract formulae.0.versions.stable raw -)" "$provenance_plist"
/usr/libexec/PlistBuddy -c 'Add :libX11License string MIT' "$provenance_plist"
/usr/libexec/PlistBuddy -c "Add :libXextVersion string $(brew info --json=v2 libxext | plutil -extract formulae.0.versions.stable raw -)" "$provenance_plist"
/usr/libexec/PlistBuddy -c 'Add :libXextLicense string MIT' "$provenance_plist"
/usr/libexec/PlistBuddy -c "Add :sdl2Version string $(brew info --json=v2 sdl2 | plutil -extract formulae.0.versions.stable raw -)" "$provenance_plist"
/usr/libexec/PlistBuddy -c 'Add :sdl2License string Zlib' "$provenance_plist"
/usr/libexec/PlistBuddy -c "Add :sdl3Version string $(brew info --json=v2 sdl3 | plutil -extract formulae.0.versions.stable raw -)" "$provenance_plist"
/usr/libexec/PlistBuddy -c 'Add :sdl3License string Zlib' "$provenance_plist"
if $graphics_runtime; then
    /usr/libexec/PlistBuddy -c "Add :dxvkSource string $DXVK_SOURCE" "$provenance_plist"
    /usr/libexec/PlistBuddy -c "Add :dxvkTag string $dxvk_tag" "$provenance_plist"
    /usr/libexec/PlistBuddy -c "Add :dxvkRevision string $(git -C "$dxvk_source_dir" rev-parse HEAD)" "$provenance_plist"
    /usr/libexec/PlistBuddy -c 'Add :dxvkLicense string zlib' "$provenance_plist"
    /usr/libexec/PlistBuddy -c "Add :dxvkPortabilityPatchSHA256 string $(<"$dxvk_output_dir/portability-patch.sha256")" "$provenance_plist"
    /usr/libexec/PlistBuddy -c "Add :dxvkMingw14PatchSHA256 string $(<"$dxvk_output_dir/mingw14-patch.sha256")" "$provenance_plist"
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
