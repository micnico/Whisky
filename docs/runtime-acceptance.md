# Runtime acceptance

Publish a runtime only when its archive, manifest, provenance, Developer ID signature, and smoke-test record are available together. Do not overwrite the legacy runtime or make an unverified archive the default.

`scripts/build-wine-runtime.sh` builds either `arm64` (the default) or `x86_64` Wine from official source, records the exact revision and host architecture in `Libraries/WhiskyWineProvenance.plist`, then writes the archive, checksum file, and client manifest. The `x86_64` build must run in an Intel Homebrew environment and enables Wine's `i386,x86_64` WoW64 PE mode; on Apple silicon it runs through Rosetta. The optional CrossOver 26.3 FOSS source route is pinned to its official archive SHA-256 and is x86_64-only because its D3DMetal bridge targets the Rosetta Wine ABI.

```sh
scripts/build-wine-runtime.sh \
  --wine-tag wine-11.0 \
  --archive-url https://example.invalid/runtimes/wine-11.0-arm64.tar.gz
```

Pass both `--dxvk-tag` and `--moltenvk-tag` to build the opt-in DXVK + MoltenVK candidate. Pass the matching full `--wine-revision`, `--dxvk-revision`, and `--moltenvk-revision` values to fail the build if a tag no longer resolves to the reviewed commit. The build records the revisions and writes `WhiskyWineBinaries.sha256`; validate its archive with `scripts/verify-graphics-runtime.sh` before publishing.

For the CrossOver route, first run `Build Graphics Runtime Candidate` with `wine_distribution=crossover`, `architecture=x86_64`, `configure_preflight=true`, and `build_candidate=false`. This downloads and verifies the public source bundle, runs the same dependency closure check used by a build, configures Wine, and compiles targeted `win32u` and `winemac` probes. Those probes cover the bundled Vulkan loader path, MSync, the native macOS OpenGL framework used by WineD3D, and the D3DMetal bridge without compiling the full runtime. Wine's generic `No OpenGL library` configure warning refers to the optional X11/GLX driver; the preflight separately proves the native `winemac.drv` OpenGL path. A full build remains a separate explicit action. CrossOver candidates use a distinct `cx-26.3-wine-11.0-…` runtime ID and record `wineDistribution=crossover` plus `wineSourceArchiveSHA256`; they never include CrossOver's proprietary application code or Apple binaries.

Candidates without the `architecture` field in `WhiskyWineProvenance.plist` are intentionally rejected. Rebuild them with the current script; do not retag or rename an older archive.

## Manifest

Publish `WhiskyWineVersion.plist` with these fields. `archiveURL` must use HTTPS and `sha256` is the lowercase SHA-256 digest of the exact archive bytes.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>id</key><string>wine-11.0-arm64</string>
    <key>version</key>
    <dict>
        <key>major</key><integer>11</integer>
        <key>minor</key><integer>0</integer>
        <key>patch</key><integer>0</integer>
        <key>preRelease</key><string></string>
        <key>build</key><string></string>
    </dict>
    <key>archiveURL</key><string>https://releases.example.invalid/runtimes/wine-11.0-arm64.tar.gz</string>
    <key>sha256</key><string>64 lowercase hexadecimal characters</string>
</dict>
</plist>
```

Keep the archive's top-level `Libraries` directory. A versioned release must also include `Libraries/Wine/bin/wine64` and `Libraries/WhiskyWineVersion.plist`; every symlink must resolve within `Libraries`. The client checks its digest, archive paths, and link containment before activation, installs it under `Runtimes/<id>/Libraries`, and leaves the previously active runtime available for rollback.

For a candidate built by `Build Graphics Runtime Candidate`, download the archive and verify its GitHub provenance before the normal archive checks:

```sh
gh attestation verify wine-11.0-dxvk-moltenvk-arm64.tar.gz \
  -R OWNER/REPOSITORY \
  --signer-workflow OWNER/REPOSITORY/.github/workflows/BuildGraphicsRuntime.yml
```

Replace `arm64` with `x86_64` for that candidate architecture. The workflow attests the archive, its SHA-256 file, and the client manifest together. This proves the candidate's GitHub Actions origin; the client still enforces the manifest digest at install time. It does not make an unsigned runtime releasable.

Run the Apple-silicon Rosetta gate separately, using a fresh directory outside the Whisky application data:

```sh
scripts/verify-x86-runtime-on-apple-silicon.sh \
  --archive wine-11.0-dxvk-moltenvk-x86_64.tar.gz \
  --workdir /private/tmp/whisky-wine11-rosetta-smoke
