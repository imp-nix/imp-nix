# imp-nix

Core Nix library and flake-parts module for automatic imports.

## Dev Notes

### File naming

- Source files use kebab-case: `config-tree.nix`, `flake-module.nix`
- Update `docs/manifest.nix` when renaming files (drives docgen)

### Flake gotcha

- `git add` new files before `nix flake check`/`nix eval` - untracked files aren't visible to flake evaluation

### Key behaviors

- `.d` directories: generic, work for any name (no allowlist)
- Collision detection: `foo.nix` + `foo/` throws error; `.d` merges, not collides
- Fragment accessors (`asString`/`asList`/`asAttrs`): type-validated, throw on mismatch

### Docs to update after API changes

- `docs/src/concepts/fragment-directories.md` - .d semantics
- `docs/src/concepts/naming-conventions.md` - collision rules
- `docs/src/reference/methods.md` - method signatures
- `docs/src/reference/files.md` - file descriptions
- Docstrings in `src/*.nix` auto-generate some docs

## Code Style

### Nix docstrings

Use `/**` (not `/*` or `#`) for module/function docs parsed by docgen:

```nix
/**
  Brief description.

  # Arguments

  - `name` (type): What it is

  # Returns

  What it returns.
*/
```

### Nushell (or general) scripts

- Header: `#!/usr/bin/env nu` then `# name - brief description`
- Errors: terse, no `Error:` prefix (error make already indicates error)
- Progress: `"name: action"` not `"Running name..."`
- No trivial messages: avoid `"Done"`, `"Finished"`, `"Initialized"`

### Shell output

- No decorative banners (`===`, `---`, ascii art)
- Progress info is fine; completion markers are not
