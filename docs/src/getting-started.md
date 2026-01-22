# Getting Started

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    imp.url = "github:imp-nix/imp-nix";
  };
}
```

## With flake-parts

The flake-parts module is the recommended way to use imp. It handles the wiring between your directory structure and flake outputs automatically.

```nix
{
  outputs = inputs@{ flake-parts, imp, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ imp.flakeModules.default ];
      systems = [ "x86_64-linux" "aarch64-linux" ];
      imp = {
        src = ./outputs;
        registry.src = ./registry;  # optional
      };
    };
}
```

Your `outputs/` directory maps directly to flake outputs:

```
outputs/
  perSystem/
    packages.nix      # -> perSystem.packages
    devShells.nix     # -> perSystem.devShells
  nixosConfigurations/
    server.nix        # -> flake.nixosConfigurations.server
  overlays.nix        # -> flake.overlays
```

Files in `perSystem/` receive the standard flake-parts arguments: `pkgs`, `lib`, `system`, `self`, `self'`, `inputs`, `inputs'`. Files outside `perSystem/` receive `lib`, `self`, `inputs`, plus `registry` and `imp` if you've configured them.

## Standalone usage

Without flake-parts, imp works as a tree builder or module importer.

As a module importer in NixOS configurations:

```nix
{ inputs, ... }:
{
  imports = [ (inputs.imp ./modules) ];
}
```

As a tree builder for arbitrary directory structures:

```nix
imp.treeWith lib (f: f { inherit pkgs; }) ./outputs
# => { packages.hello = <derivation>; apps.run = <derivation>; }
```

The `treeWith` function takes three arguments: `lib` (from nixpkgs), a transformation function applied to each imported file, and the root path. Most files export functions expecting arguments like `pkgs`, and the transformation function is where you supply them.

## Next steps

Read about [directory-based imports](./concepts/directory-imports.md) to understand how imp maps files to attributes. If you're building NixOS or Home Manager configurations, [config trees](./guides/config-trees.md) show how directory paths can map directly to option paths. For larger projects, [the registry](./concepts/registry.md) provides named module references.

Once you have a registry, [export sinks](./concepts/exports.md) let features declare where their configuration lands rather than having consumers list every import. [Host declarations](./concepts/hosts.md) take this further: define `__host` in the registry and imp generates `nixosConfigurations` with sink imports, Home Manager integration, and config tree merging wired up.
