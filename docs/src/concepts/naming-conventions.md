# Naming Conventions

imp translates filesystem paths to Nix attributes. The rules are simple but worth knowing.

| Path              | Attribute   | Notes                          |
| ----------------- | ----------- | ------------------------------ |
| `foo.nix`         | `foo`       | File becomes attribute         |
| `foo/default.nix` | `foo`       | Directory with default.nix     |
| `foo_.nix`        | `foo`       | Trailing `_` is stripped       |
| `_foo.nix`        | _(ignored)_ | Leading `_` hides files        |
| `foo.d/`          | `foo`       | Fragment directory (see below) |

## Directory modules

A directory containing `default.nix` is treated as a single unit. imp imports the `default.nix` and stops; sibling files in that directory are not imported or represented as attributes. They can still be imported by `default.nix` itself using relative paths, giving you a clean external interface while keeping implementation details private.

## Hidden files

Anything starting with `_` is ignored. This covers both files (`_helpers.nix`) and directories (`_internal/`). Use this for helpers that shouldn't be auto-imported, work in progress, or templates meant to be copied rather than evaluated.

## Escaping reserved names

Trailing `_` is stripped from attribute names: `default_.nix` becomes `default`, `import_.nix` becomes `import`. This lets you create attributes that would otherwise conflict with Nix keywords or builtins.

## The `__path` attribute

Directories without `default.nix` include a special `__path` attribute pointing to the directory itself:

```nix
registry.modules.nixos          # Attrset with children + __path
registry.modules.nixos.__path   # Path to the directory
registry.modules.nixos.base     # Path to base.nix
```

When you pass an attrset to `imp`, it checks for `__path` and imports from that directory: `(imp registry.modules.nixos)` recursively imports everything under `registry/modules/nixos/`.

## Fragment directories

Directories ending in `.d` follow the Unix convention (like `conf.d`, `init.d`). Files inside are merged into a single attrset using `lib.recursiveUpdate`. If both `foo.nix` and `foo.d/` exist, they are merged together (base file first, then fragments on top).

For `.d` directories containing shell scripts or other non-`.nix` files, use `imp.fragments`.

See [Fragment Directories](./fragment-directories.md) for details.

## Collision detection

If multiple entries resolve to the same attribute name, imp throws an error:

```
imp.tree: collision for attribute 'foo' from multiple sources: /path/foo.nix, /path/foo/default.nix
```

The `.d` suffix is NOT a collision - `foo.d/` explicitly merges with `foo.nix` or `foo/`.
