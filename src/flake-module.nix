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

  # Normalize a value that can be null, path, or list of paths to a list
  toPathList =
    v:
    if v == null then
      [ ]
    else if builtins.isList v then
      v
    else
      [ v ];

  # Get first path from src (for single-path operations like systems.nix)
  firstSrc =
    if cfg.src == null then
      null
    else if builtins.isList cfg.src then
      builtins.head cfg.src
    else
      cfg.src;

  /**
    Build perSystem argument set.

    includePerSystemConfig: Whether to include config.imp.args.
      Set to false for deferred functor evaluation to prevent infinite recursion.
      When a functor contributes to perSystem options, and config.imp.args
      references those options, including it creates a cycle.

    buildDeps: Collected build dependencies from `__outputs.perSystem.buildDeps.*`.
      Bundles can declare dependencies that other bundles' packages should use.
  */
  mkPerSystemArgs =
    {
      pkgs,
      system,
      self',
      inputs',
      perSystemConfig ? null,
      buildDeps ? { },
    }:
    {
      inherit
        lib
        pkgs
        system
        self
        self'
        inputs
        inputs'
        imp
        buildDeps
        ;
      ${cfg.registry.name} = registry;
      exports = exportSinks;
    }
    // cfg.args
    // (if perSystemConfig != null then perSystemConfig.imp.args else { });

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

  srcPaths = toPathList cfg.src;

  flakeTree =
    if srcPaths == [ ] then
      { }
    else
      let
        trees = map (src: buildTree src flakeArgs) srcPaths;
        fullTree = lib.foldl' lib.recursiveUpdate { } trees;
      in
      filterAttrs (name: _: !isSpecialEntry name) fullTree;

  # systems.nix only from first src path
  systemsFile = if firstSrc != null then firstSrc + "/systems.nix" else null;
  hasSystemsFile = systemsFile != null && builtins.pathExists systemsFile;
  systemsFromFile =
    if hasSystemsFile then utils.applyIfCallable flakeArgs (import systemsFile) else null;

  exportsCfg = cfg.exports;

  # Exports scan both registry.src and src paths
  exportSources = toPathList cfg.registry.src ++ srcPaths;

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

  bundlePaths = toPathList cfg.bundles.src;

  # Inputs scan all source paths
  inputSources = srcPaths ++ toPathList cfg.registry.src ++ bundlePaths;
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

  # Outputs scan src and bundles (registry.src is for named modules, not bundles)
  outputSources = srcPaths ++ bundlePaths;

  collectedOutputs =
    if outputsCfg.enable && outputSources != [ ] then impLib.collectOutputs outputSources else { };

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
        deferredFunctors = [ ];
      };

  hostsCfg = cfg.hosts;

  # Hosts are scanned from registry.src only
  hostSources = toPathList cfg.registry.src;

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

    (lib.mkIf (srcPaths != [ ]) {
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
          perSystemPaths = map (src: src + "/${cfg.perSystemDir}") srcPaths;
          perSystemArgs = mkPerSystemArgs {
            inherit
              pkgs
              system
              self'
              inputs'
              ;
            perSystemConfig = config;
          };
          trees = map (p: buildTree p perSystemArgs) perSystemPaths;
          rawOutputs = lib.foldl' lib.recursiveUpdate { } trees;
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
          nonFormatterOutputs = filterAttrs (k: _: k != "formatter") builtOutputs.perSystem;

          isBuildDeps = k: lib.hasPrefix "buildDeps." k;
          buildDepsOutputs = filterAttrs (k: _: isBuildDeps k) nonFormatterOutputs;
          otherOutputs = filterAttrs (k: _: !isBuildDeps k) nonFormatterOutputs;

          baseArgs = mkPerSystemArgs {
            inherit
              pkgs
              system
              self'
              inputs'
              ;
            perSystemConfig = config;
          };

          evaluatedBuildDeps = lib.mapAttrs' (
            outputPath: value:
            let
              name = lib.removePrefix "buildDeps." outputPath;
              evaluated = if builtins.isFunction value then value baseArgs else value;
            in
            lib.nameValuePair name evaluated
          ) buildDepsOutputs;

          perSystemArgs = mkPerSystemArgs {
            inherit
              pkgs
              system
              self'
              inputs'
              ;
            perSystemConfig = config;
            buildDeps = evaluatedBuildDeps;
          };

          evaluatedOutputs = lib.mapAttrs (
            outputPath: value:
            let
              parts = lib.splitString "." outputPath;
              evaluated = if builtins.isFunction value then value perSystemArgs else value;
            in
            lib.setAttrByPath parts evaluated
          ) otherOutputs;

          merged = lib.foldl' lib.recursiveUpdate { } (lib.attrValues evaluatedOutputs);
        in
        merged;
    })

    # Deferred functor outputs (bundles with __functor or plain functions)
    # Note: Does not include config.imp.args to avoid infinite recursion
    (lib.mkIf (outputsCfg.enable && builtOutputs.deferredFunctors != [ ]) {
      perSystem =
        {
          pkgs,
          system,
          self',
          inputs',
          ...
        }:
        let
          baseArgs = mkPerSystemArgs {
            inherit
              pkgs
              system
              self'
              inputs'
              ;
          };

          isBuildDepsKey = k: lib.hasPrefix "buildDeps." k;
          staticBuildDepsOutputs = filterAttrs (k: _: isBuildDepsKey k) builtOutputs.perSystem;
          staticBuildDeps = lib.mapAttrs' (
            outputPath: value:
            let
              name = lib.removePrefix "buildDeps." outputPath;
              evaluated = if builtins.isFunction value then value baseArgs else value;
            in
            lib.nameValuePair name evaluated
          ) staticBuildDepsOutputs;

          # First pass: extract buildDeps from functors
          extractFunctorBuildDeps =
            {
              functor,
              isFunctor,
              source,
            }:
            let
              fn = if isFunctor then functor.__functor functor else functor;
              result = fn baseArgs;
              outputs = result.__outputs or { };
              perSystem = outputs.perSystem or { };
            in
            perSystem.buildDeps or { };

          functorBuildDeps = map extractFunctorBuildDeps builtOutputs.deferredFunctors;
          mergedFunctorBuildDeps = lib.foldl' lib.recursiveUpdate { } functorBuildDeps;
          allBuildDeps = lib.recursiveUpdate staticBuildDeps mergedFunctorBuildDeps;

          perSystemArgs = mkPerSystemArgs {
            inherit
              pkgs
              system
              self'
              inputs'
              ;
            buildDeps = allBuildDeps;
          };

          unwrapLeaf = utils.unwrapValue perSystemArgs;

          processOutputs =
            attrs:
            lib.mapAttrs (
              _outputType: outputs:
              if builtins.isAttrs outputs then lib.mapAttrs (_name: unwrapLeaf) outputs else unwrapLeaf outputs
            ) attrs;

          # Second pass: evaluate functors with collected buildDeps
          evaluateFunctor =
            {
              functor,
              isFunctor,
              source,
            }:
            let
              fn = if isFunctor then functor.__functor functor else functor;
              result = fn perSystemArgs;
              outputs = result.__outputs or { };
              perSystem = outputs.perSystem or { };
              # perSystem keys are top-level ("buildDeps", "packages"), not dot-separated
              filtered = filterAttrs (k: _: k != "formatter" && k != "buildDeps") perSystem;
              processed = processOutputs filtered;
            in
            processed;

          deferredResults = map evaluateFunctor builtOutputs.deferredFunctors;
          merged = lib.foldl' lib.recursiveUpdate { } deferredResults;
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
          ...
        }:
        let
          # formatter.d and formatter.nix from first src only
          perSystemPath = if firstSrc != null then firstSrc + "/${cfg.perSystemDir}" else null;
          formatterDPath = if perSystemPath != null then perSystemPath + "/formatter.d" else null;
          formatterNixPath = if perSystemPath != null then perSystemPath + "/formatter.nix" else null;
          hasFormatterD = formatterDPath != null && builtins.pathExists formatterDPath;
          hasFormatterNix = formatterNixPath != null && builtins.pathExists formatterNixPath;
          hasOutputsFormatter = outputsCfg.enable && builtOutputs.perSystem ? "formatter";
          hasDeferredFunctors = outputsCfg.enable && builtOutputs.deferredFunctors != [ ];

          # Skip if formatter.nix exists (user handles treefmt directly)
          shouldBuildFormatter =
            (hasFormatterD || hasOutputsFormatter || hasDeferredFunctors) && !hasFormatterNix;

          # perSystemConfig = null - formatter section doesn't need config.imp.args
          perSystemArgs = mkPerSystemArgs {
            inherit
              pkgs
              system
              self'
              inputs'
              ;
          };

          treefmt-nix =
            inputs.imp.inputs.treefmt-nix or inputs.treefmt-nix
              or (throw "formatter.d/__outputs.formatter requires treefmt-nix input (available via inputs.imp.inputs.treefmt-nix)");

          formatterDFragments =
            if hasFormatterD then (imp.fragmentsWith perSystemArgs formatterDPath).asAttrs else { };

          outputsFormatterFragments =
            if hasOutputsFormatter then
              let
                value = builtOutputs.perSystem."formatter";
                evaluated = if builtins.isFunction value then value perSystemArgs else value;
              in
              evaluated
            else
              { };

          # Extract formatter config from deferred functors
          deferredFormatterFragments =
            if hasDeferredFunctors then
              let
                extractFormatter =
                  {
                    functor,
                    isFunctor,
                    source,
                  }:
                  let
                    fn = if isFunctor then functor.__functor functor else functor;
                    result = fn perSystemArgs;
                    outputs = result.__outputs or { };
                    formatter = outputs.perSystem.formatter or null;
                  in
                  if formatter == null then
                    { }
                  else if builtins.isAttrs formatter && formatter ? value then
                    formatter.value
                  else
                    formatter;
                fragments = map extractFormatter builtOutputs.deferredFunctors;
              in
              lib.foldl' lib.recursiveUpdate { } fragments
            else
              { };

          merged = lib.foldl' lib.recursiveUpdate { projectRootFile = "flake.nix"; } [
            formatterDFragments
            outputsFormatterFragments
            deferredFormatterFragments
          ];

          formatterResult =
            if shouldBuildFormatter then
              { formatter = (treefmt-nix.lib.evalModule pkgs merged).config.build.wrapper; }
            else
              { };
        in
        formatterResult;
    }

    # Auto-generated default devShell from impShell.enable
    (lib.mkIf cfg.impShell.enable {
      perSystem =
        { pkgs, self', ... }:
        {
          devShells.default = lib.mkDefault (
            pkgs.mkShell {
              inputsFrom = builtins.attrValues (builtins.removeAttrs self'.devShells [ "default" ]);
            }
          );
        };
    })

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

    (
      let
        collectedSkills = if bundlePaths != [ ] then impLib.collectSkills bundlePaths else { };
        skillNames = builtins.attrNames collectedSkills;
        hasSkills = skillNames != [ ];
      in
      lib.mkIf (cfg.bundles.skills.enable && hasSkills) {
        perSystem =
          { pkgs, ... }:
          {
            /*
              Symlink bundle skills to .claude/skills/

              Bundles can include Claude Code skills in a skills/ subdirectory.
              Each skill folder becomes a symlink in .claude/skills/.

              Run: nix run .#imp-link-skills
            */
            apps.imp-link-skills = {
              type = "app";
              program = toString (
                pkgs.writeShellScript "imp-link-skills" ''
                  mkdir -p .claude/skills
                  ${lib.concatStringsSep "\n" (
                    map (
                      name:
                      "ln -sfn ${
                        lib.escapeShellArg (toString collectedSkills.${name})
                      } .claude/skills/${lib.escapeShellArg name}"
                    ) skillNames
                  )}
                  echo "imp-link-skills: linked ${toString (builtins.length skillNames)} skill(s)"
                ''
              );
              meta.description = "Symlink bundle skills to .claude/skills/";
            };
          };
      }
    )
  ];
}
