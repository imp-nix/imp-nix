# imp-nix

* nix library and flake-parts module for automatic imports, implicit drop-in file collecting.
* `git add` new files before `nix flake check`/`nix eval` - untracked files aren't visible to flake evaluation

## architecture map (start here)

Module-level docblocks are the ground truth for subsystem behavior and
invariants. Read and update them when relevant.

Get the file path and read the file in one:
* Command template: `rg -N -C999 "IMP_ANCHOR_<ID>" src`
* `<ID>` values:
  * `ENTRYPOINT` (primary imp entrypoint)
  * `RUNTIME_CORE` (core callable runtime assembly)
  * `API_CHAIN` (chainable API methods)
  * `COLLECT_ENTRY` (collection entrypoint)
  * `COLLECT_ENGINE` (collection implementation)
  * `TREE_ENTRY` (directory tree behavior)
  * `TREE_ENGINE` (tree implementation)
  * `TREE_FRAGMENTS` (fragment directory composition)
  * `CONFIG_TREE` (config tree mapping)
  * `CONFIG_TREE_MERGE` (config tree merge behavior)
  * `REGISTRY` (registry discovery and resolution)
  * `EXPORT_SINKS` (export sink merge strategies)
  * `COLLECT_INPUTS` (input declaration collection)
  * `COLLECT_OUTPUTS` (output declaration collection)
  * `COLLECT_EXPORTS` (export declaration collection)
  * `COLLECT_HOSTS` (host declaration collection)
  * `BUILD_OUTPUTS` (output materialization)
  * `BUILD_HOSTS` (host to nixosConfiguration build)
  * `FLAKE_MODULE` (flake-parts integration)
  * `OPTIONS_SCHEMA` (imp module options schema)
  * `FLAKE_FORMAT` (flake.nix formatting/generation)
  * `SCANNER` (shared recursive scanner)
  * `BUNDLES_ENTRY` (bundle utilities entrypoint)
  * `BUNDLES_MODULE` (bundle utilities implementation)
  * `BUNDLES_CONFIG` (bundle config collection)
  * `LIB_UTILS` (shared internal utility primitives)

## code style

* Nix docstrings: use `/**` (not `/*` or `#`) for module/function docs parsed by tooling.
* Nushell/scripts:
  * Header: `#!/usr/bin/env nu` then `# name - brief description`
  * Errors: terse, no `Error:` prefix
  * Progress: `"name: action"` not `"Running name..."`
  * Avoid trivial completion messages (`Done`, `Finished`, etc.)
* Shell output:
  * No decorative banners
  * Progress info is fine; completion markers are not

## adding core functionality

Quick checklist after adding an imp feature (for example `__outputs`, `__exports`, `__hosts`):

1. Source files: create `src/collect/collect-*.nix` and `src/build-*.nix` with `/**` docs.
2. Exports: add callable exports and docstrings to `src/default.nix`.
3. Options: add `imp.<feature>` options to `src/flake/options-schema.nix`.
4. Integration: wire into `src/flake/flake-module.nix` (collection/build/mkMerge sections).
5. Fixtures: create `tests/fixtures/collect/<feature>/` test data.
6. Tests: add `tests/<feature>.nix` and include in `tests/default.nix`.
7. Stage new files before eval/tests.
8. Verify:
   * `git add src/ tests/`
   * `nix run .#tests`
   * `nix flake check`
