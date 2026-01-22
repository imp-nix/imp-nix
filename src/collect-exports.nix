/**
  Collects `__exports` declarations from directory trees.

  Recursively scans `.nix` files for `__exports` attributes and collects them
  with source paths for debugging and conflict detection. No nixpkgs dependency.

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

  safeExtractExports =
    value:
    let
      hasIt = builtins.tryEval (isAttrs value && value ? __exports && isAttrs value.__exports);
    in
    if hasIt.success && hasIt.value then
      let
        exports = value.__exports;
        forced = builtins.tryEval (builtins.deepSeq exports exports);
      in
      if forced.success then forced.value else { }
    else
      { };

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
          if result.success && isAttrs result.value then safeExtractExports result.value else { }
        else
          { }
      else if innerFn.success && isAttrs innerFn.value then
        safeExtractExports innerFn.value
      else
        { }
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
        staticExports = safeExtractExports imported.value;
        functorExports = if staticExports == { } then tryFunctorExports imported.value else { };
      in
      if staticExports != { } then staticExports else functorExports
    else
      { };

  # Leaf exports have `value` or `strategy`; non-leaves are nested containers
  isLeafExport = entry: !isAttrs entry || entry ? value || entry ? strategy;

  normalizeExportEntry =
    sinkKey: entry:
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

  # Flatten nested `__exports.a.b.value` into `"a.b"` sink keys
  flattenExports =
    prefix: exports:
    let
      keys = builtins.attrNames exports;
    in
    builtins.concatMap (
      key:
      let
        entry = exports.${key};
        sinkKey = if prefix == "" then key else "${prefix}.${key}";
      in
      if isLeafExport entry then [ { inherit sinkKey entry; } ] else flattenExports sinkKey entry
    ) keys;

  processFileExports =
    sourcePath: exports:
    let
      flattened = flattenExports "" exports;
    in
    builtins.foldl' (
      acc: item:
      let
        entry = normalizeExportEntry item.sinkKey item.entry;
        exportRecord = {
          source = toString sourcePath;
          inherit (entry) value strategy;
        };
        sinkKey = item.sinkKey;
      in
      acc
      // {
        ${sinkKey} = if acc ? ${sinkKey} then acc.${sinkKey} ++ [ exportRecord ] else [ exportRecord ];
      }
    ) { } flattened;

  mergeExports =
    acc: newExports:
    let
      allKeys = builtins.attrNames acc ++ builtins.attrNames newExports;
      uniqueKeys = builtins.foldl' (
        keys: key: if builtins.elem key keys then keys else keys ++ [ key ]
      ) [ ] allKeys;
    in
    builtins.foldl' (
      result: key:
      result
      // {
        ${key} = (acc.${key} or [ ]) ++ (newExports.${key} or [ ]);
      }
    ) { } uniqueKeys;

  processFile =
    acc: path:
    let
      exports = importAndExtract path;
    in
    if exports == { } then acc else mergeExports acc (processFileExports path exports);

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

  collectExports =
    pathOrPaths:
    let
      paths = if builtins.isList pathOrPaths then pathOrPaths else [ pathOrPaths ];
      result = builtins.foldl' processPath { } paths;
    in
    result;

in
collectExports
