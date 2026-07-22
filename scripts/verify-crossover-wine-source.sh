#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

# Verify the public CrossOver source bundle before using its Wine tree.
set -euo pipefail
export LC_ALL=C

archive=""
expected_sha256=""
version=""

while (( $# )); do
    case "$1" in
        --archive) archive="$2"; shift 2 ;;
        --sha256) expected_sha256="$2"; shift 2 ;;
        --version) version="$2"; shift 2 ;;
        *) print -u2 "Unknown argument: $1"; exit 2 ;;
    esac
done

if [[ ! -f "$archive" || ! "$expected_sha256" =~ '^[0-9a-f]{64}$' || ! "$version" =~ '^[0-9]+\.[0-9]+$' ]]; then
    print -u2 'Usage: verify-crossover-wine-source.sh --archive FILE --sha256 SHA256 --version X.Y'
    exit 2
fi

actual_sha256="$(openssl dgst -sha256 "$archive" | awk '{print $NF}')"
[[ "$actual_sha256" == "$expected_sha256" ]] || {
    print -u2 "CrossOver source checksum mismatch: expected $expected_sha256, got $actual_sha256"
    exit 1
}

required=(
    sources/wine/VERSION
    sources/wine/dlls/ntdll/loader.c
    sources/wine/dlls/ntdll/ntdll.spec
    sources/wine/dlls/ntdll/unix/msync.c
    sources/wine/dlls/ntdll/unix/msync.h
    sources/wine/dlls/winemac.drv/d3dmetal.c
    sources/wine/dlls/winemac.drv/d3dmetal_objc.m
    sources/wine/server/msync.c
    sources/wine/server/msync.h
)
for entry in "${required[@]}"; do
    tar -tzf "$archive" "$entry" >/dev/null || {
        print -u2 "CrossOver source is missing $entry"
        exit 1
    }
done

[[ "$(tar -xOzf "$archive" sources/wine/VERSION)" == "Wine version $version" ]] || {
    print -u2 "CrossOver source does not contain Wine $version"
    exit 1
}
tar -xOzf "$archive" sources/wine/dlls/winemac.drv/d3dmetal.c | grep -F 'macdrv_functions' >/dev/null
tar -xOzf "$archive" sources/wine/dlls/ntdll/ntdll.spec | grep -F '__wine_unix_call' >/dev/null
tar -xOzf "$archive" sources/wine/server/msync.c | grep -F 'WINEMSYNC' >/dev/null

print "Verified CrossOver Wine $version source: $actual_sha256"
