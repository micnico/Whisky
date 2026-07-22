---
name: whisky-runtime-maintenance
description: Maintain or release Whisky's versioned Wine, DXVK, and MoltenVK runtime on Apple Silicon. Use when changing the runtime build scripts, graphics backend, Bottle runtime migration, GitHub runtime workflow, provenance, archive validation, or optional Game Porting Toolkit integration.
---

# Whisky Runtime Maintenance

Treat `docs/runtime-acceptance.md`, `docs/graphics-runtime-validation.md`, and `docs/graphics-backend-policy.md` as the current acceptance policy. Read the relevant one before changing behavior.

## Runtime changes

1. Build only explicit stable tags and full expected revisions with `scripts/build-wine-runtime.sh`.
2. Keep the generated archive versioned, checksummed, self-contained, and installed atomically under `Runtimes/<id>/Libraries`.
3. Run `scripts/verify-graphics-runtime.sh`, then smoke Wine and a newly compiled 32-bit executable in a clean prefix.
4. Use `.github/workflows/BuildGraphicsRuntime.yml` on an Apple Silicon runner to produce an attested candidate. Do not claim release readiness from a local build alone.
5. On CI failure, inspect the emitted `*.log` tail before changing versions or dependencies; do not guess from an exit code.

## Bottle safety

- Preserve `legacy` for Bottle metadata that predates `runtimeID`.
- Migrate through `Wine.migrateBottle(_:to:)`: stop the old server, copy the full Bottle, smoke `wineboot -u`, and restore the copy on failure.
- Never silently retarget existing Bottles when activating a runtime. Keep a successful migration backup until an explicit cleanup feature exists.

## GPTK boundary

Treat Game Porting Toolkit/D3DMetal as user-installed and opt-in. Do not download, copy, bundle, or distribute Apple binaries. Require a user-selected installation, record the detected version per Bottle, and provide per-Bottle disable/rollback before enabling the path.

## Promotion

Candidates are not releases. Before publishing, require verified archive checksums, GitHub provenance, Wine/WoW64 smoke evidence, a Bottle migration/rollback result, and an explicit publishing authorization. Keep backend compatibility claims narrowly tied to the workload actually run.
