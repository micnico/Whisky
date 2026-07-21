# Wine 11 x86_64 candidate verification record

Date: 2026-07-21

Status: retain the current unpublished engineering candidate as an explicit opt-in. It passed the self-contained runtime, Wineboot, basic WoW64, local Apple-silicon graphics, application-integration, and provenance gates. A real 32-bit WinSCP GUI regression remains open, so the candidate is not the default runtime or a general compatibility release.

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

On 2026-07-21, the locally built Whisky application created a new `Wine 11 Smoke` Bottle bound to `wine-11.0-dxvk-moltenvk-x86_64`. Application logs recorded `wineboot.exe -u`, Wine 11.0, the bundled Vulkan environment, and DXVK DLL overrides without an invalid Mach-O-as-PE lookup. The application copied byte-identical x64 and x32 DXVK DLLs into the Bottle, and its D3D11 launch reached DXVK and MoltenVK on Apple M4. A direct run of the same fixture in that Bottle returned zero with D3D feature level 11_0.

The full repository verifier was then repeated against the exact accepted archive in `/private/tmp/whisky-wine11-matrix-20260721`. Static verification, Wineboot, the 32-bit WoW64 fixture, native Vulkan/MoltenVK, and DXVK D3D11 all passed. Loading the rebuilt application left the content hash and modification time of all registered Bottle metadata unchanged; runtime selection remained bound to the new test Bottle only.

The real-GUI matrix then ran copied application files only inside the disposable `Wine 11 Smoke` Bottle. 64-bit 7-Zip opened and worked through Whisky; its missing CJK glyphs are a prefix-font limitation rather than a launch failure. WinSCP 6.5 build 16288's 32-bit console frontend also ran, but its GUI exited with status 5 before presenting a window. Wine tracing recorded a Delphi `0x0eedfade` exception followed by `c0000005` and `Exception frame is not in stack limits`. The same executable remained alive for the observation period in a fresh Wine 7.7 prefix, while Gcenx's official macOS Wine 11.0_1 build reproduced the Wine 11 failure. This isolates a Wine 11 new-WoW64/32-bit Delphi compatibility regression rather than a Whisky launcher, DXVK, or locally built runtime defect.

The matrix was extended with current, upstream-published portable applications. Every downloaded archive matched the publisher's SHA-256 before extraction:

| Application | Architecture | Result | Evidence |
| --- | --- | --- | --- |
| WinSCP 6.5.6 portable (`dd91974a...cb3121`) | PE32 i386 | Fail | Exited 5 with the same access-violation/invalid-exception-frame chain |
| WinSCP 6.6.2 RC experimental portable (`d2a8c4ed...7c7348`) | PE32+ x86_64 | Pass | Remained running; `tasklist.exe` reported `WinSCP.exe` through Whisky's `start /unix` path |
| Notepad++ 8.9.6.1 portable (`1f33144b...3aca3f`) | PE32 i386 | Pass | Remained running in a fresh prefix and in `Wine 11 Smoke`; `tasklist.exe` reported `notepad++.exe` through `start /unix` |

The WinSCP project independently documents a Wine report for WinSCP 6.5.3 with the same “Invalid access to memory” class of failure. Its 6.6.2 RC release introduced an experimental 64-bit build, which provides a working compatibility route while the 32-bit Delphi/WoW64 regression remains unresolved. These results show that Wine 11's general 32-bit GUI path works; the WinSCP failure must not be generalized to all WoW64 applications.

This completes the clean-Bottle, Wineboot, basic WoW64, independent 32/64-bit GUI, and D3D11 application-integration gates. The WinSCP 32-bit regression remains recorded rather than hidden by the passing samples. D3D12 and a real launcher or game remain separate compatibility gates and must not be inferred from the D3D11 result.

## Runtime route decision

Keep the provenance-linked Whisky archive as the accepted Wine 11 engineering candidate. Do not replace it with Gcenx Wine 11.0_1: the reference archive (`b50dc50ec7f41d58b115a6b685d4d1315ba3c797bd3aa0f49213f2703cb82388`) reproduces the same WinSCP 32-bit failure and therefore does not provide a compatibility fix. It also does not replace this candidate's verified Whisky-specific DXVK-macOS, MoltenVK, dependency-closure, archive-hash, and provenance work. Continue using Gcenx as an upstream build and regression comparison.

No new Wine build is justified by the current evidence. Repackage the accepted archive for runtime-only dependency repairs, and rebuild Wine only for a reviewed Wine source change or a newer pinned Wine release that needs evaluation.

Wine 11 may become the default only after all of these remaining gates are recorded:

1. A D3D12 workload passes with a separately licensed backend, or D3D12 is explicitly excluded from that release channel.
2. A real supported launcher or game installs, updates, and starts in a disposable Bottle.
3. Upgrade and rollback are repeated on a copy of a legacy Bottle without changing the original.
4. The WinSCP 32-bit regression has either an upstream fix or a documented compatibility route that preserves one-click per-Bottle fallback to Wine 7.
5. Any distributed archive passes the signing and notarization policy in `runtime-acceptance.md`; until then, the exact SHA-256 local import remains the only supported route.

Apple Game Porting Toolkit and D3DMetal remain user-provided optional inputs. They are not present in this archive and must not be downloaded, copied, or redistributed by the project workflow.

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
