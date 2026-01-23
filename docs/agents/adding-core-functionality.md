# Adding Core Functionality

Quick checklist after implementing new imp features (e.g., `__outputs`, `__exports`, `__hosts`).

## Implementation

1. Source files - Create `src/collect/collect-*.nix` and `src/build-*.nix` with `/**` docstrings
2. Exports - Add to `src/default.nix` callable exports and docstrings
3. Options - Add `imp.<feature>` options to `src/flake/options-schema.nix`
4. Integration - Wire into `src/flake/flake-module.nix` (collection, building, mkMerge sections)

## Testing

5. Fixtures - Create `tests/fixtures/collect/<feature>/` with test data
6. Tests - Create `tests/<feature>.nix`, add to `tests/default.nix`
7. git add - Stage new files before running `nix run .#tests`

## Documentation

08. Manifest - Update `docs/manifest.nix`:
    - Add files to `files.sections`
    - Add exports to `methods.sections`
09. Concept doc - Create `docs/src/concepts/<feature>.md` if needed
10. SUMMARY.md - Add concept doc to `docs/src/SUMMARY.md` navigation

## Verify

```bash
git add src/ tests/ docs/
nix run .#tests
nix flake check
nix build .#docs
```
