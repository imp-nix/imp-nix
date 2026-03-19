/**
  Anchor ID: IMP_ANCHOR_RECORD_STRATEGIES
  Shared strategy resolution helpers for merging dotted-key record buckets.

  Used by `build-outputs.nix` and `export-sinks.nix`.

  Separates the common "strategy analysis" phase from the
  feature-specific "apply merge" phase:
  * source-order sorting
  * effective strategy resolution
  * invalid-strategy validation
  * conflict detection and standardized diagnostics

  Callers still own the actual merge handlers for each supported strategy.
*/
{
  lib,
}:
let
  prepare =
    {
      scope,
      subject,
      records,
      resolveStrategy ? record: record.strategy,
      defaultStrategy,
      validStrategies ? null,
      formatRecord ? record: "  - ${record.source} (strategy: ${toString record.__resolvedStrategy})",
      conflictHint ? null,
      invalidError ? record: "${scope}: invalid strategy in ${record.source}",
    }:
    let
      sorted = builtins.sort (a: b: a.source < b.source) records;
      resolved = map (record: record // { __resolvedStrategy = resolveStrategy record; }) sorted;
      invalidRecords =
        if validStrategies == null then
          [ ]
        else
          builtins.filter (record: !builtins.elem record.__resolvedStrategy validStrategies) resolved;
      strategies = map (record: record.__resolvedStrategy) resolved;
      explicitStrategies = builtins.filter (strategy: strategy != null) strategies;
      uniqueStrategies = lib.unique explicitStrategies;
      hasConflict = builtins.length uniqueStrategies > 1;
      effectiveStrategy =
        if uniqueStrategies != [ ] then builtins.head uniqueStrategies else defaultStrategy resolved;
      conflictLines = map formatRecord resolved;
      conflictHintText = if conflictHint == null then "" else "\n\n${conflictHint}";
      conflictError = ''
        ${scope}: conflicting strategies for ${subject}
        Contributors:
        ${builtins.concatStringsSep "\n" conflictLines}${conflictHintText}
      '';
    in
    if invalidRecords != [ ] then
      throw (invalidError (builtins.head invalidRecords))
    else if hasConflict then
      throw conflictError
    else
      {
        inherit
          effectiveStrategy
          resolved
          sorted
          ;
      };

  merge =
    args@{
      handlers,
      ...
    }:
    let
      state = prepare (builtins.removeAttrs args [ "handlers" ]);
      handler =
        handlers.${state.effectiveStrategy}
          or (throw "${args.scope}: unsupported strategy '${state.effectiveStrategy}' for ${args.subject}");
    in
    handler state;
in
{
  inherit
    merge
    prepare
    ;
}
