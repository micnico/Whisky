#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

# Build both DXVK-macOS PE architectures with Vulkan portability enabled.
set -euo pipefail

usage() {
    print "Usage: ${0:t} --source DIR --workdir DIR --output DIR"
}

source_dir=""
work_dir=""
output_dir=""

while (( $# )); do
    case "$1" in
        --source) source_dir="$2"; shift 2 ;;
        --workdir) work_dir="$2"; shift 2 ;;
        --output) output_dir="$2"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) print -u2 "Unknown argument: $1"; usage; exit 2 ;;
    esac
done

patch_dir="${0:A:h}/patches"
patches=(
    "$patch_dir/dxvk-macos-portability.patch"
    "$patch_dir/dxvk-macos-mingw14.patch"
)
if [[ ! -d "$source_dir/.git" || -e "$work_dir" || -e "$output_dir" ]]; then
    print -u2 -- "--source must be a clean Git checkout; --workdir and --output must not exist."
    exit 2
fi
for patch_file in "${patches[@]}"; do
    [[ -f "$patch_file" ]] || {
        print -u2 "Missing pinned DXVK patch: $patch_file"
        exit 1
    }
done
for command in file git meson ninja openssl strings; do
    command -v "$command" >/dev/null || {
        print -u2 "Missing required command: $command"
        exit 1
    }
done
[[ -z "$(git -C "$source_dir" status --short)" ]] || {
    print -u2 'DXVK source checkout must be clean before applying the pinned patch.'
    exit 1
}

for patch_file in "${patches[@]}"; do
    git -C "$source_dir" apply --check --unidiff-zero "$patch_file"
    git -C "$source_dir" apply --unidiff-zero "$patch_file"
done
git -C "$source_dir" diff --check
for patch_file in "${patches[@]}"; do
    git -C "$source_dir" apply --check --reverse --unidiff-zero "$patch_file"
done

mkdir -p "$work_dir" "$output_dir"
meson setup "$work_dir/x64" "$source_dir" --cross-file "$source_dir/build-win64.txt" \
    --buildtype release --prefix "$output_dir/x64"
ninja -C "$work_dir/x64" install
meson setup "$work_dir/x32" "$source_dir" --cross-file "$source_dir/build-win32.txt" \
    --buildtype release --prefix "$output_dir/x32"
ninja -C "$work_dir/x32" install

git -C "$source_dir" rev-parse HEAD > "$output_dir/source-revision.txt"
git -C "$source_dir" describe --tags --exact-match HEAD > "$output_dir/source-tag.txt"
openssl dgst -sha256 "$patch_dir/dxvk-macos-portability.patch" | awk '{print $NF}' \
    > "$output_dir/portability-patch.sha256"
openssl dgst -sha256 "$patch_dir/dxvk-macos-mingw14.patch" | awk '{print $NF}' \
    > "$output_dir/mingw14-patch.sha256"
"${0:A:h}/verify-dxvk-macos-output.sh" --output "$output_dir"
print "Built portable DXVK-macOS outputs in $output_dir"
