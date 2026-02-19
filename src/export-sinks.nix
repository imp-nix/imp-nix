/**
  Materializes sinks from collected exports by applying merge strategies.

  Takes `collectExports` output and produces usable Nix values (modules or
  attrsets) by merging contributions according to their strategies.

  Export sinks are "push-based" composition: feature modules declare where
  their config should land, and consumers import the merged sink instead of
  listing every feature explicitly.

  # Merge Strategies

  - `merge`: Deep merge via `lib.recursiveUpdate` (last wins for primitives)
  - `override`: Last writer completely replaces earlier values
  - `list-append`: Concatenate lists (errors on non-lists)
  - `mkMerge`: Module functions become `{ imports = [...]; }`;
    plain attrsets use `lib.mkMerge`

  Strategy resolution:
  - explicit per-export `strategy` wins
  - otherwise first matching `sinkDefaults` pattern wins
  - otherwise falls back to `override`

  # Example

  ```nix
  buildExportSinks {
    lib = nixpkgs.lib;
    collected = {
      "nixos.role.desktop" = [
        { source = "/audio.nix"; value = { services.pipewire.enable = true; }; strategy = "merge"; }
        { source = "/wayland.nix"; value = { services.greetd.enable = true; }; strategy = "merge"; }
      ];
    };
    sinkDefaults = { "nixos.*" = "merge"; };
  }
  # => { nixos.role.desktop = { __module = { ... }; __meta = { ... }; }; }
  ```

  # Arguments

  - `lib` (attrset): nixpkgs lib for merge operations.
  - `collected` (attrset): Output from `collectExports`.
  - `sinkDefaults` (attrset): Glob patterns to default strategies (e.g., `{ "nixos.*" = "merge"; }`).
  - `enableDebug` (bool): Include `__meta` with contributor info (default: true).
*/
{
  lib,
  collected ? { },
  sinkDefaults ? { },
  enableDebug ? true,
}:
let
  matchesPattern =
    pattern: key:
    let
      prefix =
        if lib.hasSuffix ".*" pattern then
          lib.removeSuffix "*" pattern
        else if lib.hasSuffix "*" pattern then
          lib.removeSuffix "*" pattern
        else
          pattern;
      hasGlob = lib.hasSuffix "*" pattern;
    in
    if hasGlob then lib.hasPrefix prefix key else key == pattern;

  findDefaultStrategy =
    sinkKey:
    let
      patterns = builtins.attrNames sinkDefaults;
      matching = builtins.filter (p: matchesPattern p sinkKey) patterns;
    in
    if matching != [ ] then sinkDefaults.${builtins.head matching} else null;

  isValidStrategy =
    s:
    builtins.elem s [
      "merge"
      "override"
      "list-append"
      "mkMerge"
      null
    ];

  # Strategy-specific initial accumulator
  initAcc =
    strategy:
    if strategy == "override" || strategy == null then
      { __empty = true; }
    else if strategy == "merge" then
      { }
    else if strategy == "list-append" then
      [ ]
    else if strategy == "mkMerge" then
      {
        __mkMerge = true;
        values = [ ];
      }
    else
      throw "Unknown merge strategy: ${strategy}";

  # Strategy-specific merge step with type validation
  stepStrategy =
    strategy: existing: new:
    if strategy == "override" || strategy == null then
      new
    else if strategy == "merge" then
      if !lib.isAttrs new then
        throw "merge strategy requires attrset values, got: ${builtins.typeOf new}"
      else
        lib.recursiveUpdate existing new
    else if strategy == "list-append" then
      if !builtins.isList new then
        throw "list-append strategy requires list values, got: ${builtins.typeOf new}"
      else
        existing ++ new
    else if strategy == "mkMerge" then
      {
        __mkMerge = true;
        values = existing.values ++ [ new ];
      }
    else
      throw "Unknown merge strategy: ${strategy}";

  buildSink =
    sinkKey: exportRecords:
    let
      sorted = builtins.sort (a: b: a.source < b.source) exportRecords;

      withStrategies = map (
        record:
        let
          effectiveStrategy =
            if record.strategy != null then record.strategy else findDefaultStrategy sinkKey;
        in
        record // { effectiveStrategy = effectiveStrategy; }
      ) sorted;

      invalidStrategies = builtins.filter (r: !isValidStrategy r.effectiveStrategy) withStrategies;

      strategies = map (r: r.effectiveStrategy) withStrategies;
      uniqueStrategies = lib.unique (builtins.filter (s: s != null) strategies);
      hasConflict = builtins.length uniqueStrategies > 1;

      conflictError =
        let
          strategyInfo = map (
            r: "  - ${r.source} (strategy: ${toString r.effectiveStrategy})"
          ) withStrategies;
        in
        ''
          imp.buildExportSinks: conflicting strategies for sink '${sinkKey}'
          Contributors:
          ${builtins.concatStringsSep "\n" strategyInfo}

          All exports to the same sink must use compatible strategies.
        '';

      mergedValue =
        let
          strategy = if uniqueStrategies != [ ] then builtins.head uniqueStrategies else "override";
          initial = initAcc strategy;
        in
        builtins.foldl' (acc: record: stepStrategy strategy acc record.value) initial withStrategies;

      finalValue =
        if mergedValue ? __mkMerge then
          let
            values = mergedValue.values;
            allFunctions = builtins.all builtins.isFunction values;
          in
          if allFunctions then { imports = values; } else lib.mkMerge values
        else if mergedValue ? __empty then
          { }
        else
          mergedValue;

      meta = {
        contributors = map (r: r.source) sorted;
        strategy = if uniqueStrategies != [ ] then builtins.head uniqueStrategies else "override";
      };

    in
    if invalidStrategies != [ ] then
      throw "imp.buildExportSinks: invalid strategy in ${(builtins.head invalidStrategies).source}"
    else if hasConflict then
      throw conflictError
    else if enableDebug then
      {
        __module = finalValue;
        __meta = meta;
      }
    else
      finalValue;

  sinks =
    let
      sinkKeys = builtins.attrNames collected;
    in
    builtins.foldl' (
      acc: sinkKey:
      let
        parts = lib.splitString "." sinkKey;
        value = buildSink sinkKey collected.${sinkKey};
      in
      lib.recursiveUpdate acc (lib.setAttrByPath parts value)
    ) { } sinkKeys;

in
sinks
