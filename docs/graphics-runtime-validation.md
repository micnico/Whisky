# Wine 11 DXVK + MoltenVK candidate validation

This is an unpublished, locally built candidate. It is not a public runtime release and contains no Apple Game Porting Toolkit or D3DMetal binaries.

## Immutable inputs

| Component | Source | Revision | License |
| --- | --- | --- | --- |
| Wine | https://gitlab.winehq.org/wine/wine.git | `wine-11.0` / `db11d0fe6a169c457e23d007e20404643d067aa8` | LGPL-2.1-or-later |
| DXVK | https://github.com/doitsujin/dxvk | `v3.0.1` / `c850747f1df24180ce97b7a9094603f39da1251d` | zlib |
| MoltenVK | https://github.com/KhronosGroup/MoltenVK | `v1.4.1` / `db445ff2042d9ce348c439ad8451112f354b8d2a` | Apache-2.0 |
| Vulkan Loader | https://github.com/KhronosGroup/Vulkan-Loader | Homebrew `1.4.350.1` | Apache-2.0 |

The package layout is `Libraries/Wine`, `Libraries/DXVK/{x64,x32}`, and `Libraries/Vulkan`. `MoltenVK_icd.json` selects the bundled `libMoltenVK.dylib`; Bottle DXVK mode sets that JSON in `VK_DRIVER_FILES` and the deprecated `VK_ICD_FILENAMES` compatibility variable, then prepends only runtime-internal Vulkan and Wine library folders to `DYLD_FALLBACK_LIBRARY_PATH`.

## Candidate artifact

The locally generated archive is named `wine-11.0-dxvk-moltenvk-arm64-r1.tar.gz`.

```text
SHA-256: 0d57462da9be6e44df48a670bf2dd398c9b67c1d650d0c7c4a5846f02aac24a0
```

It contains `WhiskyWineVersion.plist`, `WhiskyWineProvenance.plist`, and `WhiskyWineBinaries.sha256`. The latter has 2,640 entries and was regenerated after extraction; the regenerated file compared byte-for-byte with the archive's copy.

## Smoke results

All checks were performed on Apple Silicon using a clean temporary 64-bit Bottle prefix and the archive contents.

| Workload | Architecture | Result |
| --- | --- | --- |
| `vkCreateInstance` + physical-device enumeration | ARM64 | passed |
| `D3D11CreateDevice` with `WINEDLLOVERRIDES=d3d11,dxgi=n` | x64 | passed |
| `D3D11CreateDevice` with `WINEDLLOVERRIDES=d3d11,dxgi=n` | x86 | passed |
| `D3D12CreateDevice` via Wine 11's built-in D3D12 path | x64 | passed |
| Start an x64 program in the same prefix with the plain Wine 11 runtime | x64 | passed |

The DXVK tests use native-only overrides, so success cannot be attributed to WineD3D fallback. The D3D12 result is Wine's built-in path, not DXVK, GPTK, or a claim of broad game compatibility.

## Remaining release work

`Build Graphics Runtime Candidate` is a manual Apple Silicon GitHub Actions workflow. It rebuilds the fixed tags and invokes `verify-graphics-runtime.sh`, which validates the provenance plist, required Wine/DXVK/MoltenVK files, code signatures, architectures, and the complete SHA-256 file list. With a configured Developer ID signing certificate, it signs every Mach-O file, then starts the extracted Wine binary and a freshly compiled 32-bit Windows executable in a clean prefix. Without that certificate, the workflow records a skipped executable smoke test rather than treating an Apple System Policy termination as a Wine regression. GitHub signs a provenance attestation for the archive, digest, and client manifest before the workflow retains them as a 14-day artifact. The workflow does not publish a release or make the candidate available to users.

Before publishing this candidate, run the graphics workload suite from CI, host the archive and signed manifest through the release channel, and repeat the rollback smoke test through the actual Bottle migration UI. Keep it opt-in until real application compatibility data is recorded.
