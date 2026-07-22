#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

# Run isolated x86_64 Wine runtime smoke tests through Rosetta without touching a Bottle.
set -euo pipefail
export LC_ALL=C LANG=C

readonly SCRIPT_NAME="${0:t}"

usage() {
    print "Usage: $SCRIPT_NAME --archive PATH --workdir DIR [--phase all|wineboot|wow64|graphics|d3dmetal] [--d3dmetal-root DIR]"
}

archive=""
work_dir=""
phase="all"
d3dmetal_root=""

while (( $# )); do
    case "$1" in
        --archive) archive="$2"; shift 2 ;;
        --workdir) work_dir="$2"; shift 2 ;;
        --phase) phase="$2"; shift 2 ;;
        --d3dmetal-root) d3dmetal_root="$2"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) print -u2 "Unknown argument: $1"; usage; exit 2 ;;
    esac
done

if [[ "$phase" != "all" && "$phase" != "wineboot" && "$phase" != "wow64" &&
      "$phase" != "graphics" && "$phase" != "d3dmetal" ]]; then
    print -u2 -- "--phase must be all, wineboot, wow64, graphics, or d3dmetal."
    exit 2
fi

if [[ "$(uname -m)" != "arm64" || -z "$archive" || -z "$work_dir" || ! -f "$archive" || -e "$work_dir" ]]; then
    print -u2 -- "Run on Apple silicon with an existing archive and a new work directory."
    usage
    exit 2
fi
if [[ "$phase" == "d3dmetal" && -z "$d3dmetal_root" ]]; then
    print -u2 -- "--phase d3dmetal requires an existing --d3dmetal-root directory."
    exit 2
fi
if [[ -n "$d3dmetal_root" && ! -d "$d3dmetal_root" ]]; then
    print -u2 -- "--d3dmetal-root must be an existing directory."
    exit 2
fi
[[ -z "$d3dmetal_root" ]] || d3dmetal_root="${d3dmetal_root:A}"

required_commands=(arch file perl plutil tar)
[[ "$phase" != "graphics" ]] || required_commands+=(brew clang i686-w64-mingw32-gcc xcrun x86_64-w64-mingw32-gcc)
[[ "$phase" != "wow64" ]] || required_commands+=(i686-w64-mingw32-gcc)
[[ "$phase" != "all" ]] || required_commands+=(brew clang i686-w64-mingw32-gcc xcrun x86_64-w64-mingw32-gcc)
[[ "$phase" != "d3dmetal" ]] || required_commands+=(xcrun x86_64-w64-mingw32-gcc)
for command in $required_commands; do
    command -v "$command" >/dev/null || {
        print -u2 "Missing required command: $command"
        exit 1
    }
done

arch -x86_64 /usr/bin/true

run_x86() {
    perl -e 'alarm shift; exec @ARGV' 240 arch -x86_64 "$@"
}

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
test "$(run_x86 "$wine" --version)" = "$wine_tag"
export VK_DRIVER_FILES="$smoke_dir/Libraries/Vulkan/MoltenVK_icd.json"
export DYLD_FALLBACK_LIBRARY_PATH="$smoke_dir/Libraries/Vulkan:$smoke_dir/Libraries/Wine/lib"

run_wineboot() {
    local prefix="$1" log="$2"
    WINEPREFIX="$prefix" WINEDLLOVERRIDES="mscoree,mshtml=" \
        run_x86 "$wine" wineboot.exe -u 2>&1 | tee "$log"
    if grep -Eq 'Wine cannot find the FreeType|gnutls_process_attach failed to load libgnutls|invalid \.so library|NSInternalInconsistencyException|libc\+\+abi: terminating|process_send_command receiving command result timed out' "$log"; then
        print -u2 'wineboot logged an invalid runtime component, native service crash, or timeout.'
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
    WINEPREFIX="$prefix" run_x86 "$wine" "$smoke_dir/smoke-win32.exe" \
        2>&1 | tee "$work_dir/wow64.log"
}

