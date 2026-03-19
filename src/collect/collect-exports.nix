/**
  Anchor ID: IMP_ANCHOR_COLLECT_EXPORTS
  Collects `__exports` declarations from directory trees.

  Recursively scans `.nix` files for `__exports` attributes and collects them
  with source paths for debugging and conflict detection. No nixpkgs dependency.

  Nested attr syntax is flattened through the shared keyed-record collector,
  so `__exports.a.b = ...` and `__exports."a.b" = ...` feed the same
  downstream sink key.

  Static exports sit at the top level. Functor exports (`__functor`) are called
  with stub args to extract declarations; values remain lazy thunks until use.

  # Export Syntax

  Both flat string keys and nested attribute paths work:

  ```nix
  # Flat string keys
  { __exports."sink.name".value = { config = ...; }; }

  # Nested paths (enables static analysis)
  { __exports.sink.name.value = { config = ...; }; }

  # Functor pattern for modules needing inputs
  {
    __inputs = { foo.url = "..."; };
    __functor = _: { inputs, ... }:
      let mod = { ... };
      in { __exports.sink.name.value = mod; __module = mod; };
  }
  ```

  # Arguments

  pathOrPaths
  : Directory, file, or list of paths to scan.
*/
let
  scanner = import ../scanner.nix;
  keyedRecords = import ./keyed-records.nix {
    isLeaf = entry: !builtins.isAttrs entry || entry ? value || entry ? strategy;
  };
  utils = import ../lib.nix;

  isAttrs = builtins.isAttrs;
  isFunction = builtins.isFunction;

  tryFunctorExports =
    value:
    if isAttrs value && value ? __functor then
      let
        innerFn = builtins.tryEval (value.__functor value);
      in
      if innerFn.success && isFunction innerFn.value then
        let
          innerArgs = builtins.tryEval (builtins.functionArgs innerFn.value);
        in
        if innerArgs.success then
          let
            stubArgs = builtins.mapAttrs (name: hasDefault: if hasDefault then null else { }) innerArgs.value;
            result = builtins.tryEval (innerFn.value stubArgs);
          in
          if result.success && isAttrs result.value then utils.extractExports result.value else null
        else
          null
      else if innerFn.success && isAttrs innerFn.value then
        utils.extractExports innerFn.value
      else
        null
    else
      null;

  importAndExtract =
    path:
    let
      imported = builtins.tryEval (import path);
    in
    if !imported.success then
      null
    else if isAttrs imported.value then
      let
        staticExports = utils.extractExports imported.value;
        functorExports = if staticExports == null then tryFunctorExports imported.value else null;
      in
      if staticExports != null then staticExports else functorExports
    else
      null;

  collectExports = scanner.mkScanner {
    extract = importAndExtract;
    processResult =
      acc: path: exports:
      keyedRecords.mergeKeyedRecords acc (keyedRecords.processFileDeclarations path exports);
    initial = { };
  };

in
collectExports
