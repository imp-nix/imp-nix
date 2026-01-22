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

  registry =
    if cfg.registry.src == null then
      { }
    else
      let
        autoRegistry = registryLib.buildRegistry cfg.registry.src;
      in
      lib.recursiveUpdate autoRegistry cfg.registry.modules;

  imp = impLib.withLib lib;

  buildTree =
    dir: args:
    if builtins.pathExists dir then impLib.treeWith lib (utils.applyIfCallable args) dir else { };

  isSpecialEntry = name: name == cfg.perSystemDir || name == "systems";

  # Prefer nixpkgs lib (has nixosSystem, etc.) over flake-parts lib
  nixpkgsLib = inputs.nixpkgs.lib or lib;

  flakeArgs = {
    lib = nixpkgsLib;
    inherit
      self
      inputs
      config
      imp
      ;
    inherit (config) systems;
    ${cfg.registry.name} = registry;
    exports = exportSinks;
  }
  // cfg.args;

  flakeTree =
    if cfg.src == null then
      { }
    else
      let
        fullTree = buildTree cfg.src flakeArgs;
      in
      filterAttrs (name: _: !isSpecialEntry name) fullTree;

  systemsFile = cfg.src + "/systems.nix";
  hasSystemsFile = cfg.src != null && builtins.pathExists systemsFile;
  systemsFromFile =
    if hasSystemsFile then utils.applyIfCallable flakeArgs (import systemsFile) else null;

  exportsCfg = cfg.exports;

  exportSources =
    if exportsCfg.sources != [ ] then
      exportsCfg.sources
    else
      builtins.filter (p: p != null) [
        cfg.registry.src
        cfg.src
      ];

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

  flakeFileCfg = cfg.flakeFile;

  inputSources = builtins.filter (p: p != null) [
    cfg.src
    cfg.registry.src
    cfg.bundles.src
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

  outputsCfg = cfg.outputs;

  outputSources =
    if outputsCfg.sources != [ ] then
      outputsCfg.sources
    else
      builtins.filter (p: p != null) [
        cfg.registry.src
        cfg.src
        cfg.bundles.src
      ];

  collectedOutputs =
    if outputsCfg.enable && outputSources != [ ] then
      impLib.collectOutputs outputSources
    else
      { };

  builtOutputs =
    if outputsCfg.enable && collectedOutputs != { } then
      impLib.buildOutputs {
        inherit lib;
        collected = collectedOutputs;
      }
    else
      {
        perSystem = { };
        flake = { };
      };

  hostsCfg = cfg.hosts;

  hostSources =
    if hostsCfg.sources != [ ] then
      hostsCfg.sources
    else if cfg.registry.src != null then
      [ cfg.registry.src ]
    else
      [ ];

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
    { imp.flakeFile.path = lib.mkDefault (self + "/flake.nix"); }

    (lib.mkIf (systemsFromFile != null) {
      systems = lib.mkDefault systemsFromFile;
    })

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

          # Formatter excluded: buildTree returns raw attrset, combined section builds wrapper
          filteredOutputs = filterAttrs (k: _: k != "formatter") rawOutputs;
        in
        filteredOutputs;
    })

    # __outputs integration (formatter excluded - combined section handles it)
    (lib.mkIf (outputsCfg.enable && builtOutputs.perSystem != { }) {
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
            exports = exportSinks;
          }
          // cfg.args
          // config.imp.args;

          nonFormatterOutputs = filterAttrs (k: _: k != "formatter") builtOutputs.perSystem;

          evaluatedOutputs = lib.mapAttrs (
            outputPath: value:
            let
              parts = lib.splitString "." outputPath;
              evaluated = if builtins.isFunction value then value perSystemArgs else value;
            in
            lib.setAttrByPath parts evaluated
          ) nonFormatterOutputs;

          merged = lib.foldl' lib.recursiveUpdate { } (lib.attrValues evaluatedOutputs);
        in
        merged;
    })

    (lib.mkIf (outputsCfg.enable && builtOutputs.flake != { }) {
      flake =
        let
          evaluatedOutputs = lib.mapAttrs (
            outputPath: value:
            let
              parts = lib.splitString "." outputPath;
              evaluated = if builtins.isFunction value then value flakeArgs else value;
            in
            lib.setAttrByPath parts evaluated
          ) builtOutputs.flake;
        in
        lib.foldl' lib.recursiveUpdate { } (lib.attrValues evaluatedOutputs);
    })

    # Combined formatter from formatter.d/ and __outputs.perSystem.formatter
    {
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
          perSystemPath = if cfg.src != null then cfg.src + "/${cfg.perSystemDir}" else null;
          formatterDPath = if perSystemPath != null then perSystemPath + "/formatter.d" else null;
          formatterNixPath = if perSystemPath != null then perSystemPath + "/formatter.nix" else null;
          hasFormatterD = formatterDPath != null && builtins.pathExists formatterDPath;
          hasFormatterNix = formatterNixPath != null && builtins.pathExists formatterNixPath;
          hasOutputsFormatter = outputsCfg.enable && builtOutputs.perSystem ? "formatter";

          # Skip if formatter.nix exists (user handles treefmt directly)
          shouldBuildFormatter = (hasFormatterD || hasOutputsFormatter) && !hasFormatterNix;

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
            exports = exportSinks;
          }
          // cfg.args
          // config.imp.args;

          treefmt-nix =
            inputs.imp.inputs.treefmt-nix or inputs.treefmt-nix
              or (throw "formatter.d/__outputs.formatter requires treefmt-nix input (available via inputs.imp.inputs.treefmt-nix)");

          formatterDFragments =
            if hasFormatterD then
              (imp.fragmentsWith perSystemArgs formatterDPath).asAttrs
            else
              { };

          outputsFormatterFragments =
            if hasOutputsFormatter then
              let
                value = builtOutputs.perSystem."formatter";
                evaluated = if builtins.isFunction value then value perSystemArgs else value;
              in
              evaluated
            else
              { };

          merged = lib.foldl' lib.recursiveUpdate { projectRootFile = "flake.nix"; } [
            formatterDFragments
            outputsFormatterFragments
          ];

          formatterResult =
            if shouldBuildFormatter then
              { formatter = (treefmt-nix.lib.evalModule pkgs merged).config.build.wrapper; }
            else
              { };
        in
        formatterResult;
    }

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
