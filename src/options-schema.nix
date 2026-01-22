/**
  Shared options schema for imp.

  This is a standard NixOS-style module defining imp.* options.
  Used by:
  - flake-module.nix (imports this module)
  - Documentation generation (evaluated standalone)
*/
{ lib, ... }:
let
  inherit (lib)
    mkOption
    mkEnableOption
    types
    literalExpression
    ;

  # Type that accepts a single path or a list of paths
  pathOrPaths = types.either types.path (types.listOf types.path);
in
{
  options.imp = {
    src = mkOption {
      type = types.nullOr pathOrPaths;
      default = null;
      description = ''
        Directory (or list of directories) containing flake outputs to import.

        Structure maps to flake-parts semantics:
          outputs/
            perSystem/           -> perSystem.* (per-system outputs)
              packages.nix       -> perSystem.packages
              devShells.nix      -> perSystem.devShells
            nixosConfigurations/ -> flake.nixosConfigurations
            overlays.nix         -> flake.overlays
            systems.nix          -> systems (optional, overrides top-level)

        When multiple paths are provided, they are scanned in order.
      '';
      example = literalExpression ''
        [ ./outputs ./extra-outputs ]
      '';
    };

    args = mkOption {
      type = types.attrsOf types.unspecified;
      default = { };
      description = ''
        Extra arguments passed to all imported files.

        Flake files receive: { lib, self, inputs, config, imp, registry, ... }
        perSystem files receive: { pkgs, lib, system, self, self', inputs, inputs', imp, registry, ... }

        User-provided args take precedence over defaults.
      '';
    };

    perSystemDir = mkOption {
      type = types.str;
      default = "perSystem";
      description = ''
        Subdirectory name for per-system outputs.

        Files in this directory receive standard flake-parts perSystem args:
        { pkgs, lib, system, self, self', inputs, inputs', ... }
      '';
    };

    registry = {
      name = mkOption {
        type = types.str;
        default = "registry";
        description = ''
          Attribute name used to inject the registry into file arguments.

          Change this if "registry" conflicts with other inputs or arguments.
        '';
        example = literalExpression ''
          "impRegistry"
          # Then in files:
          # { impRegistry, ... }:
          # { imports = [ impRegistry.modules.home ]; }
        '';
      };

      src = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Root directory to scan for building the module registry.

          The registry maps directory structure to named modules.
          Files can then reference modules by name instead of path.
        '';
        example = literalExpression ''
          ./nix
          # Structure:
          #   nix/
          #     users/alice/     -> registry.users.alice
          #     modules/nixos/   -> registry.modules.nixos
          #
          # Usage in files:
          #   { registry, ... }:
          #   { imports = [ registry.modules.home ]; }
        '';
      };

      modules = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
        description = ''
          Explicit module name -> path mappings.
          These override auto-discovered modules from registry.src.
        '';
        example = literalExpression ''
          {
            specialModule = ./path/to/special.nix;
          }
        '';
      };
    };

    exports = {
      enable = mkEnableOption "export sinks from __exports declarations" // {
        default = true;
      };

      sinkDefaults = mkOption {
        type = types.attrsOf types.str;
        default = {
          "nixos.*" = "merge";
          "hm.*" = "merge";
        };
        description = ''
          Default merge strategies for sink patterns.

          Patterns use glob syntax where * matches any suffix.
          Available strategies:
          - "merge": Deep merge (lib.recursiveUpdate)
          - "override": Last writer wins
          - "list-append": Concatenate lists
          - "mkMerge": Use lib.mkMerge for module semantics
        '';
        example = literalExpression ''
          {
            "nixos.*" = "merge";
            "hm.*" = "mkMerge";
            "packages.*" = "override";
          }
        '';
      };

      enableDebug = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Include __meta with contributor info in sinks.

          When enabled, each sink includes:
          - __meta.contributors: list of source paths
          - __meta.strategy: effective merge strategy
        '';
      };
    };

    flakeFile = {
      enable = mkEnableOption "flake.nix generation from __inputs declarations";

      path = mkOption {
        type = types.path;
        # Placeholder default - flake-module.nix overrides this with self + "/flake.nix"
        default = /path/to/flake.nix;
        defaultText = literalExpression "self + \"/flake.nix\"";
        description = "Path to flake.nix file to generate/check.";
      };

      description = mkOption {
        type = types.str;
        default = "";
        description = "Flake description field.";
      };

      coreInputs = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
        description = ''
          Core inputs always included in flake.nix (e.g., nixpkgs, flake-parts).
        '';
        example = literalExpression ''
          {
            nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
            flake-parts.url = "github:hercules-ci/flake-parts";
          }
        '';
      };

      outputsFile = mkOption {
        type = types.str;
        default = "./nix/flake";
        description = "Path to outputs file (relative to flake.nix).";
      };

      header = mkOption {
        type = types.str;
        default = "/**\n  Auto-generated by imp - DO NOT EDIT\n  Regenerate with: nix run .#imp-flake\n*/";
        description = "Header comment for generated flake.nix.";
      };

      submodules = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable git submodule support in the flake.
          When true, adds `self.submodules = true;` to inputs.
        '';
      };
    };

    outputs = {
      enable = mkEnableOption "output collection from __outputs declarations" // {
        default = true;
      };
    };

    bundles = {
      src = mkOption {
        type = types.nullOr pathOrPaths;
        default = null;
        description = ''
          Directory (or list of directories) containing self-contained bundles
          with __outputs declarations.

          Bundles are portable directories that contribute to multiple flake outputs.
          Each bundle's default.nix can declare __outputs.perSystem.* and __outputs.*
          to add packages, devShell tools, formatter config, etc.
        '';
        example = literalExpression ''
          ./nix/bundles
          # Or multiple:
          # [ ./nix/bundles ./extra-bundles ]
        '';
      };
    };

    impShell = {
      enable = mkEnableOption "auto-generated default devShell" // {
        default = false;
        description = ''
          Automatically generate a default devShell that composes all other devShells.

          When enabled and no explicit devShells.default is defined, imp creates one
          that uses inputsFrom to include all other devShells. This eliminates
          boilerplate for the common case where you want all devShell contributions
          merged together.
        '';
      };
    };

    hosts = {
      enable = mkEnableOption "automatic nixosConfigurations from __host declarations" // {
        default = false;
        description = ''
          Generate nixosConfigurations by scanning for __host declarations.

          When enabled, imp walks registry.src looking for .nix files that
          contain a __host attrset. Each such file becomes a nixosConfiguration
          entry, named after the directory (for default.nix) or filename.

          The __host schema declares system, stateVersion, base config trees,
          export sinks, extra modules, and optional Home Manager integration.
          See the Host Declarations concept documentation for the full schema.
        '';
      };

      defaults = mkOption {
        type = types.attrsOf types.unspecified;
        default = { };
        description = ''
          Default values for host declarations.

          These fill in any fields not explicitly set in __host. Common use:
          setting system and stateVersion once instead of repeating per-host.
        '';
        example = literalExpression ''
          {
            system = "x86_64-linux";
            stateVersion = "24.11";
          }
        '';
      };
    };
  };
}
