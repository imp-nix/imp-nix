# Using with flake-parts

The flake-parts module maps your directory structure to flake outputs. Point it at an outputs directory and files become attributes:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    imp.url = "github:imp-nix/imp-nix";
  };

  outputs = inputs@{ flake-parts, imp, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ imp.flakeModules.default ];
      systems = [ "x86_64-linux" "aarch64-linux" ];
      imp.src = ./outputs;
    };
}
```

## Directory structure

```
outputs/
  perSystem/
    packages.nix      # perSystem.packages
    devShells.nix     # perSystem.devShells
  nixosConfigurations/
    server.nix        # flake.nixosConfigurations.server
  overlays.nix        # flake.overlays
```

Files in `perSystem/` evaluate once per system in your `systems` list. They receive `pkgs` instantiated for that system, along with `system`, `self'`, and `inputs'` (the per-system projections). Flake-level files outside `perSystem/` receive `lib`, `self`, `inputs`, and `config`.

## perSystem files

```nix
# outputs/perSystem/packages.nix
{ pkgs, self, inputs, ... }:
{
  hello = pkgs.hello;
  myPackage = inputs.bun2nix.lib.mkBunPackage {
    inherit pkgs;
    src = self + "/src";
    lockfile = self + "/bun.lock";
  };
}
```

The `self + "/path"` pattern references files relative to the flake root. Since `self` is the flake itself (a path-like value), concatenating strings produces paths anywhere in your repository. Use this for lockfiles, source directories, or anything outside the current file's directory.

## Flake-level files

```nix
# outputs/nixosConfigurations/server.nix
{ lib, self, inputs, registry, ... }:
lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = { inherit inputs registry; };
  modules = [ /* ... */ ];
}
```

These don't receive `pkgs` since there's no single system context. If you need pkgs, call `inputs.nixpkgs.legacyPackages.${system}` explicitly.

## Adding a registry

```nix
imp = {
  src = ./outputs;
  registry.src = ./registry;
};
```

With `registry.src` set, every file receives `registry`, letting you reference modules by name rather than path. See [The Registry](../concepts/registry.md) for the full pattern.

## Troubleshooting

The most common error looks like this:

```
error: attribute 'bun2nix' missing
at /nix/store/.../outputs/perSystem/packages.nix:6:3
```

Three typical causes. First, you might be destructuring an input directly instead of accessing it through `inputs`:

```nix
# Wrong: bun2nix isn't a direct argument
{ bun2nix, ... }: bun2nix.lib.mkPackage { }

# Correct: access through inputs
{ inputs, ... }: inputs.bun2nix.lib.mkPackage { }
```

Second, check for typos in argument names. Third, flake-level files (outside `perSystem/`) don't receive `pkgs` or `system`. If you're trying to use those in a non-perSystem file, restructure your code or access them explicitly.
