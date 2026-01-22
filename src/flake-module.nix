/**
  Flake-parts module for imp.

  Automatically loads flake outputs from a directory structure.
  Directory structure maps directly to flake-parts options:

    outputs/
      perSystem/           -> perSystem options (receives pkgs, system, etc.)
        packages.nix       -> perSystem.packages
        apps.nix           -> perSystem.apps
        devShells.nix      -> perSystem.devShells
      nixosConfigurations/ -> flake.nixosConfigurations
      overlays.nix         -> flake.overlays
      systems.nix          -> systems (list of supported systems)

  Files receive standardized arguments matching flake-parts conventions:
    - perSystem files: { pkgs, lib, system, self, self', inputs, inputs', config, ... }
    - flake files: { lib, self, inputs, config, ... }
*/
{
  lib,
  flake-parts-lib,
  config,
  inputs,
  self,
  ...
}:
let
  inherit (lib)
    mkOption
    types
    filterAttrs
    ;

  inherit (flake-parts-lib) mkPerSystemOption;

  impLib = import ./.;
  utils = import ./lib.nix;
  registryLib = import ./registry.nix { inherit lib; };

  cfg = config.imp;

  # Build the registry from configured sources
  registry =
    if cfg.registry.src == null then
      { }
    else
      let
        autoRegistry = registryLib.buildRegistry cfg.registry.src;
      in
      lib.recursiveUpdate autoRegistry cfg.registry.modules;

  # Bound imp instance with lib for passing to modules
  imp = impLib.withLib lib;

  buildTree =
    dir: args:
    if builtins.pathExists dir then impLib.treeWith lib (utils.applyIfCallable args) dir else { };

  # Reserved directory/file names that have special handling
  isSpecialEntry = name: name == cfg.perSystemDir || name == "systems";

  # Use nixpkgs lib when available (has nixosSystem, etc.), fallback to flake-parts lib
  # This ensures lib.nixosSystem works in output files
  nixpkgsLib = inputs.nixpkgs.lib or lib;

  # Standard flake-level args (mirrors flake-parts module args)
  flakeArgs = {
    lib = nixpkgsLib;
    inherit
      self
      inputs
      config
      imp
      ;
    # Allow access to top-level options for introspection
    inherit (config) systems;
    ${cfg.registry.name} = registry;
    # Export sinks for direct access (avoids self.exports circular dependency)
    exports = exportSinks;
  }
  // cfg.args;

  # Get flake-level outputs (everything except special entries)
  flakeTree =
    if cfg.src == null then
      { }
    else
      let
        fullTree = buildTree cfg.src flakeArgs;
      in
      filterAttrs (name: _: !isSpecialEntry name) fullTree;

  # Check for systems.nix in src directory
  systemsFile = cfg.src + "/systems.nix";
  hasSystemsFile = cfg.src != null && builtins.pathExists systemsFile;
  systemsFromFile =
    if hasSystemsFile then utils.applyIfCallable flakeArgs (import systemsFile) else null;

  # Export sinks configuration (defined early for inclusion in flakeArgs)
  exportsCfg = cfg.exports;

  # Determine sources for export scanning
  exportSources =
    if exportsCfg.sources != [ ] then
      exportsCfg.sources
    else
      builtins.filter (p: p != null) [
        cfg.registry.src
        cfg.src
      ];

  # Build export sinks if enabled
  exportSinks =
    if exportsCfg.enable && exportSources != [ ] then
      let
        collected = impLib.collectExports exportSources;
      in
      impLib.buildExportSinks {
        inherit lib;
        inherit collected;
        sinkDefaults = exportsCfg.sinkDefaults;
        enableDebug = exportsCfg.enableDebug;
      }
    else
      { };

  # Flake file generation
  flakeFileCfg = cfg.flakeFile;

  # Collect inputs from both outputs dir and registry dir
  inputSources = builtins.filter (p: p != null) [
    cfg.src
    cfg.registry.src
  ];
  collectedInputs =
    if flakeFileCfg.enable && inputSources != [ ] then impLib.collectInputs inputSources else { };

  generatedFlakeContent =
    if flakeFileCfg.enable then
      impLib.formatFlake {
        inherit (flakeFileCfg)
          description
          coreInputs
          outputsFile
          header
          submodules
          ;
        inherit collectedInputs;
      }
    else
      "";

  # Host generation configuration
  hostsCfg = cfg.hosts;

  # Determine sources for host scanning
  hostSources =
    if hostsCfg.sources != [ ] then
      hostsCfg.sources
    else if cfg.registry.src != null then
      [ cfg.registry.src ]
    else
      [ ];

  # Collect and build hosts if enabled
  collectedHosts =
    if hostsCfg.enable && hostSources != [ ] then impLib.collectHosts hostSources else { };

  generatedNixosConfigurations =
    if hostsCfg.enable && collectedHosts != { } then
      impLib.buildHosts {
        lib = nixpkgsLib;
        inherit imp;
        hosts = collectedHosts;
        inherit flakeArgs;
        hostDefaults = hostsCfg.defaults;
      }
    else
      { };

