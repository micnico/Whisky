# Wine 11 DXVK-macOS + MoltenVK candidate validation

This is an unpublished engineering candidate. It contains no Apple Game Porting Toolkit or D3DMetal binaries and must not change an existing Bottle during validation.

## Immutable inputs

| Component | Source | Revision | License |
| --- | --- | --- | --- |
| Wine | https://gitlab.winehq.org/wine/wine.git | `wine-11.0` / `db11d0fe6a169c457e23d007e20404643d067aa8` | LGPL-2.1-or-later |
| DXVK-macOS | https://github.com/Gcenx/DXVK-macOS | `v1.10.3-20230507-repack` / `8f1e28deed3ad30802f7e1bdff428ec14e6e7817` | zlib |
| MoltenVK | https://github.com/KhronosGroup/MoltenVK | `v1.4.1` / `db445ff2042d9ce348c439ad8451112f354b8d2a` | Apache-2.0 |
| Vulkan Loader | https://github.com/KhronosGroup/Vulkan-Loader | version recorded from the build host | Apache-2.0 |

DXVK-macOS remains on its macOS-compatible 1.10.3 line intentionally. Upstream DXVK 3.0.1 requires Vulkan features that MoltenVK does not expose and is not a valid upgrade for this backend.

Two source patches are part of the pinned input and their hashes are recorded in `WhiskyWineProvenance.plist`:

| Patch | SHA-256 | Purpose |
| --- | --- | --- |
| `dxvk-macos-portability.patch` | `fc8f465e1ca3f04caea68f4ae7707f67b60b81dc98462d1b9a1917d818930a27` | Enables `VK_KHR_portability_enumeration` and its instance-create flag when the loader exposes it |
| `dxvk-macos-mingw14.patch` | `cce5b3a3494f7401786958250abe57f3f11756aeef416e32182fa3637518dee3` | Uses DXVK's namespace for a definition now supplied by current MinGW headers |

The MoltenVK manifest must retain `ICD.is_portability_driver=true`. Removing that declaration to bypass Vulkan Loader filtering is not an accepted compatibility mechanism.

## Pipeline contract

`Build Graphics Runtime Candidate` separates the work into these gates:

1. `preflight` validates all immutable tags and, before a Wine build, proves the Wine loader paths and bundleable dependencies.
2. `graphics-preflight` builds both DXVK-macOS PE architectures, applies the pinned patches, verifies their hashes, and uploads a reusable component artifact. It can run with `build_candidate=false`.
3. `repackage` can combine that component artifact with an existing Wine 11 archive and repair its Homebrew dependency closure without rebuilding Wine.
4. `verify` rejects host Homebrew references, unresolved `@loader_path` entries, an unmarked MoltenVK portability driver, incorrect provenance, missing hashes, or DXVK binaries without the portability extension.
5. The three independent smoke jobs run Wine bootstrap, a 32-bit WoW64 executable, and the graphics chain. The x86_64 graphics candidate runs on an Apple-silicon host through Rosetta.
6. `attest` cannot run until all applicable smoke jobs pass.

The graphics smoke is not satisfied by process exit alone. Its log must show DXVK 1.10.3, `VK_KHR_portability_enumeration`, D3D feature level 11_0, and the Vulkan Loader selecting the bundled `libMoltenVK.dylib`.

## Current evidence

On 2026-07-20, run [`29753990552`](https://github.com/micnico/Whisky/actions/runs/29753990552) built and verified the pinned DXVK-macOS x64/x32 component, skipped the full Wine build, repackaged source artifact run `29747213847`, verified the complete archive and provenance, and passed Wineboot, WoW64, and attestation. The runtime archive SHA-256 is `ccec9f0717135b8405674b0a8e5408d3f9b2b8283f48d0c0c07319045e3d9c9e`; the GitHub candidate artifact digest is `sha256:04ca01fbbb62889a34651a562da359b6b93275186c7b70c2721475f0f7401545`.

The hosted Apple-silicon runner exposed no Metal device, so its graphics job correctly recorded `SKIPPED`. The exact candidate was then downloaded and tested with the repository verifier in three new temporary prefixes on an Apple M4. The `D3D11CreateDevice` fixture completed successfully through:

```text
D3D11 -> DXVK-macOS 1.10.3 -> WineVulkan -> bundled Vulkan Loader -> MoltenVK 1.4.1 -> Apple M4
```

The log recorded DXVK-macOS 1.10.3, the portability extension, Apple M4 device selection, D3D feature level 11_0, Vulkan device creation, the bundled `libMoltenVK.dylib`, and clean device destruction. Static verification rejected host Homebrew references and unresolved loader paths. Wineboot emitted neither the FreeType nor GnuTLS missing-library diagnostics. The test did not read or modify a Whisky Bottle.

The no-rebuild gates are complete for this provenance-linked candidate, and [attestation 36183615](https://github.com/micnico/Whisky/attestations/36183615) covers its three published subjects. A new full Wine build is not required for the runtime-only dependency and DXVK repair. The candidate remains unpublished until application integration and the broader compatibility matrix are completed.
