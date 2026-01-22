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
  scanner = import ./scanner.nix;
  utils = import ./lib.nix;

  # Import a `.nix` file and extract `__inputs` from attrsets only
  importAndExtract =
    path:
    let
      imported = builtins.tryEval (import path);
    in
    if !imported.success then
      null
    else if builtins.isAttrs imported.value then
      utils.extractInputs imported.value
    else
      # Functions are not called - use `__functor` pattern for functions with `__inputs`
      null;

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

  collectInputs =
    pathOrPaths:
    let
      result = scanner.mkScanner {
        extract = importAndExtract;
        processResult =
          acc: path: inputs:
          mergeInputs path acc inputs;
        initial = {
          inputs = { };
          conflicts = [ ];
        };
      } pathOrPaths;

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
