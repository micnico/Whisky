#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

# Prove Wine's configure step embeds runtime-relative dlopen() paths without
# compiling Wine. The caller supplies an already checked-out Wine source tree.
set -euo pipefail

usage() {
    print "Usage: ${0:t} --source DIR --workdir DIR [--architecture arm64|x86_64] [--compile-win32u] [--jobs N]"
}

source_dir=""
work_dir=""
architecture="$(uname -m)"
compile_win32u=false
jobs=3
while (( $# )); do
    case "$1" in
        --source) source_dir="$2"; shift 2 ;;
        --workdir) work_dir="$2"; shift 2 ;;
        --architecture) architecture="$2"; shift 2 ;;
        --compile-win32u) compile_win32u=true; shift ;;
        --jobs) jobs="$2"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) print -u2 "Unknown argument: $1"; usage; exit 2 ;;
    esac
done

if [[ -z "$source_dir" || -z "$work_dir" || ! -x "$source_dir/configure" || -e "$work_dir" ]]; then
    print -u2 -- "--source must contain configure and --workdir must not exist."
    usage
    exit 2
fi
if [[ "$architecture" != "arm64" && "$architecture" != "x86_64" ]] || [[ "$(uname -m)" != "$architecture" ]]; then
    print -u2 -- "Run this preflight on an arm64 or x86_64 host matching --architecture."
    exit 1
fi
[[ "$jobs" =~ '^[1-9][0-9]*$' ]] || {
    print -u2 -- "--jobs must be a positive integer."
    exit 2
}

for command in brew grep make strings; do
    command -v "$command" >/dev/null || {
        print -u2 "Missing required command: $command"
        exit 1
    }
done

bison_prefix="$(brew --prefix bison)"
llvm_prefix="$(brew --prefix llvm)"
lld_prefix="$(brew --prefix lld)"
freetype_prefix="$(brew --prefix freetype)"
gnutls_prefix="$(brew --prefix gnutls)"
sdl2_prefix="$(brew --prefix sdl2)"
sdl2_library="$sdl2_prefix/lib/libSDL2-2.0.0.dylib"
if [[ ! -f "$sdl2_library" ]]; then
    sdl2_installed=("${(z)$(brew list --versions sdl2)}")
    (( ${#sdl2_installed} >= 2 )) || {
        print -u2 "Homebrew reports no installed SDL2 formula."
        exit 1
    }
    sdl2_library="$(brew --cellar)/${sdl2_installed[1]}/${sdl2_installed[2]}/lib/libSDL2-2.0.0.dylib"
    [[ -f "$sdl2_library" ]] || {
        print -u2 "Missing libSDL2-2.0.0.dylib after installing sdl2."
        exit 1
    }
    sdl2_prefix="${sdl2_library:h:h}"
fi
vulkan_headers_prefix="$(brew --prefix vulkan-headers)"
vulkan_loader_prefix="$(brew --prefix vulkan-loader)"
export PATH="$llvm_prefix/bin:$lld_prefix/bin:$bison_prefix/bin:$PATH"

configure_args=()
if [[ "$architecture" == "x86_64" ]]; then
    configure_args=(--build=x86_64-apple-darwin --enable-archs=i386,x86_64)
fi

mkdir -p "$work_dir/build"
(
    cd "$work_dir/build"
    env \
        ac_cv_lib_soname_freetype='@loader_path/../../libfreetype.6.dylib' \
        ac_cv_lib_soname_gnutls='@loader_path/../../libgnutls.30.dylib' \
        ac_cv_lib_soname_vulkan='@loader_path/../../../../Vulkan/libvulkan.1.dylib' \
        PKG_CONFIG_PATH="$freetype_prefix/lib/pkgconfig:$gnutls_prefix/lib/pkgconfig:$sdl2_prefix/lib/pkgconfig:$vulkan_loader_prefix/lib/pkgconfig:$vulkan_headers_prefix/share/pkgconfig" \
        CPPFLAGS="-I$freetype_prefix/include -I$gnutls_prefix/include -I$sdl2_prefix/include -I$vulkan_headers_prefix/include" \
        LDFLAGS="-L$freetype_prefix/lib -L$gnutls_prefix/lib -L$sdl2_prefix/lib -L$vulkan_loader_prefix/lib" \
        "$source_dir/configure" "${configure_args[@]}"
)

config="$work_dir/build/include/config.h"
for definition in \
    '#define SONAME_LIBFREETYPE "@loader_path/../../libfreetype.6.dylib"' \
    '#define SONAME_LIBGNUTLS "@loader_path/../../libgnutls.30.dylib"' \
    '#define SONAME_LIBVULKAN "@loader_path/../../../../Vulkan/libvulkan.1.dylib"'; do
    grep -Fxq "$definition" "$config" || {
        print -u2 "Wine configure did not emit: $definition"
        exit 1
    }
done

if $compile_win32u; then
    module="$work_dir/build/dlls/win32u/win32u.so"
    make -C "$work_dir/build" -j"$jobs" dlls/win32u/win32u.so
    strings "$module" | grep -Fx '@loader_path/../../../../Vulkan/libvulkan.1.dylib' >/dev/null || {
        print -u2 'Compiled win32u.so does not resolve Vulkan from the bundled runtime path.'
        exit 1
    }
fi

print "Wine configure loader-path preflight passed for $architecture."
