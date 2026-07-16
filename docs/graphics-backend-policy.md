# Graphics backend policy

The default runtime is plain Wine. A graphics backend is opt-in until its exact source revisions, licenses, and workload results are recorded with its runtime release.

| Backend | APIs | Distribution policy | Status |
| --- | --- | --- | --- |
| WineD3D | Wine-provided Direct3D | Included with Wine | Default fallback |
| DXVK + MoltenVK | D3D8-11 via Vulkan/Metal | May be built from source after recording DXVK's zlib and MoltenVK's Apache-2.0 notices | Candidate |
| DXMT | D3D10-11 via Metal | May be built from source after LGPL-2.1 obligations and Wine 11 compatibility are verified | Candidate |
| Apple D3DMetal / GPTK | Apple evaluation environment | Never bundle, host, or redistribute | User-installed only; no auto-integration yet |

[Game Porting Toolkit 4](https://developer.apple.com/games/game-porting-toolkit/) is currently documented by Apple as an evaluation environment for running Windows games on Apple silicon, not as a stable bundled dependency for third-party compatibility layers. Whisky therefore does not claim GPTK support merely because a Bottle has legacy D3DMetal-related environment variables.

The GPTK/D3DMetal path requires an end user to obtain the matching package directly from Apple and accept its terms. Whisky must neither download it on the user's behalf nor place it in a public runtime archive. Before adding an optional integration, the implementation must: require a user-selected installation directory, record the detected version per Bottle, avoid copying Apple binaries, verify the exact required files without guessing a system path, and provide a per-Bottle disable/rollback path. Review the package terms and the current [Apple Developer Program License Agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/) for the intended distribution before enabling that UI.

Before enabling any backend for a Bottle, verify that the selected runtime contains its required libraries and that the Bottle has passed a backup-and-restore smoke test. Keep `legacy` selected for a Bottle unless migration was explicit; runtime activation alone must not migrate Bottle metadata.

## Release gate

For every non-WineD3D backend, publish alongside the runtime archive:

1. Source URLs, immutable revisions, license texts, and SHA-256 hashes for every shipped binary.
2. Exact DLL overrides and host library search paths used by the backend.
3. One D3D11 and one D3D12 test result, plus a 32-bit executable check in a 64-bit Bottle.
4. A rollback result: switch the Bottle to `legacy`, start once, and confirm its prefix still opens.

Do not present a backend as generally compatible from a single game result. Failed workloads remain recorded compatibility data and keep the backend opt-in.
