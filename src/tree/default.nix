/**
  Anchor ID: IMP_ANCHOR_TREE_ENTRY
  Entry point for building nested attrsets from directory structure.

  Naming:  `foo.nix` | `foo/default.nix` -> `{ foo = ... }`
           `foo_.nix`                  -> `{ foo = ... }`  (escapes reserved names)
           `_foo.nix` | `_foo/`          -> ignored
           `foo.d/`                      -> fragment directory (merged attrsets)

  Directory modules:
    A directory with `default.nix` is treated as a leaf module. imp imports
    that directory as a single unit and does not recurse into sibling files.
    This gives directories a clean external interface while allowing internal
    helper files to stay private.

  Fragment directories (`*.d/`):
    Any `foo.d/` directory is processed as a fragment directory. The `.nix`
    files inside are imported in sorted order (00-base.nix before 10-extra.nix)
    and combined with `lib.recursiveUpdate`.

    If `foo.d/` contains no valid `.nix` files, it is skipped entirely.
    Non-`.nix` files in `.d` directories (e.g., `.sh` files for shell hooks)
    should be consumed via `imp.fragments` or `imp.fragmentsWith`.

  Merging with base:
    If both `foo.nix` (or `foo/default.nix`) and `foo.d/` exist, they are
    combined: the base is imported first, then `foo.d/*.nix` fragments are
    merged on top using `lib.recursiveUpdate`. This allows a base file to
    define core outputs while fragments add or extend them.

  Collision detection:
    If multiple entries resolve to the same attribute name (e.g., `foo.nix`
    and `foo/default.nix`), an error is thrown. The `.d` suffix is NOT a
    collision - it explicitly merges with the base.

  # Example

  Directory structure:

  ```
  outputs/
    apps.nix
    checks.nix
    packages.d/
      00-core.nix       # { default = ...; foo = ...; }
      10-extras.nix     # { bar = ...; }
  ```

  ```nix
  imp.treeWith lib import ./outputs
  ```

  Returns:

  ```nix
  {
    apps = <imported from apps.nix>;
    checks = <imported from checks.nix>;
    packages = { default = ...; foo = ...; bar = ...; };  # merged
  }
  ```

  # Usage

  ```nix
  (imp.withLib lib).tree ./outputs
  ```

  Or with transform:

  ```nix
  ((imp.withLib lib).mapTree (f: f args)).tree ./outputs
  imp.treeWith lib (f: f args) ./outputs
  ```
*/
import ./build-tree.nix
