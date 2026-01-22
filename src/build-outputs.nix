/**
  Builds flake outputs from collected `__outputs` declarations.

  Takes output from `collectOutputs` and produces structures suitable for
  flake-parts integration. Separates perSystem outputs (which need per-system
  evaluation) from top-level flake outputs.

  # Example

  ```nix
  buildOutputs {
    lib = nixpkgs.lib;
    collected = {
      "perSystem.packages.lint" = [
        { source = "/lint.nix"; value = { pkgs, ... }: mkLint pkgs; strategy = null; }
      ];
      "perSystem.devShells.default" = [
        { source = "/shell.nix"; value = { pkgs, ... }: { nativeBuildInputs = [...]; }; strategy = "merge"; }
      ];
      "overlays.myOverlay" = [
        { source = "/overlay.nix"; value = final: prev: { ... }; strategy = null; }
      ];
    };
  }
  # => {
  #   perSystem = { "packages.lint" = [...]; "devShells.default" = [...]; };
  #   flake = { "overlays.myOverlay" = [...]; };
  # }
  ```

  # Arguments

  - `lib` (attrset): nixpkgs lib for merge operations.
  - `collected` (attrset): Output from `collectOutputs`.
*/
{
  lib,
  collected ? { },
}:
let
  hasPrefix = lib.hasPrefix;
  removePrefix = lib.removePrefix;
  splitString = lib.splitString;
  setAttrByPath = lib.setAttrByPath;
  recursiveUpdate = lib.recursiveUpdate;

  # Extract deferred functors (evaluated later with real args)
  deferredFunctors = collected.__deferredFunctors or [ ];

  # Remove __deferredFunctors from collected for regular processing
  staticCollected = builtins.removeAttrs collected [ "__deferredFunctors" ];

  # Separate perSystem outputs from flake-level outputs
  partitionOutputs =
    let
      keys = builtins.attrNames staticCollected;
      perSystemKeys = builtins.filter (k: hasPrefix "perSystem." k) keys;
      flakeKeys = builtins.filter (k: !(hasPrefix "perSystem." k)) keys;
    in
    {
      perSystem = builtins.listToAttrs (
        map (k: {
          name = removePrefix "perSystem." k;
          value = staticCollected.${k};
        }) perSystemKeys
      );
      flake = builtins.listToAttrs (
        map (k: {
          name = k;
          value = staticCollected.${k};
        }) flakeKeys
      );
    };

  # Merge output records for a single output path
  mergeOutputRecords =
    outputKey: records:
    let
      sorted = builtins.sort (a: b: a.source < b.source) records;

      # Determine effective strategy
      strategies = map (r: r.strategy) sorted;
      explicitStrategies = builtins.filter (s: s != null) strategies;
      uniqueStrategies = lib.unique explicitStrategies;

      hasConflict = builtins.length uniqueStrategies > 1;

      effectiveStrategy =
        if uniqueStrategies != [ ] then
          builtins.head uniqueStrategies
        else
        # Default: merge for multiple contributors, override for single
        if builtins.length records > 1 then
          "merge"
        else
          "override";

      conflictError =
        let
          strategyInfo = map (r: "  - ${r.source} (strategy: ${toString r.strategy})") sorted;
        in
        ''
          imp.buildOutputs: conflicting strategies for output '${outputKey}'
          Contributors:
          ${builtins.concatStringsSep "\n" strategyInfo}

          All contributions to the same output must use compatible strategies.
        '';

      # Apply merge strategy
      mergedValue =
        if effectiveStrategy == "override" then
          (lib.last sorted).value
        else if effectiveStrategy == "merge" then
          # For merge, we need to combine the values
          # Values might be functions (for perSystem) - we'll wrap them
          let
            values = map (r: r.value) sorted;
            allFunctions = builtins.all builtins.isFunction values;
          in
          if allFunctions then
            # Return a function that merges results
            args: builtins.foldl' (acc: fn: recursiveUpdate acc (fn args)) { } values
          else if builtins.all lib.isAttrs values then
            builtins.foldl' recursiveUpdate { } values
          else
            # Can't merge non-attrsets, use last
            lib.last values
        else
          (lib.last sorted).value;

    in
    if hasConflict then throw conflictError else mergedValue;

  # Build the final structure
  partitioned = partitionOutputs;

  buildSection =
    section: builtins.mapAttrs (outputKey: records: mergeOutputRecords outputKey records) section;

in
{
  perSystem = buildSection partitioned.perSystem;
  flake = buildSection partitioned.flake;
  inherit deferredFunctors;
}