```

The script first performs the static archive checks, then runs Wine bootstrap, WoW64, and Metal/Vulkan/D3D11 as independent phases with separate temporary prefixes. Pass `--phase wineboot`, `--phase wow64`, or `--phase graphics` to rerun only one layer. The graphics phase requires a real Metal device, uses `VK_DRIVER_FILES`, runs a native Vulkan/MoltenVK probe, and then executes both x64 and x86 D3D11 fixtures with the archive's matching DXVK DLLs. Its bootstrap command temporarily disables `mscoree` and `mshtml`: Wine's clean-prefix registration would otherwise invoke the interactive Mono/Gecko downloader when those add-ons are absent. The script does not create, modify, or migrate a Whisky Bottle, and leaves its work directory and per-phase logs for inspection.

Test a user-obtained GPTK/D3DMetal installation separately with the CrossOver Wine candidate:

```sh
scripts/verify-x86-runtime-on-apple-silicon.sh \
  --archive cx-26.3-wine-11.0-dxvk-moltenvk-x86_64.tar.gz \
  --workdir /private/tmp/whisky-wine11-d3dmetal-smoke \
  --phase d3dmetal \
  --d3dmetal-root "/path/to/Evaluation environment for Windows games 4.0 beta 1"
```

This phase validates the four x64 PE DLLs and the x86_64 support libraries, creates a new temporary prefix, links its four `system32` graphics entries to the user-owned files in place, and runs x64 D3D11 and D3D12 device-creation fixtures. It never copies those Apple files into the runtime, repository, or temporary prefix. Removing the selected installation leaves broken links rather than hidden copies; selecting WineD3D or DXVK replaces those links with the bound runtime's own files.

## Verify an existing build artifact without rebuilding Wine

When a candidate's build job succeeded but its verification job failed, manually run `Build Graphics Runtime Candidate` with `build_candidate=false` and `source_artifact_run_id` set to the original Actions run ID. The workflow downloads that run's `wine-graphics-runtime-build-output` artifact, records the source run ID beside the verification output, and runs only the archive and executable checks. For a runtime-only dependency repair, additionally set `repackage_candidate=true`; this may add and relink bundled libraries but never invokes `scripts/build-wine-runtime.sh`. Set `source_artifact_signed=true` only when the original artifact used a valid Developer ID Application signature; signed artifacts must be rebuilt rather than modified after signing.

If Wine did not build but `graphics-preflight` succeeded, set `dxvk_artifact_run_id` to that run when retrying. The new run skips DXVK compilation, downloads the named `dxvk-macos-preflight` artifact from the same repository, and still runs `verify-dxvk-macos-output.sh` against the pinned tag and revision before Wine uses it. Do not use this input when explicitly requesting a fresh `graphics_preflight`.

Every distributed runtime needs a `Developer ID Application` signature and any required notarization. To enable that release gate, configure `WHISKY_RUNTIME_SIGNING_P12_BASE64` (a base64-encoded Developer ID `.p12`, including its private key) and `WHISKY_RUNTIME_SIGNING_P12_PASSWORD`. The workflow imports that identity into an ephemeral runner keychain, signs every Mach-O file before calculating runtime file hashes, verifies Developer ID authority, and runs the Wine/WoW64 smoke test.

Without those secrets, the workflow produces an attestable **unsigned candidate** that must not be published. The native `arm64` candidate records an explicitly skipped executable smoke test because current system policy blocks its unsigned Wine helpers. The `x86_64` candidate is built and smoke-tested on an Intel runner, then requires a separate Rosetta regression on Apple silicon before it may be accepted. Notarize the final release archive or enclosing app as required by the intended distribution path.

## Bottle migration

Runtime selection is per Bottle. Metadata written by older Whisky releases has no `runtimeID`, so it is treated as `legacy`; activating a new runtime never silently changes an existing Bottle. New Bottles record the runtime that was active when they were created. Move a Bottle only after its backup and compatibility smoke test succeed, and keep the legacy runtime until every migrated Bottle has been validated.

## Required record

For every runtime release, record the source revisions and licenses for Wine, DXVK/DXMT/vkd3d, MoltenVK, and any Apple-provided components. Do not redistribute proprietary CrossOver code or Apple binaries unless their license explicitly permits the chosen distribution.

Use a stable Wine release for the default channel; development releases require a separate opt-in channel. Treat Game Porting Toolkit/D3DMetal as a user-installed optional component until its exact download license has been reviewed for this distribution. Do not add it to a public runtime archive. The engineering integration binds a user-selected installation and detected version to the Bottle, never copies Apple binaries, and keeps WineD3D and DXVK rollback explicit.

The backend-specific distribution and test gates are in [graphics-backend-policy.md](graphics-backend-policy.md).

## Smoke tests

Run and record these tests before making a manifest public:

1. Install the archive into a clean Whisky profile, then confirm `wine64 --version`.
2. Create a Windows 10 Bottle and run a 32-bit Windows executable in it.
3. Open an existing legacy Bottle, then activate and roll back the new runtime.
4. Test one D3D11 workload and one D3D12 workload using the chosen graphics backend.
5. Verify Steam or another supported launcher can install, update, and start once.

Treat a failed workload as compatibility data: keep the release available only behind an explicit opt-in until a regression is understood.
