/**
  Collects __inputs declarations from directory trees.
  Standalone implementation - no nixpkgs dependency, only builtins.

  Scans `.nix` files recursively for `__inputs` attribute declarations and
  merges them, detecting conflicts when the same input name has different
  definitions in different files.

  Note: Only attrsets with `__inputs` are collected. For functions that
  need to declare inputs, use the `__functor` pattern:

  ```nix
  {
    __inputs.foo.url = "github:foo/bar";
    __functor = _: { inputs, ... }: { __module = ...; };
  }
  ```

  # Example

  ```nix
  # Single path
  collectInputs ./nix/outputs
  # => { treefmt-nix = { url = "github:numtide/treefmt-nix"; }; }

  # Multiple paths (merged with conflict detection)
  collectInputs [ ./nix/outputs ./nix/registry ]
  # => { treefmt-nix = { ... }; nur = { ... }; }
  ```

  # Arguments

  pathOrPaths
  : Directory/file path, or list of paths, to scan for __inputs declarations.
*/
let
  # Check if path should be excluded (starts with `_` in basename)
  isExcluded =
    path:
    let
      str = toString path;
      parts = builtins.filter (x: x != "") (builtins.split "/" str);
      basename = builtins.elemAt parts (builtins.length parts - 1);
    in
    builtins.substring 0 1 basename == "_";

  isAttrs = builtins.isAttrs;

  # Safely extract `__inputs`, catching evaluation errors with `tryEval`
  safeExtractInputs =
    value:
    let
      hasIt = builtins.tryEval (isAttrs value && value ? __inputs && isAttrs value.__inputs);
    in
    if hasIt.success && hasIt.value then
      let
        inputs = value.__inputs;
        forced = builtins.tryEval (builtins.deepSeq inputs inputs);
      in
      if forced.success then forced.value else { }
    else
      { };

  # Import a `.nix` file and extract `__inputs` from attrsets only
  importAndExtract =
    path:
    let
      imported = builtins.tryEval (import path);
    in
    if !imported.success then
      { }
    else if isAttrs imported.value then
      safeExtractInputs imported.value
    else
      # Functions are not called - use `__functor` pattern for functions with `__inputs`
      { };

  # Compare two input definitions for equality
  inputsEqual =
    a: b:
    let
      aKeys = builtins.attrNames a;
      bKeys = builtins.attrNames b;
    in
    aKeys == bKeys && builtins.all (k: a.${k} == b.${k}) aKeys;

  # Merge inputs, detecting conflicts between different definitions
  mergeInputs =
    sourcePath: existing: new:
    let
      newNames = builtins.attrNames new;
    in
    builtins.foldl' (
      acc: name:
      if acc.inputs ? ${name} then
        if inputsEqual acc.inputs.${name}.def new.${name} then
          acc
        else
          acc
          // {
            conflicts = acc.conflicts ++ [
              {
                inherit name;
                sources = acc.inputs.${name}.sources ++ [ sourcePath ];
                definitions = [
                  acc.inputs.${name}.def
                  new.${name}
                ];
              }
            ];
          }
      else
        acc
        // {
          inputs = acc.inputs // {
            ${name} = {
              def = new.${name};
              sources = [ sourcePath ];
            };
          };
        }
    ) existing newNames;

  # Process a single `.nix` file
  processFile =
    acc: path:
    let
      inputs = importAndExtract path;
    in
    if inputs == { } then acc else mergeInputs path acc inputs;

  # Process a directory recursively
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

  # Process a path (file or directory)
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

  # Main: accepts path or list of paths
  collectInputs =
    pathOrPaths:
    let
      paths = if builtins.isList pathOrPaths then pathOrPaths else [ pathOrPaths ];

      initial = {
        inputs = { };
        conflicts = [ ];
      };

      result = builtins.foldl' processPath initial paths;

      formatConflict =
        c:
        let
          sourcesStr = builtins.concatStringsSep "\n  - " (map toString c.sources);
          defsStr = builtins.concatStringsSep "\n    " (
            map (d: if d ? url then d.url else builtins.toJSON d) c.definitions
          );
        in
        "input '${c.name}':\n  Sources:\n  - ${sourcesStr}\n  Definitions:\n    ${defsStr}";

      conflictMessages = map formatConflict result.conflicts;
      errorMsg = "imp.collectInputs: conflicting definitions for:\n\n${builtins.concatStringsSep "\n\n" conflictMessages}";
      finalInputs = builtins.mapAttrs (_: v: v.def) result.inputs;
    in
    if result.conflicts != [ ] then throw errorMsg else finalInputs;

in
collectInputs
