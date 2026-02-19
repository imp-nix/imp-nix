# imp-nix

* nix library and flake-parts module for automatic imports, implicit drop-in file collecting.
* `git add` new files before `nix flake check`/`nix eval` - untracked files aren't visible to flake evaluation

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
