#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

# Verify that a DXVK-macOS component artifact is complete and portability-aware.
set -euo pipefail

usage() {
    print "Usage: ${0:t} --output DIR [--revision SHA] [--tag TAG]"
}

output_dir=""
expected_revision=""
expected_tag=""
while (( $# )); do
    case "$1" in
        --output) output_dir="$2"; shift 2 ;;
        --revision) expected_revision="$2"; shift 2 ;;
        --tag) expected_tag="$2"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) print -u2 "Unknown argument: $1"; usage; exit 2 ;;
    esac
done

patch_dir="${0:A:h}/patches"
for command in file openssl strings; do
    command -v "$command" >/dev/null || {
        print -u2 "Missing required command: $command"
        exit 1
    }
done
if [[ ! -d "$output_dir" || ! -f "$patch_dir/dxvk-macos-portability.patch" ||
      ! -f "$patch_dir/dxvk-macos-mingw14.patch" ||
      ! -f "$output_dir/source-revision.txt" ||
      ! -f "$output_dir/source-tag.txt" ||
      ! -f "$output_dir/portability-patch.sha256" ||
      ! -f "$output_dir/mingw14-patch.sha256" ]]; then
    print -u2 'Incomplete DXVK-macOS component artifact.'
    exit 1
fi

revision="$(<"$output_dir/source-revision.txt")"
tag="$(<"$output_dir/source-tag.txt")"
[[ "$revision" =~ '^[0-9a-f]{40}$' ]] || {
    print -u2 "Invalid DXVK source revision: $revision"
    exit 1
}
[[ "$tag" =~ '^v[0-9]+\.[0-9]+(\.[0-9]+)?(-[A-Za-z0-9.-]+)?$' ]] || {
    print -u2 "Invalid DXVK source tag: $tag"
    exit 1
}
[[ -z "$expected_revision" || "$revision" == "$expected_revision" ]] || {
    print -u2 "DXVK revision mismatch: expected $expected_revision, got $revision"
    exit 1
}
[[ -z "$expected_tag" || "$tag" == "$expected_tag" ]] || {
    print -u2 "DXVK tag mismatch: expected $expected_tag, got $tag"
    exit 1
}
for patch_name in portability mingw14; do
    expected_patch_hash="$(openssl dgst -sha256 "$patch_dir/dxvk-macos-$patch_name.patch" | awk '{print $NF}')"
    actual_patch_hash="$(<"$output_dir/$patch_name-patch.sha256")"
    [[ "$actual_patch_hash" == "$expected_patch_hash" ]] || {
        print -u2 "DXVK $patch_name patch checksum mismatch."
        exit 1
    }
done

for architecture in x64 x32; do
    for dll in d3d11.dll dxgi.dll; do
        [[ -f "$output_dir/$architecture/bin/$dll" ]] || {
            print -u2 "Missing DXVK output: $output_dir/$architecture/bin/$dll"
            exit 1
        }
    done
    strings "$output_dir/$architecture/bin/dxgi.dll" | \
        grep -Fx VK_KHR_portability_enumeration >/dev/null || {
        print -u2 "DXVK $architecture does not contain the portability extension gate."
        exit 1
    }
done
file "$output_dir/x64/bin/dxgi.dll" | grep -q PE32+
file "$output_dir/x32/bin/dxgi.dll" | grep -q 'PE32 executable'

print "Verified DXVK-macOS component artifact at $output_dir"
