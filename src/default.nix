/**
  Entry point for imp - directory-based Nix imports.

  This module exports the main imp API including:
  - Chainable filtering and transformation methods
  - Tree building from directory structure
  - Registry for named module discovery
  - Utilities for flake input collection
*/
let
  utils = import ./lib.nix;
  perform = import ./collect.nix;
  inherit (utils) inModuleEval;

  /**
    Scan directories for `__inputs` declarations and collect them.

    Recursively scans .nix files for `__inputs` attribute declarations
    and merges them into a single attrset. Detects conflicts when the
    same input name has different definitions in different files.

    Only attrsets with `__inputs` are collected. For files that need to
    be functions (e.g., to receive `inputs` at runtime), use the `__functor`
    pattern so `__inputs` is accessible without calling the function:

    ```nix
    {
      __inputs.foo.url = "github:foo/bar";
      __functor = _: { inputs, ... }: inputs.foo.lib.something;
    }
    ```

    Accepts either a single path or a list of paths. When given multiple
    paths, all are scanned and merged with conflict detection.

    # Example

    ```nix
    # Single path
    imp.collectInputs ./outputs
    # => { treefmt-nix = { url = "github:numtide/treefmt-nix"; }; }

    # Multiple paths
    imp.collectInputs [ ./outputs ./registry ]
    # => { treefmt-nix = { ... }; nur = { ... }; }
    ```

    # Arguments

    pathOrPaths
    : Directory/file path, or list of paths, to scan for __inputs declarations.
  */
  collectInputs = import ./collect-inputs.nix;

  /**
    Scan directories for `__exports` declarations and collect them.

    Recursively scans .nix files for `__exports` attribute declarations
    and collects them, tracking source paths. Returns an attrset mapping
    sink keys to lists of export records.

    Only attrsets with `__exports` are collected. For functions that need
    to declare exports, use the `__functor` pattern:

    ```nix
    {
      __exports."nixos.role.desktop" = {
        value = { services.pipewire.enable = true; };
        strategy = "merge";
      };
      __functor = _: { inputs, ... }: { __module = ...; };
    }
    ```

    # Example

    ```nix
    imp.collectExports ./registry
    # => {
    #   "nixos.role.desktop" = [
    #     {
    #       source = "/path/to/audio.nix";
    #       value = { services.pipewire.enable = true; };
    #       strategy = "merge";
    #     }
    #   ];
    # }
    ```

    # Arguments

    pathOrPaths
    : Directory/file path, or list of paths, to scan for __exports declarations.
  */
  collectExports = import ./collect-exports.nix;

  /**
    Build export sinks from collected exports.

    Takes collected exports and merges them according to their strategies,
    producing a nested attrset of sinks. Each sink contains merged values
    and metadata about contributors.

    # Example

    ```nix
    buildExportSinks {
      lib = nixpkgs.lib;
      collected = imp.collectExports ./registry;
      sinkDefaults = {
        "nixos.*" = "merge";
        "hm.*" = "merge";
      };
    }
    # => {
    #   nixos.role.desktop = {
    #     __module = { ... };
    #     __meta = { contributors = [...]; strategy = "merge"; };
    #   };
    # }
    ```

    # Arguments

    lib
    : nixpkgs lib for merge operations.

    collected
    : Output from collectExports.

    sinkDefaults
    : Optional attrset mapping glob patterns to default strategies.

    enableDebug
    : Include __meta with contributor info (default: true).
  */
  buildExportSinks = import ./export-sinks.nix;

  /**
    Scan directories for `__host` declarations and collect them.

    Recursively scans .nix files for `__host` attribute declarations
    and collects host configuration metadata.

    # Example

    ```nix
    imp.collectHosts ./registry/hosts
    # => {
    #   desktop = {
    #     __host = { system = "x86_64-linux"; stateVersion = "24.11"; ... };
    #     __source = "/path/to/desktop/default.nix";
    #     config = ./config;
    #   };
    # }
    ```

    # Arguments

    pathOrPaths
    : Directory/file path, or list of paths, to scan for __host declarations.
  */
  collectHosts = import ./collect-hosts.nix;

  /**
    Build nixosConfigurations from collected host declarations.

    Takes host declarations and generates nixosConfigurations attrset.

    # Example

    ```nix
    buildHosts {
      lib = nixpkgs.lib;
      imp = impWithLib;
      hosts = imp.collectHosts ./hosts;
      flakeArgs = { self, inputs, registry, exports, ... };
    }
    # => { desktop = <nixosConfiguration>; vm = <nixosConfiguration>; }
    ```

    # Arguments

    lib
    : nixpkgs lib (must have nixosSystem).

    imp
    : Bound imp instance with lib.

    hosts
    : Output from collectHosts.

    flakeArgs
    : Standard flake args { self, inputs, registry, exports, ... }.

    hostDefaults
    : Default values for host config (optional).
  */
  buildHosts = import ./build-hosts.nix;

  /**
    Scan directories for `__outputs` declarations and collect them.

    Enables self-contained bundles to contribute to multiple flake output types.
    perSystem outputs receive { pkgs, lib, system, ... } at evaluation time.

    # Example

    ```nix
    imp.collectOutputs ./bundles
    # => {
    #   "perSystem.packages.lint" = [
    #     { source = "/lint/default.nix"; value = <function>; strategy = null; }
    #   ];
    #   "perSystem.devShells.default" = [
    #     { source = "/shell.nix"; value = <function>; strategy = "merge"; }
    #   ];
    # }
    ```

    # Arguments

    pathOrPaths
    : Directory/file path, or list of paths, to scan for __outputs declarations.
  */
  collectOutputs = import ./collect-outputs.nix;

  /**
    Build flake outputs from collected __outputs declarations.

    Separates perSystem outputs from flake-level outputs and merges
    contributions according to their strategies.

    # Example

    ```nix
    buildOutputs {
      lib = nixpkgs.lib;
      collected = imp.collectOutputs ./bundles;
    }
    # => {
    #   perSystem = { "packages.lint" = <function>; "devShells.default" = <merged-function>; };
    #   flake = { "overlays.myOverlay" = <value>; };
    # }
    ```

    # Arguments

    lib
    : nixpkgs lib for merge operations.

    collected
    : Output from collectOutputs.
  */
  buildOutputs = import ./build-outputs.nix;

  flakeFormat = import ./format-flake.nix;
  inherit (flakeFormat) formatInputs formatFlake;

  # Registry utilities (requires lib)
  registryModule = import ./registry.nix;

  /**
    Convenience function combining collectInputs and formatFlake.

    Scans a directory for `__inputs` declarations and generates
    complete flake.nix content in one step.

    # Example

    ```nix
    imp.collectAndFormatFlake {
      src = ./outputs;
      coreInputs = { nixpkgs.url = "github:nixos/nixpkgs"; };
      description = "My flake";
    }
    # => "{ description = \"My flake\"; inputs = { ... }; ... }"
    ```

    # Arguments

    src
    : Directory to scan for __inputs declarations.

    coreInputs
    : Core flake inputs attrset (optional).

    description
    : Flake description string (optional).

    outputsFile
    : Path to outputs file (default: "./nix/flake").

    header
    : Header comment for generated file (optional).
  */
  collectAndFormatFlake =
    {
      src,
      coreInputs ? { },
      description ? "",
      outputsFile ? "./nix/flake",
      header ? "/**\n  Auto-generated by imp - DO NOT EDIT\n  Regenerate with: nix run .#imp-flake\n*/",
    }:
    let
      collectedInputs = collectInputs src;
    in
    formatFlake {
      inherit
        description
        coreInputs
        collectedInputs
        outputsFile
        header
        ;
    };

  # Makes imp callable: imp ./path or imp { config, ... }
  functor = self: arg: perform self.__config (if inModuleEval arg then [ ] else arg);

  # The imp builder object - a stateful configuration that produces the API
  callable =
    let
      # Initial configuration state
      initial = {
        api = { };
        mapf = (i: i);
        treef = import;
        filterf = _: true;
        roots = [ ];

        # State functor: receives update function, returns new state with bound API
        __functor =
          config: update:
          let
            updated = update config;
            current = config update;
            boundAPI = builtins.mapAttrs (_: g: g current) updated.api;

            # Import API methods with current state
            apiMethods = import ./api.nix {
              inherit
                config
                update
                updated
                current
                callable
                ;
            };
          in
          boundAPI
          // apiMethods
          // {
            __config = updated;
            __functor = functor;

            # Standalone utilities available on imp object
            inherit
              collectInputs
              collectExports
              buildExportSinks
              collectHosts
              buildHosts
              collectOutputs
              buildOutputs
              formatInputs
              formatFlake
              collectAndFormatFlake
              registryModule
              ;

            # Convenience: build registry with current lib
            # Usage: (imp.withLib lib).registry ./nix
            registry =
              path:
              if updated.lib == null then
                throw "You need to call withLib before using registry."
              else
                (registryModule { lib = updated.lib; }).buildRegistry path;

            # Convenience: collect and build export sinks with current lib
            # Usage: (imp.withLib lib).exportSinks { ... } ./nix
            exportSinks =
              args: pathOrPaths:
              if updated.lib == null then
                throw "You need to call withLib before using exportSinks."
              else
                let
                  collected = collectExports pathOrPaths;
                in
                buildExportSinks (
                  {
                    lib = updated.lib;
                    inherit collected;
                  }
                  // args
                );
          };
      };
    in
    initial (config: config);

in
callable
