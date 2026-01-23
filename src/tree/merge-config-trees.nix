/**
  Merges multiple config trees into a single NixOS/Home Manager module.

  Supports two merge strategies:

  - `override` (default): Later trees override earlier (`lib.recursiveUpdate`)
  - `merge`: Use module system's `mkMerge` for proper option merging

  This enables composable features where one extends another:

  ```
  features/
    shell/programs/{zsh,starship}.nix    # base shell config
    devShell/programs/{git,zsh}.nix      # extends shell, overrides zsh
  ```

  # Usage

  Override strategy (default):

  ```nix
  # devShell/default.nix
  { imp, ... }:
  {
    imports = [
      (imp.mergeConfigTrees [ ../shell ./. ])
    ];
  }
  ```

  Or with merge strategy for concatenating list options:

  ```nix
  { imp, ... }:
  {
    imports = [
      (imp.mergeConfigTrees { strategy = "merge"; } [ ../shell ./. ])
    ];
  }
  ```

  With `override`: later values completely replace earlier ones.
  With `merge`: options combine according to module system rules:

  - lists concatenate
  - strings may error (use `mkForce`/`mkDefault` to control)
  - nested attrs merge recursively
*/
{
  lib,
  filterf,
  extraArgs ? { },
  strategy ? "override",
}:
let
  buildConfigTree = import ./config-tree.nix { inherit lib filterf extraArgs; };

  mergeTrees =
    paths:
    {
      config,
      lib,
      pkgs,
      ...
    }@moduleArgs:
    let
      # Build each tree's config
      configs = map (path: (buildConfigTree path moduleArgs).config) paths;

      # Merge based on strategy
      merged =
        if strategy == "merge" then
          # Use mkMerge for proper module system semantics
          lib.mkMerge configs
        else
          # Default: recursiveUpdate, later overrides earlier
          lib.foldl' lib.recursiveUpdate { } configs;
    in
    {
      config = merged;
    };
in
mergeTrees
