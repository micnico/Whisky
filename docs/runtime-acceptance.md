# Runtime acceptance

Publish a runtime only when its archive, manifest, provenance, and smoke-test record are available together. Do not overwrite the legacy runtime or make an unverified archive the default.

Build the base ARM64 Wine runtime with `scripts/build-wine-runtime.sh`. It accepts only a stable Wine tag, clones the official WineHQ source, records its exact revision in `Libraries/WhiskyWineProvenance.plist`, then writes the archive, checksum file, and client manifest. It requires Homebrew `bison`, `llvm`, and `lld`.

```sh
scripts/build-wine-runtime.sh \
  --wine-tag wine-11.0 \
  --archive-url https://example.invalid/runtimes/wine-11.0-arm64.tar.gz
```

Pass both `--dxvk-tag` and `--moltenvk-tag` to build the opt-in DXVK + MoltenVK candidate. Pass the matching full `--wine-revision`, `--dxvk-revision`, and `--moltenvk-revision` values to fail the build if a tag no longer resolves to the reviewed commit. The build records the revisions and writes `WhiskyWineBinaries.sha256`; validate its archive with `scripts/verify-graphics-runtime.sh` before publishing.

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
gh attestation verify wine-11.0-dxvk-moltenvk-arm64.tar.gz -R OWNER/REPOSITORY
```

The workflow attests the archive, its SHA-256 file, and the client manifest together. This proves the candidate's GitHub Actions origin; the client still enforces the manifest digest at install time.

## Bottle migration

Runtime selection is per Bottle. Metadata written by older Whisky releases has no `runtimeID`, so it is treated as `legacy`; activating a new runtime never silently changes an existing Bottle. New Bottles record the runtime that was active when they were created. Move a Bottle only after its backup and compatibility smoke test succeed, and keep the legacy runtime until every migrated Bottle has been validated.

## Required record

For every runtime release, record the source revisions and licenses for Wine, DXVK/DXMT/vkd3d, MoltenVK, and any Apple-provided components. Do not redistribute proprietary CrossOver code or Apple binaries unless their license explicitly permits the chosen distribution.

Use a stable Wine release for the default channel; development releases require a separate opt-in channel. Treat Game Porting Toolkit/D3DMetal as a user-installed optional component until its exact download license has been reviewed for this distribution. Do not add it to a public runtime archive by default. An eventual optional integration must bind a user-selected installation and detected version to the Bottle, never copy Apple binaries, and make disable/rollback explicit.

The backend-specific distribution and test gates are in [graphics-backend-policy.md](graphics-backend-policy.md).

## Smoke tests

Run and record these tests before making a manifest public:

1. Install the archive into a clean Whisky profile, then confirm `wine64 --version`.
2. Create a Windows 10 Bottle and run a 32-bit Windows executable in it.
3. Open an existing legacy Bottle, then activate and roll back the new runtime.
4. Test one D3D11 workload and one D3D12 workload using the chosen graphics backend.
5. Verify Steam or another supported launcher can install, update, and start once.

Treat a failed workload as compatibility data: keep the release available only behind an explicit opt-in until a regression is understood.
