# Wine 11 x86_64 candidate verification record

Date: 2026-07-19

This record covers the Wine 11 x86_64 graphics candidate built by GitHub Actions run `29653014405` and re-verified without rebuilding by run `29673871654` at commit `44d19063`.

## Evidence

- The verify-only run used `build_candidate=false`; its `build` job was skipped and it recorded source run `29653014405`.
- GitHub Actions verified the archive, ran `wineboot -u`, compiled and ran the repository's 32-bit WoW64 fixture, and created a GitHub artifact attestation.
- The archive SHA-256 is `17350ac54792d3e404c85fc560740a957b55552895ef2d73960a5d1551b46d8f`.
- A local Apple-silicon Rosetta run of `scripts/verify-x86-runtime-on-apple-silicon.sh` passed against the same archive in a new temporary `WINEPREFIX`; no Whisky Bottle was read or changed.
- The archive provenance records Wine `wine-11.0` at `db11d0fe6a169c457e23d007e20404643d067aa8`, DXVK `v3.0.1`, and MoltenVK `v1.4.1`.

## First-prefix fix

Wine's `wine.inf` registers `mscoree.dll` on a clean prefix. In Wine 11, that registration synchronously invokes the interactive Mono downloader when no Mono MSI is bundled. CI therefore stalled in `control.exe appwiz.cpl install_mono` before `wineboot` could complete. The verify commands now scope `WINEDLLOVERRIDES="mscoree,mshtml="` to `wineboot` only. The override is not persisted in a prefix and is not used for the 32-bit sample.

## Remaining graphics limitation

This candidate is **not a self-contained graphics runtime release**. Local Rosetta logs show that Wine 11's `win32u.so` cannot load `libvulkan.1.dylib`; FreeType and GnuTLS report the same dynamic-library class of warning. The files are present and have the correct x86_64 architecture.

The cause is reproducible: Wine 11 calls `dlopen(SONAME_LIBVULKAN, RTLD_NOW)` with the bare name `libvulkan.1.dylib`, while Wine strips `DYLD_*` variables before its Windows processes start. `DYLD_FALLBACK_LIBRARY_PATH`, `DYLD_LIBRARY_PATH`, and `DYLD_INSERT_LIBRARIES` therefore do not provide a safe bundled-library resolution path for this candidate.

Do not publish or select this runtime as a DXVK/MoltenVK graphics default. It may remain an unsigned, provenance-recorded Wine/WoW64 candidate for further engineering. The safe no-rebuild action is to keep the legacy runtime/graphics backend selected for existing Bottles. A release-grade graphics fix requires a later Wine build that resolves the Vulkan loader and bundled dependencies from a runtime-internal path, followed by the same verify-only and Rosetta gates.