in
{
  # Use shared options schema for imp.* options
  imports = [ ./options-schema.nix ];

  # Add perSystem-specific options
  options.perSystem = mkPerSystemOption (
    { lib, ... }:
    {
      options.imp = {
        args = mkOption {
          type = types.attrsOf types.unspecified;
          default = { };
          description = "Extra per-system arguments passed to imported files.";
        };
      };
    }
  );

  config = lib.mkMerge [
    # Override flakeFile.path default with actual self path
    {
      imp.flakeFile.path = lib.mkDefault (self + "/flake.nix");
    }
    # Systems from file (if present)
    (lib.mkIf (systemsFromFile != null) {
      systems = lib.mkDefault systemsFromFile;
    })

    # Main imp config
    (lib.mkIf (cfg.src != null) {
      flake = flakeTree;

      perSystem =
        {
          pkgs,
          system,
          self',
          inputs',
          config,
          ...
        }:
        let
          perSystemPath = cfg.src + "/${cfg.perSystemDir}";
          perSystemArgs = {
            inherit
              lib
              pkgs
              system
              self
              self'
              inputs
              inputs'
              imp
              ;
            ${cfg.registry.name} = registry;
          }
          // cfg.args
          // config.imp.args;

          rawOutputs = buildTree perSystemPath perSystemArgs;

          /**
            Auto-detect formatter.d/ and build treefmt wrapper.

            If formatter.d/ exists without a formatter.nix, fragments are collected
            and wrapped with treefmt-nix. treefmt-nix is sourced from imp's inputs
            (inputs.imp.inputs.treefmt-nix) or the consumer's direct inputs.
          */
          formatterDPath = perSystemPath + "/formatter.d";
          formatterNixPath = perSystemPath + "/formatter.nix";
          hasFormatterD = builtins.pathExists formatterDPath;
          hasFormatterNix = builtins.pathExists formatterNixPath;

          formatterOutput =
            if hasFormatterD && !hasFormatterNix then
              let
                treefmt-nix =
                  inputs.imp.inputs.treefmt-nix or inputs.treefmt-nix
                    or (throw "formatter.d requires treefmt-nix input (available via inputs.imp.inputs.treefmt-nix)");
                fragments = imp.fragmentsWith perSystemArgs formatterDPath;
                merged = lib.recursiveUpdate { projectRootFile = "flake.nix"; } fragments.asAttrs;
              in
              {
                formatter = (treefmt-nix.lib.evalModule pkgs merged).config.build.wrapper;
              }
            else
              { };
        in
        rawOutputs // formatterOutput;
    })

    # Flake file generation outputs
    (lib.mkIf flakeFileCfg.enable {
      perSystem =
        { pkgs, ... }:
        {
          /*
            Regenerate flake.nix from __inputs declarations.

            Files can declare inputs inline:

              # With __functor (when file needs args like pkgs, inputs):
              {
                __inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
                __functor = _: { pkgs, inputs, ... }:
                  inputs.treefmt-nix.lib.evalModule pkgs { ... };
              }

              # Without __functor (static data that declares inputs):
              {
                __inputs.foo.url = "github:owner/foo";
                someKey = "value";
              }

            Run: nix run .#imp-flake
          */
          apps.imp-flake = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "imp-flake" ''
                printf '%s' ${lib.escapeShellArg generatedFlakeContent} > flake.nix
                echo "Generated flake.nix"
              ''
            );
            meta.description = "Regenerate flake.nix from __inputs declarations";
          };

          checks.flake-up-to-date =
            pkgs.runCommand "flake-up-to-date"
              {
                expected = generatedFlakeContent;
                actual = builtins.readFile flakeFileCfg.path;
                passAsFile = [
                  "expected"
                  "actual"
                ];
              }
              ''
                if diff -u "$expectedPath" "$actualPath"; then
                  echo "flake.nix is up-to-date"
                  touch $out
                else
                  echo ""
                  echo "ERROR: flake.nix is out of date!"
                  echo "Run 'nix run .#imp-flake' to regenerate it."
                  exit 1
                fi
              '';
        };
    })

    # Export sinks output
    (lib.mkIf (exportsCfg.enable && exportSources != [ ]) {
      /*
        Expose export sinks as flake outputs.

        Modules can declare exports using __exports:

          {
            __exports."nixos.role.desktop" = {
              value = { services.pipewire.enable = true; };
              strategy = "merge";
            };
          }

        These are collected and merged into sinks available at:

          flake.exports.nixos.role.desktop
          flake.exports.hm.role.desktop

        Consumers can then import these sinks:

          { inputs, ... }:
          {
            imports = [ inputs.self.exports.nixos.role.desktop.__module ];
          }
      */
      flake.exports = exportSinks;
    })

    # Registry output
    (lib.mkIf (cfg.registry.src != null) {
      /*
        Expose the registry attrset as a flake output.

        Evaluating `nix eval .#registry` returns the full registry structure,
        making it available to external tools that need to validate registry
        paths without importing the flake's Nix code.

        The output mirrors the in-memory registry: nested attrsets where each
        leaf contains a `__path` attribute pointing to the module file.
      */
      flake.registry = registry;
    })

    # Auto-generated hosts from __host declarations
    (lib.mkIf (hostsCfg.enable && collectedHosts != { }) {
      /*
        Generate nixosConfigurations from __host declarations.

        Files in the registry can declare hosts:

          {
            __host = {
              system = "x86_64-linux";
              stateVersion = "24.11";
              sinks = [ "shared.nixos" "desktop.nixos" ];
              hmSinks = [ "shared.hm" "desktop.hm" ];
              bases = [ "hosts.shared.base" ];
              user = "albert";
            };
            config = ./config;
          }

        These are collected and built into nixosConfigurations automatically.
      */
      flake.nixosConfigurations = generatedNixosConfigurations;
    })
  ];
}
