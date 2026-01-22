# Docs

Documentation source for imp, built with mdbook and [imp.docgen](https://github.com/imp-nix/imp.docgen).

## Development

```sh
nix run .#docs        # serve with live reload
nix run .#build-docs  # build to ./docs/book
```

Both commands regenerate `src/reference/methods.md` and `src/reference/options.md` before building, so edits to source doc-comments appear immediately.

## Generation

docgen produces three types of reference documentation from a manifest (`manifest.nix`):

`methods.md` extracts function documentation from `/** ... */` doc-comments using nixdoc. The manifest lists which files to process and optionally filters to specific exports:

```nix
methods.sections = [
  { file = "api.nix"; }
  { file = "default.nix"; heading = "Standalone"; exports = [ "collectInputs" ]; }
];
```

`options.md` renders NixOS-style module options. The options module (`src/options-schema.nix`) is evaluated, converted to JSON via `docgen.lib.optionsToJson`, then formatted by nixdoc's `options` subcommand.

`files.md` extracts file-level doc-comments (the `# comment` block at the top of a file before any code). Useful for describing what each file does at a glance.

## Configuration

Docs are configured via `src/flakeModules/docs.nix`, which is imported by `flake.nix`:

```nix
imp.docs = {
  manifest = ./docs/manifest.nix;
  srcDir = ./src;
  siteDir = ./docs;
  name = "imp";
  anchorPrefix = "imp";
  optionsModule = ./src/options-schema.nix;
  optionsPrefix = "imp.";
};
```

This produces the `docs` package, `docs` app (serve), and `build-docs` app.

## Writing doc-comments

Function documentation follows nixdoc's format:

````nix
{
  /**
    Short description on first line.

    Longer explanation if needed.

    # Arguments

    - `arg1` (type): What it does
    - `arg2` (type): What it does

    # Example

    ```nix
    myFn "foo" { bar = true; }
    => { result = "foo"; bar = true; }
    ```
  */
  myFn = arg1: arg2: { ... };
}
````

File-level comments go before any code:

```nix
# Brief description of what this file provides.
#
# Additional context if needed.
{ lib }:
{ ... }
```
