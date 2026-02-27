{
  description = "A Nix library for organizing flakes with directory-based imports, named module registries, and automatic input collection.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Collected from __inputs declarations in outputs/
    # Regenerate with: nix run .#imp-flake
    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
    nix-unit.inputs.flake-parts.follows = "flake-parts";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      # Bootstrap: import imp-nix directly from source
      imp = import ./src;
      directExports = {
        # imp library API
        __functor = imp.__functor;
        __config = imp.__config;
        withLib = imp.withLib;
        addRoot = imp.addRoot;
        addAPI = imp.addAPI;
        new = imp.new;

        tree = imp.tree;
        treeWith = imp.treeWith;
        configTree = imp.configTree;
        configTreeWith = imp.configTreeWith;

        collectInputs = imp.collectInputs;
        formatInputs = imp.formatInputs;
        formatFlake = imp.formatFlake;
        collectAndFormatFlake = imp.collectAndFormatFlake;
        mkWorkspaceFlakeOutputs = imp.mkWorkspaceFlakeOutputs;
      };
      flakePartsOutputs = flake-parts.lib.mkFlake { inherit inputs; } {
        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "x86_64-darwin"
          "aarch64-darwin"
        ];

        imports = [
          ./src/flake/flake-module.nix
        ];

        imp = {
          src = ./outputs;
          registry.src = ./src;
          exports.enable = false;
          args = {
            treefmt-nix = inputs.treefmt-nix;
          };

          # imp-nix uses a custom flake.nix with direct exports, so disable auto-generation
          flakeFile.enable = false;
        };
      };
      base = directExports // flakePartsOutputs;
      existingLib = if builtins.hasAttr "lib" base then base.lib else { };
    in
    base
    // {
      lib = existingLib // {
        mkWorkspaceFlakeOutputs = imp.mkWorkspaceFlakeOutputs;
      };

      workspaceRuntime = {
        nixpkgs = inputs.nixpkgs;
      };
    };
}
