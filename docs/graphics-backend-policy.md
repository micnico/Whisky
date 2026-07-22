# Graphics backend policy

The default runtime is plain Wine. A graphics backend is opt-in until its exact source revisions, licenses, and workload results are recorded with its runtime release.

| Backend | APIs | Distribution policy | Status |
| --- | --- | --- | --- |
| WineD3D | Wine-provided Direct3D | Included with Wine | Default fallback |
| DXVK-macOS 1.10.3 + MoltenVK | D3D9-11 via Vulkan/Metal | Build from pinned source and patches; record DXVK's zlib and MoltenVK's Apache-2.0 notices | Candidate |
| DXMT | D3D10-11 via Metal | May be built from source after LGPL-2.1 obligations and Wine 11 compatibility are verified | Candidate |
| Apple D3DMetal / GPTK | Apple evaluation environment | Never bundle, host, or redistribute | User-selected engineering candidate |

[Game Porting Toolkit 4](https://developer.apple.com/games/game-porting-toolkit/) documents an evaluation environment for running an unmodified Windows executable on Apple silicon, now including Metal 4 evaluation. It remains an evaluation and porting tool, not a Whisky runtime distribution dependency. Whisky therefore does not claim GPTK support merely because a Bottle has legacy D3DMetal-related environment variables.

The GPTK/D3DMetal path requires an end user to obtain the matching package directly from Apple and accept its terms. Whisky must neither download it on the user's behalf nor place it in a public runtime archive. Review the package terms and the current [Apple Developer Program License Agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/) for the intended distribution before enabling it for general distribution.

As of 2026-07-22, the engineering UI records an explicit graphics backend and a user-selected D3DMetal directory per Bottle. It validates the four required PE32+ x86-64 DLLs and the D3DMetal framework version in place, without copying Apple binaries. D3DMetal is offered only when the selected runtime provenance says `wineDistribution=crossover` and contains the CrossOver Wine Unix loader. The launch environment binds the selected `libd3dshared.dylib`, framework, and Wine DLL path, while the Bottle's four x64 graphics entries are symbolic links to those user-owned DLLs. Its 64-bit DLLs are paired with the runtime's 32-bit DXVK files when available; WineD3D remains the deterministic restore source for both architectures, including when the external links have become broken.

Metadata without the new backend field decodes as `legacy` and is not rewritten merely by loading the Bottle. Once a user explicitly leaves `legacy`, selecting WineD3D restores the bound runtime's x86_64 and i386 Direct3D DLLs before launch; selecting DXVK restores those DLLs first and then applies both DXVK architectures. The original legacy DXVK flag remains recorded so the schema does not silently reinterpret an old Bottle.

Before enabling any backend for a Bottle, verify that the selected runtime contains its required libraries and that the Bottle has passed a backup-and-restore smoke test. Keep `legacy` selected for a Bottle unless migration was explicit; runtime activation alone must not migrate Bottle metadata.

## Release gate

For every non-WineD3D backend, publish alongside the runtime archive:

1. Source URLs, immutable revisions, license texts, and SHA-256 hashes for every shipped binary.
2. Exact DLL overrides and host library search paths used by the backend.
3. An API-appropriate graphics test result (D3D11 for DXVK/DXMT; D3D12 only for a backend that claims it), plus a 32-bit executable check in a 64-bit Bottle.
4. A rollback result: switch the Bottle to `legacy`, start once, and confirm its prefix still opens.

Do not present a backend as generally compatible from a single game result. Failed workloads remain recorded compatibility data and keep the backend opt-in.
