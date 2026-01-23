/**
  Collects `__outputs` declarations from directory trees.

  Scans `.nix` files for `__outputs` attributes targeting flake output paths.
  Enables self-contained bundles to contribute to multiple output types.

  # Output Syntax

  ```nix
  # perSystem outputs (receive { pkgs, lib, system, ... })
  {
    __outputs.perSystem.packages.lint = { pkgs, ... }: pkgs.writeShellScript "lint" "...";
    __outputs.perSystem.devShells.default = {
      value = { pkgs, ... }: { buildInputs = [ ... ]; };
      strategy = "merge";
    };
  }

  # Top-level outputs
  {
    __outputs.overlays.myOverlay = final: prev: { ... };
  }

  # Functor pattern for outputs needing inputs
  {
    __inputs.foo.url = "github:owner/foo";
    __functor = _: { inputs, ... }: {
      __outputs.perSystem.packages.bar = { pkgs, ... }:
        inputs.foo.packages.${pkgs.system}.default;
    };
  }
  ```

  # Merge Strategies

  - `merge`: Deep merge via `lib.recursiveUpdate` (default for attrset outputs)
  - `override`: Last writer wins (default for non-attrset outputs)

  # Arguments

  pathOrPaths
  : Directory, file, or list of paths to scan.
*/
let
  scanner = import ../scanner.nix;
  utils = import ../lib.nix;

  isAttrs = builtins.isAttrs;
  isFunction = builtins.isFunction;

  /**
    For files that are functions or have __functor, return a special marker.
    The function will be evaluated later at build time with real args.
  */
  tryDeferredOutputs =
    value: path:
    if isAttrs value && value ? __functor then
      {
        __deferredFunctor = {
          functor = value;
          isFunctor = true;
          source = toString path;
        };
      }
    else if isFunction value then
      {
        __deferredFunctor = {
          functor = value;
          isFunctor = false;
          source = toString path;
        };
      }
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
        staticOutputs = utils.extractOutputs imported.value;
        deferredOutputs = if staticOutputs == null then tryDeferredOutputs imported.value path else null;
      in
      if staticOutputs != null then
        { outputs = staticOutputs; }
      else if deferredOutputs != null then
        deferredOutputs
      else
        null
    else if isFunction imported.value then
      # Plain function - defer for later evaluation
      tryDeferredOutputs imported.value path
    else
      null;

  # Leaf outputs have `value` or `strategy`, or are functions/non-attrsets
  isLeafOutput = entry: !isAttrs entry || entry ? value || entry ? strategy || isFunction entry;

  # Flatten nested `__outputs.perSystem.packages.foo` into `"perSystem.packages.foo"` keys
  flattenOutputs =
    prefix: outputs:
    let
      keys = builtins.attrNames outputs;
    in
    builtins.concatMap (
      key:
      let
        entry = outputs.${key};
        outputKey = if prefix == "" then key else "${prefix}.${key}";
      in
      if isLeafOutput entry then [ { inherit outputKey entry; } ] else flattenOutputs outputKey entry
    ) keys;

  processFileOutputs =
    sourcePath: outputs:
    let
      flattened = flattenOutputs "" outputs;
    in
    builtins.foldl' (
      acc: item:
      let
        entry = utils.normalizeValueStrategy item.entry;
        outputRecord = {
          source = toString sourcePath;
          inherit (entry) value strategy;
        };
        outputKey = item.outputKey;
      in
      acc
      // {
        ${outputKey} =
          if acc ? ${outputKey} then acc.${outputKey} ++ [ outputRecord ] else [ outputRecord ];
      }
    ) { } flattened;

  mergeOutputs =
    acc: newOutputs:
    let
      allKeys = builtins.attrNames acc ++ builtins.attrNames newOutputs;
      uniqueKeys = builtins.foldl' (
        keys: key: if builtins.elem key keys then keys else keys ++ [ key ]
      ) [ ] allKeys;
    in
    builtins.foldl' (
      result: key:
      result
      // {
        ${key} = (acc.${key} or [ ]) ++ (newOutputs.${key} or [ ]);
      }
    ) { } uniqueKeys;

  collectOutputs = scanner.mkScanner {
    extract = importAndExtract;
    processResult =
      acc: path: result:
      if result ? __deferredFunctor then
        # Store deferred functors separately for later evaluation
        acc // { __deferredFunctors = (acc.__deferredFunctors or [ ]) ++ [ result.__deferredFunctor ]; }
      else
        mergeOutputs acc (processFileOutputs path result.outputs);
    initial = { };
  };

in
collectOutputs
