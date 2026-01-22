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
  isAttrs = builtins.isAttrs;
  isFunction = builtins.isFunction;

  isExcluded =
    path:
    let
      str = toString path;
      parts = builtins.filter (x: x != "") (builtins.split "/" str);
      basename = builtins.elemAt parts (builtins.length parts - 1);
    in
    builtins.substring 0 1 basename == "_";

  safeExtractOutputs =
    value:
    let
      hasIt = builtins.tryEval (isAttrs value && value ? __outputs && isAttrs value.__outputs);
    in
    if hasIt.success && hasIt.value then
      let
        outputs = value.__outputs;
        forced = builtins.tryEval (builtins.deepSeq (builtins.attrNames outputs) outputs);
      in
      if forced.success then forced.value else { }
    else
      { };

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
      { };

  importAndExtract =
    path:
    let
      imported = builtins.tryEval (import path);
    in
    if !imported.success then
      { }
    else if isAttrs imported.value then
      let
        staticOutputs = safeExtractOutputs imported.value;
        deferredOutputs = if staticOutputs == { } then tryDeferredOutputs imported.value path else { };
      in
      if staticOutputs != { } then staticOutputs else deferredOutputs
    else if isFunction imported.value then
      # Plain function - defer for later evaluation
      tryDeferredOutputs imported.value path
    else
      { };

  # Leaf outputs have `value` or `strategy`, or are functions/non-attrsets
  isLeafOutput =
    entry: !isAttrs entry || entry ? value || entry ? strategy || isFunction entry;

  normalizeOutputEntry =
    entry:
    if isAttrs entry && entry ? value then
      {
        value = entry.value;
        strategy = entry.strategy or null;
      }
    else
      {
        value = entry;
        strategy = null;
      };

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
        entry = normalizeOutputEntry item.entry;
        outputRecord = {
          source = toString sourcePath;
          inherit (entry) value strategy;
        };
        outputKey = item.outputKey;
      in
      acc
      // {
        ${outputKey} = if acc ? ${outputKey} then acc.${outputKey} ++ [ outputRecord ] else [ outputRecord ];
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

  processFile =
    acc: path:
    let
      outputs = importAndExtract path;
    in
    if outputs == { } then
      acc
    else if outputs ? __deferredFunctor then
      # Store deferred functors separately for later evaluation
      acc // { __deferredFunctors = (acc.__deferredFunctors or [ ]) ++ [ outputs.__deferredFunctor ]; }
    else
      mergeOutputs acc (processFileOutputs path outputs);

  processDir =
    acc: path:
    let
      entries = builtins.readDir path;
      names = builtins.attrNames entries;

      process =
        acc: name:
        let
          entryPath = path + "/${name}";
          entryType = entries.${name};
          resolvedType = if entryType == "symlink" then builtins.readFileType entryPath else entryType;
        in
        if isExcluded entryPath then
          acc
        else if resolvedType == "regular" && builtins.match ".*\\.nix" name != null then
          processFile acc entryPath
        else if resolvedType == "directory" then
          let
            defaultPath = entryPath + "/default.nix";
            hasDefault = builtins.pathExists defaultPath;
          in
          if hasDefault then processFile acc defaultPath else processDir acc entryPath
        else
          acc;
    in
    builtins.foldl' process acc names;

  processPath =
    acc: path:
    let
      rawPathType = builtins.readFileType path;
      pathType = if rawPathType == "symlink" then builtins.readFileType path else rawPathType;
    in
    if pathType == "regular" then
      processFile acc path
    else if pathType == "directory" then
      processDir acc path
    else
      acc;

  collectOutputs =
    pathOrPaths:
    let
      paths = if builtins.isList pathOrPaths then pathOrPaths else [ pathOrPaths ];
      result = builtins.foldl' processPath { } paths;
    in
    result;

in
collectOutputs
