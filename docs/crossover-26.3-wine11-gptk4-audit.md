# CrossOver 26.3 Wine 11 and GPTK 4 audit

Date: 2026-07-22

This audit determines whether Whisky's accepted WineHQ 11 runtime can load the
user-provided Game Porting Toolkit 4 graphics bridge, and whether the public
CrossOver Wine 11 source is a suitable integration baseline. It does not copy,
publish, or add Apple binaries to Whisky.

## Inputs

| Input | Source | SHA-256 / version |
| --- | --- | --- |
| CrossOver 26.3 FOSS source | `https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz` | `ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872` |
| WineHQ 11.0 source | `https://dl.winehq.org/wine/source/11.0/wine-11.0.tar.xz` | `c07a6857933c1fc60dff5448d79f39c92481c1e9db5aa628db9d0358446e0701` |
| Accepted Whisky Wine 11 runtime | Local engineering artifact | `ccec9f0717135b8405674b0a8e5408d3f9b2b8283f48d0c0c07319045e3d9c9e` |
| Apple evaluation environment | User-provided mounted image | GPTK 4.0 beta 1 / D3DMetal 4.0b1 |

The host used for the read-only Apple binary inspection was an Apple M4 Mac
running macOS 15.1.1. The GPTK README requires Apple silicon and macOS 15 or
later. Its `D3DM_ENABLE_METALFX` path requires macOS 26, while `D3DM_MTL4=1`
requires macOS 27 or later.

## Source delta

Both source trees report `Wine version 11.0`. Compared with the WineHQ 11.0
release, the CrossOver 26.3 Wine tree contains:

- 221 changed paths: 17 added and 204 modified;
- approximately 15,717 added and 662 deleted lines;
- a D3DMetal bridge in `dlls/winemac.drv/d3dmetal.c` and
  `d3dmetal_objc.m`;
- client and server MSync implementations in `dlls/ntdll/unix/msync.c` and
  `server/msync.c`;
- the `__wine_unix_call` export required by D3DMetal PE DLLs;
- Metal view, layer, client-surface, frame-presentation, GPU LUID, input,
  audio, controller, windowing, and WoW64 changes.

The D3DMetal bridge exports a 192-byte `macdrv_functions` table containing 24
function pointers. GPTK 4.0b1's user-provided `libd3dshared.dylib` uses
`dlsym(RTLD_DEFAULT, "macdrv_functions")`, while its D3D10, D3D11, D3D12, and
DXGI PE DLLs reference `__wine_unix_call`. The accepted WineHQ 11 runtime has
neither the D3DMetal bridge paths nor these CrossOver exports.

This proves that copying or pointing GPTK 4 at the accepted WineHQ 11 runtime
is not a valid integration. A compatible custom Wine build is required, as
Apple's README also states.

## Architecture boundary

GPTK 4.0b1 provides only these Windows graphics modules:

- `x86_64-windows/d3d10.dll`
- `x86_64-windows/d3d11.dll`
- `x86_64-windows/d3d12.dll`
- `x86_64-windows/dxgi.dll`
- `x86_64-windows/nvapi64.dll`
- `x86_64-windows/nvngx-on-metalfx.dll`

All are PE32+ x86-64 files. There is no i386 D3DMetal payload. Therefore:

| Windows workload | Required Whisky graphics route |
| --- | --- |
| 64-bit D3D11/D3D12 game | User-provided D3DMetal 4 candidate |
| 32-bit D3D9/D3D10/D3D11 game | x32 DXVK/MoltenVK or WineD3D fallback |
| 32-bit launcher starting a 64-bit game | WoW64 launcher plus D3DMetal 4 for the 64-bit game process |

The goal is a Wine 11 + GPTK 4 environment capable of running both 32-bit and
64-bit 3D games. It must not claim that GPTK 4 itself translates 32-bit D3D
calls when Apple does not ship the required i386 modules.

## Decision

1. Keep the accepted WineHQ 11 + DXVK/MoltenVK artifact as the reproducible
   baseline and 32-bit graphics fallback.
2. Use the public CrossOver 26.3 Wine tree as the first D3DMetal-compatible
   Wine 11 candidate instead of attempting to guess a subset of 221 changes.
3. Record the CrossOver source URL, archive SHA-256, Wine version, and LGPL
   license in runtime provenance.
4. Keep GPTK 4 outside the Wine runtime. Require a user-selected installation,
   inspect it in place, record its version and checksum metadata, and expose
   its four x64 DLLs through reversible Bottle-local symbolic links rather
   than copying or redistributing them.
5. Validate the CrossOver Wine build without GPTK first: static archive,
   `wineboot`, WoW64, and the existing x32/x64 DXVK path.
6. Validate user-provided GPTK 4 separately on a local Metal host with 64-bit
   D3D11 and D3D12 fixtures. A hosted runner without Metal records this stage
   as skipped.
7. Preserve the old runtime binding for every existing Bottle and make the
   D3DMetal candidate explicit and reversible.

## Remaining unknowns

- Runtime compatibility of the 26.3 Wine bridge with D3DMetal 4.0b1 must be
  proven by local execution even though Apple's README documents replacing
  CrossOver's existing `apple_gptk` layer with this distribution.
- The macOS 15 default D3DMetal backend can be tested on the current host, but
  MetalFX and the Metal 4 backend cannot be accepted until tested on their
  required macOS versions.
- Real-game acceptance still needs one 32-bit 3D title through DXVK and one
  64-bit D3D11/D3D12 title through D3DMetal 4. Anti-cheat and DRM remain
  compatibility data, not guaranteed support.
