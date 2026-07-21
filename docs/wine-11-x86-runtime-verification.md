# Wine 11 x86_64 candidate verification record

Date: 2026-07-20

Status: current unpublished engineering candidate passed the self-contained runtime, Wineboot, WoW64, local Apple-silicon graphics, and provenance gates.

## Current accepted engineering candidate

GitHub Actions run [`29753990552`](https://github.com/micnico/Whisky/actions/runs/29753990552) at commit `6dc49264` reused Wine source artifact run `29747213847`; `build_candidate=false` kept the Wine `build` job explicitly skipped. DXVK-macOS x64/x32 preflight, repackage, archive verification, WoW64, and attestation succeeded. Its original Wineboot command was later superseded by the explicit `wineboot.exe` verification below.

- Runtime archive SHA-256: `ccec9f0717135b8405674b0a8e5408d3f9b2b8283f48d0c0c07319045e3d9c9e`.
- GitHub artifact digest: `sha256:04ca01fbbb62889a34651a562da359b6b93275186c7b70c2721475f0f7401545`.
- GitHub build provenance: [attestation 36183615](https://github.com/micnico/Whisky/attestations/36183615), signed through Sigstore for three subjects.
- Static verification rejected build-host Homebrew paths and unresolved loader paths, and verified bundled FreeType, GnuTLS, Vulkan Loader, MoltenVK, DXVK patches, file hashes, signatures, and provenance.
- Hosted graphics execution was explicitly `SKIPPED` because the GitHub ARM64 runner exposed no Metal device; it was not counted as graphics success.
- The exact candidate was then downloaded and tested on an Apple M4 through Rosetta in three new `/private/tmp` prefixes. On 2026-07-21, Wineboot was repeated with the unambiguous `wineboot.exe -u` command and passed. The 32-bit WoW64 fixture, native Vulkan, and the D3D11 fixture also passed. Logs recorded DXVK-macOS 1.10.3, `VK_KHR_portability_enumeration`, Apple M4, D3D feature level 11_0, and the bundled `libMoltenVK.dylib`.
- Wineboot logs contained neither the FreeType nor GnuTLS missing-library diagnostics and did not time out. No existing Whisky Bottle was read or changed.

This candidate contains no Apple Game Porting Toolkit or D3DMetal binary. It is accepted as the Wine 11 x86_64 runtime engineering input and remains unpublished while the broader compatibility matrix is completed.

## Application integration

Whisky can import the exact accepted archive from **Settings → Wine Runtime**. The importer verifies the recorded archive SHA-256 before extraction, installs the runtime under its versioned identifier, and selects it as the default for newly created Bottles. An arbitrary or modified archive is rejected.

Existing Bottles keep their recorded runtime identifier. Moving one to Wine 11 remains an explicit operation in that Bottle's configuration and uses the existing backup, Wineboot smoke test, and automatic restore path. The legacy runtime remains installed and selectable for rollback.

## Historical rejected candidate

This record covers the Wine 11 x86_64 graphics candidate built by GitHub Actions run `29653014405` and re-verified without rebuilding by run `29673871654` at commit `44d19063`.

## Evidence

- The verify-only run used `build_candidate=false`; its `build` job was skipped and it recorded source run `29653014405`.
- GitHub Actions verified the archive, ran the original `wineboot -u` command, compiled and ran the repository's 32-bit WoW64 fixture, and created a GitHub artifact attestation. The Wineboot result is historical only because the command could resolve the same-named Unix launcher.
- The archive SHA-256 is `17350ac54792d3e404c85fc560740a957b55552895ef2d73960a5d1551b46d8f`.
- A local Apple-silicon Rosetta run used a new temporary `WINEPREFIX`; Wine/WoW64 execution completed, but the graphics dependency gate described below did not pass. No Whisky Bottle was read or changed.
- The archive provenance records Wine `wine-11.0` at `db11d0fe6a169c457e23d007e20404643d067aa8`, upstream DXVK `v3.0.1`, and MoltenVK `v1.4.1`. Upstream DXVK 3.0.1 was later rejected for this backend because MoltenVK does not expose its required Vulkan feature set.

## First-prefix fix

Wine's `wine.inf` registers `mscoree.dll` on a clean prefix. In Wine 11, that registration synchronously invokes the interactive Mono downloader when no Mono MSI is bundled. CI therefore stalled in `control.exe appwiz.cpl install_mono` before `wineboot` could complete. The verify commands now scope `WINEDLLOVERRIDES="mscoree,mshtml="` to `wineboot` only. The override is not persisted in a prefix and is not used for the 32-bit sample.

## Wineboot executable-name correction

The runtime's `bin/wineboot` is a symlink to the Unix Wine launcher. Passing the bare `wineboot` name to `wine64` could initialize a prefix, then log `invalid .so library` while trying to load that Mach-O launcher as a Windows module, and still return success. Application, migration, local verification, and CI commands now use `wineboot.exe`. Verification also rejects any `invalid .so library` diagnostic even when the process status is zero.

## Remaining graphics limitation

This candidate is **not a self-contained graphics runtime release**. Local Rosetta logs show that Wine 11's `win32u.so` cannot load `libvulkan.1.dylib`; FreeType and GnuTLS report the same dynamic-library class of warning. The files are present and have the correct x86_64 architecture.

The cause is reproducible: Wine 11 calls `dlopen(SONAME_LIBVULKAN, RTLD_NOW)` with the bare name `libvulkan.1.dylib`, while Wine strips `DYLD_*` variables before its Windows processes start. `DYLD_FALLBACK_LIBRARY_PATH`, `DYLD_LIBRARY_PATH`, and `DYLD_INSERT_LIBRARIES` therefore do not provide a safe bundled-library resolution path for this candidate.

Do not publish or select this historical runtime as a DXVK/MoltenVK graphics default. It may remain an unsigned, provenance-recorded Wine/WoW64 input for further engineering. The current no-rebuild route replaces upstream DXVK with pinned DXVK-macOS, repairs the extracted dependency closure, regenerates provenance and hashes, and then repeats the static, Rosetta, WoW64, and graphics gates. A new Wine build is justified only if that repackage route proves that a required loader path cannot be repaired outside Wine's compiled modules.
