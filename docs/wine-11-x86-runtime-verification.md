# Wine 11 x86_64 candidate verification record

Date: 2026-07-19

Status: historical rejected candidate. It is not evidence that the current self-contained graphics gate passed.

This record covers the Wine 11 x86_64 graphics candidate built by GitHub Actions run `29653014405` and re-verified without rebuilding by run `29673871654` at commit `44d19063`.

## Evidence

- The verify-only run used `build_candidate=false`; its `build` job was skipped and it recorded source run `29653014405`.
- GitHub Actions verified the archive, ran `wineboot -u`, compiled and ran the repository's 32-bit WoW64 fixture, and created a GitHub artifact attestation.
- The archive SHA-256 is `17350ac54792d3e404c85fc560740a957b55552895ef2d73960a5d1551b46d8f`.
- A local Apple-silicon Rosetta run used a new temporary `WINEPREFIX`; Wine/WoW64 execution completed, but the graphics dependency gate described below did not pass. No Whisky Bottle was read or changed.
- The archive provenance records Wine `wine-11.0` at `db11d0fe6a169c457e23d007e20404643d067aa8`, upstream DXVK `v3.0.1`, and MoltenVK `v1.4.1`. Upstream DXVK 3.0.1 was later rejected for this backend because MoltenVK does not expose its required Vulkan feature set.

## First-prefix fix

Wine's `wine.inf` registers `mscoree.dll` on a clean prefix. In Wine 11, that registration synchronously invokes the interactive Mono downloader when no Mono MSI is bundled. CI therefore stalled in `control.exe appwiz.cpl install_mono` before `wineboot` could complete. The verify commands now scope `WINEDLLOVERRIDES="mscoree,mshtml="` to `wineboot` only. The override is not persisted in a prefix and is not used for the 32-bit sample.

## Remaining graphics limitation

This candidate is **not a self-contained graphics runtime release**. Local Rosetta logs show that Wine 11's `win32u.so` cannot load `libvulkan.1.dylib`; FreeType and GnuTLS report the same dynamic-library class of warning. The files are present and have the correct x86_64 architecture.

The cause is reproducible: Wine 11 calls `dlopen(SONAME_LIBVULKAN, RTLD_NOW)` with the bare name `libvulkan.1.dylib`, while Wine strips `DYLD_*` variables before its Windows processes start. `DYLD_FALLBACK_LIBRARY_PATH`, `DYLD_LIBRARY_PATH`, and `DYLD_INSERT_LIBRARIES` therefore do not provide a safe bundled-library resolution path for this candidate.

Do not publish or select this historical runtime as a DXVK/MoltenVK graphics default. It may remain an unsigned, provenance-recorded Wine/WoW64 input for further engineering. The current no-rebuild route replaces upstream DXVK with pinned DXVK-macOS, repairs the extracted dependency closure, regenerates provenance and hashes, and then repeats the static, Rosetta, WoW64, and graphics gates. A new Wine build is justified only if that repackage route proves that a required loader path cannot be repaired outside Wine's compiled modules.
