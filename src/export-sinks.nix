/**
  Anchor ID: IMP_ANCHOR_EXPORT_SINKS
  Materializes sinks from collected exports by applying merge strategies.

  Takes `collectExports` output and produces usable Nix values (modules or
  attrsets) by merging contributions according to their strategies.

  Export sinks are "push-based" composition: feature modules declare where
  their config should land, and consumers import the merged sink instead of
  listing every feature explicitly.

  # Merge Strategies

  * `merge`: Deep merge via `lib.recursiveUpdate` (last wins for primitives)
  * `override`: Last writer completely replaces earlier values
  * `list-append`: Concatenate lists (errors on non-lists)
  * `mkMerge`: Module functions become `{ imports = [...]; }`;
    plain attrsets use `lib.mkMerge`

  Strategy resolution:
  * explicit per-export `strategy` wins
  * otherwise first matching `sinkDefaults` pattern wins
  * otherwise falls back to `override`

  Strategy analysis (sorting, effective strategy selection, invalid/conflict
  diagnostics) is shared with output building through `record-strategies.nix`.

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

  * `lib` (attrset): nixpkgs lib for merge operations.
  * `collected` (attrset): Output from `collectExports`.
  * `sinkDefaults` (attrset): Glob patterns to default strategies (e.g., `{ "nixos.*" = "merge"; }`).
  * `enableDebug` (bool): Include `__meta` with contributor info (default: true).
*/
{
  lib,
  collected ? { },
  sinkDefaults ? { },
  enableDebug ? true,
}:
let
  recordStrategies = import ./record-strategies.nix { inherit lib; };
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
      resolveStrategy =
        record: if record.strategy != null then record.strategy else findDefaultStrategy sinkKey;
      prepared = recordStrategies.prepare {
        scope = "imp.buildExportSinks";
        subject = "sink '${sinkKey}'";
        records = exportRecords;
        inherit resolveStrategy;
        defaultStrategy = _resolved: "override";
        validStrategies = [
          "merge"
          "override"
          "list-append"
          "mkMerge"
          null
        ];
        formatRecord = record: "  - ${record.source} (strategy: ${toString record.__resolvedStrategy})";
        invalidError = record: "imp.buildExportSinks: invalid strategy in ${record.source}";
        conflictHint = "All exports to the same sink must use compatible strategies.";
      };
      mergedValue =
        let
          initial = initAcc prepared.effectiveStrategy;
        in
        builtins.foldl' (
          acc: record: stepStrategy prepared.effectiveStrategy acc record.value
        ) initial prepared.sorted;
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
        contributors = map (record: record.source) prepared.sorted;
        strategy = prepared.effectiveStrategy;
      };

    in
    if enableDebug then
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
