/**
  Anchor ID: IMP_ANCHOR_COLLECT_OUTPUTS
  Collects `__outputs` declarations from directory trees.

  Scans `.nix` files for `__outputs` attributes targeting flake output paths.
  Enables self-contained bundles to contribute to multiple output types.

  Nested attr syntax is flattened through the shared keyed-record collector,
  so `__outputs.a.b = ...` and `__outputs."a.b" = ...` feed the same
  downstream output key.

  # Output Syntax

  ```nix
  # Nested paths (preferred for tooling/static analysis)
  {
    __outputs.perSystem.packages.lint = { pkgs, ... }: pkgs.hello;
  }

  # Flat string key form also works
  {
    __outputs."perSystem.packages.lint" = { pkgs, ... }: pkgs.hello;
  }

  # perSystem outputs (receive { pkgs, lib, system, ... })
  {
    __outputs.perSystem.packages.lint = { pkgs, ... }: pkgs.writeShellScript "lint" "...";
    __outputs.perSystem.devShells.default = {
      value = { pkgs, ... }: { buildInputs = [ ... ]; };
      strategy = "merge";
    };
  }

  # post-merge perSystem transforms (run on final merged output section)
  {
    __outputs.perSystemTransforms.devShells = finalShells:
      finalShells;
  }

  # perSystem-arg builder form for transforms (preferred for shell wrapping)
  {
    __outputs.perSystemTransforms.devShells = imp.mkWorkspaceShellTransform {
        workspace = "my-workspace";
        aliases = [ "default" ];
        packages = [ pkgs.cargo-edit ];
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

  * `merge`: Deep merge via `lib.recursiveUpdate` (default for attrset outputs)
  * `override`: Last writer wins (default for non-attrset outputs)

  For `__outputs.perSystemTransforms.*` specifically:
  * `merge` and `pipe` compose transforms in source-path order
  * `override` keeps only the last transform contributor

  Function-valued files are collected as deferred functors and evaluated later
  with full flake/perSystem args, so collection stays static while execution
  remains context-aware.

  # Arguments

  pathOrPaths
  : Directory, file, or list of paths to scan.
*/
let
  scanner = import ../scanner.nix;
  keyedRecords = import ./keyed-records.nix {
    isLeaf =
      entry: !builtins.isAttrs entry || entry ? value || entry ? strategy || builtins.isFunction entry;
  };
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

  collectOutputs = scanner.mkScanner {
    extract = importAndExtract;
    processResult =
      acc: path: result:
      if result ? __deferredFunctor then
        # Store deferred functors separately for later evaluation
        acc // { __deferredFunctors = (acc.__deferredFunctors or [ ]) ++ [ result.__deferredFunctor ]; }
      else
        keyedRecords.mergeKeyedRecords acc (keyedRecords.processFileDeclarations path result.outputs);
    initial = { };
  };

in
collectOutputs
