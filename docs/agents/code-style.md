# Code Style

## Nix docstrings

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

## Nushell (or general) scripts

- Header: `#!/usr/bin/env nu` then `# name - brief description`
- Errors: terse, no `Error:` prefix (error make already indicates error)
- Progress: `"name: action"` not `"Running name..."`
- No trivial messages: avoid `"Done"`, `"Finished"`, `"Initialized"`

## Shell output

- No decorative banners (`===`, `---`, ascii art)
- Progress info is fine; completion markers are not
