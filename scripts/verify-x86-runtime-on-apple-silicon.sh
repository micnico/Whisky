#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

# Run isolated x86_64 Wine runtime smoke tests through Rosetta without touching a Bottle.
set -euo pipefail

readonly SCRIPT_NAME="${0:t}"

usage() {
    print "Usage: $SCRIPT_NAME --archive PATH --workdir DIR [--phase all|wineboot|wow64|graphics]"
}

archive=""
work_dir=""
phase="all"

while (( $# )); do
    case "$1" in
        --archive) archive="$2"; shift 2 ;;
        --workdir) work_dir="$2"; shift 2 ;;
        --phase) phase="$2"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) print -u2 "Unknown argument: $1"; usage; exit 2 ;;
    esac
done

if [[ "$phase" != "all" && "$phase" != "wineboot" && "$phase" != "wow64" && "$phase" != "graphics" ]]; then
    print -u2 -- "--phase must be all, wineboot, wow64, or graphics."
    exit 2
fi

if [[ "$(uname -m)" != "arm64" || -z "$archive" || -z "$work_dir" || ! -f "$archive" || -e "$work_dir" ]]; then
    print -u2 -- "Run on Apple silicon with an existing archive and a new work directory."
    usage
    exit 2
fi

commands=(arch plutil tar)
[[ "$phase" != "graphics" ]] || commands+=(brew clang xcrun x86_64-w64-mingw32-gcc)
[[ "$phase" != "wow64" ]] || commands+=(i686-w64-mingw32-gcc)
[[ "$phase" != "all" ]] || commands+=(brew clang i686-w64-mingw32-gcc xcrun x86_64-w64-mingw32-gcc)
for command in $commands; do
    command -v "$command" >/dev/null || {
        print -u2 "Missing required command: $command"
        exit 1
    }
done

arch -x86_64 /usr/bin/true

script_dir="${0:A:h}"
verify_dir="$work_dir/static"
smoke_dir="$work_dir/runtime"
"$script_dir/verify-graphics-runtime.sh" \
    --archive "$archive" \
    --workdir "$verify_dir" \
    --architecture x86_64

mkdir -p "$smoke_dir"
tar -C "$smoke_dir" -xzf "$archive"
wine="$smoke_dir/Libraries/Wine/bin/wine64"
wine_tag="$(plutil -extract wineTag raw "$smoke_dir/Libraries/WhiskyWineProvenance.plist")"
test "$(arch -x86_64 "$wine" --version)" = "$wine_tag"
export VK_DRIVER_FILES="$smoke_dir/Libraries/Vulkan/MoltenVK_icd.json"
export DYLD_FALLBACK_LIBRARY_PATH="$smoke_dir/Libraries/Vulkan:$smoke_dir/Libraries/Wine/lib"

run_wineboot() {
    local prefix="$1" log="$2"
    WINEPREFIX="$prefix" WINEDLLOVERRIDES="mscoree,mshtml=" \
        arch -x86_64 "$wine" wineboot -u 2>&1 | tee "$log"
    if grep -Eq 'Wine cannot find the FreeType|gnutls_process_attach failed to load libgnutls|NSInternalInconsistencyException|libc\+\+abi: terminating|process_send_command receiving command result timed out' "$log"; then
        print -u2 'wineboot logged a missing bundled dependency, native service crash, or timeout.'
        return 1
    fi
}

smoke_wineboot() {
    print '== Wine bootstrap =='
    run_wineboot "$smoke_dir/prefix-wineboot" "$work_dir/wineboot.log"
}

smoke_wow64() {
    print '== WoW64 =='
    local prefix="$smoke_dir/prefix-wow64"
    i686-w64-mingw32-gcc "$script_dir/fixtures/smoke-win32.c" -o "$smoke_dir/smoke-win32.exe"
    run_wineboot "$prefix" "$work_dir/wow64-wineboot.log"
    WINEPREFIX="$prefix" arch -x86_64 "$wine" "$smoke_dir/smoke-win32.exe" \
        2>&1 | tee "$work_dir/wow64.log"
}

smoke_graphics() {
    print '== Metal, Vulkan, MoltenVK, DXVK, and D3D11 =='
    xcrun swift -e 'import Metal; if MTLCreateSystemDefaultDevice() == nil { exit(1) }' || {
        print -u2 'No Metal device is available; real graphics acceptance cannot run in this terminal.'
        return 1
    }
    local prefix="$smoke_dir/prefix-graphics"
    local vulkan_dir="$smoke_dir/Libraries/Vulkan"
    clang -arch x86_64 "$script_dir/fixtures/smoke-vulkan.c" \
        -I"$(brew --prefix vulkan-headers)/include" \
        "$vulkan_dir/libvulkan.1.dylib" \
        -Wl,-rpath,"$vulkan_dir" \
        -o "$smoke_dir/smoke-vulkan"
    MVK_CONFIG_DEBUG=1 MVK_CONFIG_LOG_LEVEL=4 MVK_CONFIG_TRACE_VULKAN_CALLS=1 \
        VK_LOADER_DEBUG=error,warn,driver arch -x86_64 "$smoke_dir/smoke-vulkan" \
        2>&1 | tee "$work_dir/vulkan.log"
    x86_64-w64-mingw32-gcc "$script_dir/fixtures/smoke-d3d11.c" \
        -o "$smoke_dir/smoke-d3d11.exe" -ld3d11 -ldxgi
    run_wineboot "$prefix" "$work_dir/graphics-wineboot.log"
    cp "$smoke_dir/Libraries/DXVK/x64/"*.dll "$prefix/drive_c/windows/system32/"
    WINEPREFIX="$prefix" VK_LOADER_DEBUG=error,warn,driver \
        WINEDLLOVERRIDES="d3d11,dxgi=n,b" \
        arch -x86_64 "$wine" "$smoke_dir/smoke-d3d11.exe" \
        2>&1 | tee "$work_dir/d3d11.log"
}

case "$phase" in
    wineboot) smoke_wineboot ;;
    wow64) smoke_wow64 ;;
    graphics) smoke_graphics ;;
    all)
        smoke_wineboot
        smoke_wow64
        smoke_graphics
        ;;
esac

print "Rosetta $phase smoke test passed for $archive"