smoke_graphics() {
    print '== Metal, Vulkan, MoltenVK, and x64/x86 DXVK D3D11 =='
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
        VK_LOADER_DEBUG=error,warn,driver run_x86 "$smoke_dir/smoke-vulkan" \
        2>&1 | tee "$work_dir/vulkan.log"
    x86_64-w64-mingw32-gcc "$script_dir/fixtures/smoke-d3d11.c" \
        -o "$smoke_dir/smoke-d3d11-x64.exe" -ld3d11 -ldxgi
    i686-w64-mingw32-gcc "$script_dir/fixtures/smoke-d3d11.c" \
        -o "$smoke_dir/smoke-d3d11-x86.exe" -ld3d11 -ldxgi
    run_wineboot "$prefix" "$work_dir/graphics-wineboot.log"
    cp "$smoke_dir/Libraries/DXVK/x64/"*.dll "$prefix/drive_c/windows/system32/"
    cp "$smoke_dir/Libraries/DXVK/x32/"*.dll "$prefix/drive_c/windows/syswow64/"
    WINEPREFIX="$prefix" WINEDEBUG=-all DXVK_LOG_LEVEL=info DXVK_LOG_PATH=none DXVK_STATE_CACHE=0 \
        VK_LOADER_DEBUG=error,warn,driver \
        WINEDLLOVERRIDES="d3d11,dxgi=n,b" \
        run_x86 "$wine" "$smoke_dir/smoke-d3d11-x64.exe" \
        2>&1 | tee "$work_dir/d3d11-x64.log"
    WINEPREFIX="$prefix" WINEDEBUG=-all DXVK_LOG_LEVEL=info DXVK_LOG_PATH=none DXVK_STATE_CACHE=0 \
        VK_LOADER_DEBUG=error,warn,driver \
        WINEDLLOVERRIDES="d3d11,dxgi=n,b" \
        run_x86 "$wine" "$smoke_dir/smoke-d3d11-x86.exe" \
        2>&1 | tee "$work_dir/d3d11-x86.log"
    for log in "$work_dir/d3d11-x64.log" "$work_dir/d3d11-x86.log"; do
        grep -F 'DXVK: v1.10.3' "$log"
        grep -F 'VK_KHR_portability_enumeration' "$log"
        grep -F 'D3D11CoreCreateDevice: Using feature level D3D_FEATURE_LEVEL_11_0' "$log"
        grep -E 'Using ".+" with driver: ".*/libMoltenVK\.dylib"' "$log"
    done
}

smoke_d3dmetal() {
    print '== User-provided D3DMetal D3D11 and D3D12 =='
    xcrun swift -e 'import Metal; if MTLCreateSystemDefaultDevice() == nil { exit(1) }' || {
        print -u2 'No Metal device is available; D3DMetal acceptance cannot run in this terminal.'
        return 1
    }
    local prefix="$smoke_dir/prefix-d3dmetal"
    local library="$d3dmetal_root/redist/lib"
    local windows="$library/wine/x86_64-windows"
    local shared="$library/external/libd3dshared.dylib"
    local framework="$library/external/D3DMetal.framework/Versions/A/D3DMetal"
    local name
    for name in d3d10.dll d3d11.dll d3d12.dll dxgi.dll; do
        file "$windows/$name" | grep -q 'PE32+.*x86-64' || {
            print -u2 "Invalid x64 D3DMetal DLL: $windows/$name"
            return 1
        }
    done
    for name in "$shared" "$framework"; do
        file "$name" | grep -q 'Mach-O.*x86_64' || {
            print -u2 "Invalid x86_64 D3DMetal library: $name"
            return 1
        }
    done
    x86_64-w64-mingw32-gcc "$script_dir/fixtures/smoke-d3d11.c" \
        -o "$smoke_dir/smoke-d3d11-d3dmetal.exe" -ld3d11 -ldxgi
    x86_64-w64-mingw32-gcc "$script_dir/fixtures/smoke-d3d12.c" \
        -o "$smoke_dir/smoke-d3d12-d3dmetal.exe" -ld3d12 -ldxgi -ldxguid
    run_wineboot "$prefix" "$work_dir/d3dmetal-wineboot.log"
    for name in d3d10.dll d3d11.dll d3d12.dll dxgi.dll; do
        rm -f "$prefix/drive_c/windows/system32/$name"
        ln -s "$windows/$name" "$prefix/drive_c/windows/system32/$name"
    done
    for name in d3d11 d3d12; do
        WINEPREFIX="$prefix" WINEDEBUG=-all WINEESYNC=1 WINEMSYNC=1 \
            CX_APPLEGPTK_LIBD3DSHARED_PATH="$shared" \
            D3DMETAL_FRAMEWORK_PATH="$framework" WINEDLLPATH="$library/wine" \
            WINEDLLOVERRIDES="d3d10,d3d11,d3d12,dxgi=n,b" \
            run_x86 "$wine" "$smoke_dir/smoke-$name-d3dmetal.exe" \
            2>&1 | tee "$work_dir/$name-d3dmetal.log"
    done
}

case "$phase" in
    wineboot) smoke_wineboot ;;
    wow64) smoke_wow64 ;;
    graphics) smoke_graphics ;;
    d3dmetal) smoke_d3dmetal ;;
    all)
        smoke_wineboot
        smoke_wow64
        smoke_graphics
        [[ -z "$d3dmetal_root" ]] || smoke_d3dmetal
        ;;
esac

print "Rosetta $phase smoke test passed for $archive"
