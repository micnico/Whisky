#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later

# Fail fast when the Homebrew libraries Wine loads with dlopen() cannot be
# bundled into a self-contained runtime. This intentionally does not compile
# Wine or download source.
set -euo pipefail

usage() {
    print "Usage: ${0:t} [--architecture arm64|x86_64]"
}

architecture="$(uname -m)"
while (( $# )); do
    case "$1" in
        --architecture) architecture="$2"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) print -u2 "Unknown argument: $1"; usage; exit 2 ;;
    esac
done

if [[ "$architecture" != "arm64" && "$architecture" != "x86_64" ]]; then
    print -u2 -- "--architecture must be arm64 or x86_64."
    exit 2
fi
if [[ "$(uname -m)" != "$architecture" ]]; then
    print -u2 -- "Run this preflight on a $architecture host."
    exit 1
fi
for command in brew file otool tail; do
    command -v "$command" >/dev/null || {
        print -u2 "Missing required command: $command"
        exit 1
    }
done

brew_prefix="$(brew --prefix)"
brew_cellar="$(brew --cellar)"

resolve_library() {
    local formula="$1" name="$2" prefix candidate
    prefix="$(brew --prefix "$formula")"
    candidate="$prefix/lib/$name"
    if [[ ! -f "$candidate" && "$formula" == "sdl2" ]]; then
        local -a installed
        installed=("${(z)$(brew list --versions sdl2)}")
        (( ${#installed} >= 2 )) || {
            print -u2 "Homebrew reports no installed SDL2 formula."
            exit 1
        }
        candidate="$brew_cellar/${installed[1]}/${installed[2]}/lib/$name"
    fi
    [[ -n "$candidate" && -f "$candidate" ]] || {
        print -u2 "Missing $name for Homebrew formula $formula."
        exit 1
    }
    print -r -- "$candidate"
}

typeset -A visited
integer library_count=0
visit_library() {
    local library="$1" dependency first=true
    library="${library:A}"
    [[ "$library" == "$brew_prefix/"* ]] || {
        print -u2 "Dependency is outside Homebrew: $library"
        exit 1
    }
    [[ -z "${visited[$library]:-}" ]] || return 0
    visited[$library]=1
    (( library_count += 1 ))
    file "$library" | grep -q "$architecture" || {
        print -u2 "Wrong architecture in $library; expected $architecture."
        exit 1
    }
    while IFS= read -r dependency; do
        dependency="${dependency#"${dependency%%[![:space:]]*}"}"
        dependency="${dependency%% \(*}"
        if $first; then
            first=false
            continue
        fi
        case "$dependency" in
            /System/*|/usr/lib/*|@*) ;;
            "$brew_prefix"/*)
                [[ -f "$dependency" ]] || {
                    print -u2 "Missing Homebrew dependency: $dependency"
                    exit 1
                }
                visit_library "$dependency"
                ;;
            *)
                print -u2 "Unbundleable runtime dependency: $dependency (required by $library)"
                exit 1
                ;;
        esac
    done < <(otool -L "$library" | tail -n +2)
}

for spec in \
    "freetype libfreetype.6.dylib" \
    "gnutls libgnutls.30.dylib" \
    "sdl2 libSDL2-2.0.0.dylib"; do
    library="$(resolve_library ${(z)spec})"
    print "Checking $library"
    visit_library "$library"
done

print "Runtime dependency preflight passed: $library_count Homebrew libraries are bundleable."
