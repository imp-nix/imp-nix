# The Registry

Relative paths like `../../../modules/nixos/base.nix` break when you reorganize. The registry maps your directory structure to an attribute set: `registry/modules/nixos/base.nix` becomes `registry.modules.nixos.base`. References use attribute paths instead of filesystem paths.

## Setup

```nix
imp = {
  src = ../outputs;
  registry.src = ../registry;
};
```

## Structure

```
registry/
  hosts/
    server/default.nix    → registry.hosts.server
  modules/
    nixos/
      base.nix            → registry.modules.nixos.base
      features/
        ssh.nix           → registry.modules.nixos.features.ssh
  users/
    alice/default.nix     → registry.users.alice
```

Directories with `default.nix` become leaf nodes. Directories without it become nested attrsets with a `__path` attribute pointing to the directory.

## Usage

Files loaded by imp receive the `registry` argument:

```nix
{ lib, inputs, imp, registry, ... }:
lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = { inherit inputs imp registry; };
  modules = imp.imports [
    registry.hosts.server
    registry.modules.nixos.base
    inputs.disko.nixosModules.default
    { services.openssh.enable = true; }
  ];
}
```

`imp.imports` extracts `__path` from registry nodes, imports paths directly, and passes everything else through unchanged.

## Importing directories

Import every module in a directory:

```nix
imports = [ (imp registry.modules.nixos.features) ];
```

## Overrides

Insert external modules at registry paths:

```nix
imp.registry.modules = {
  "nixos.disko" = inputs.disko.nixosModules.default;
};
```

## Flake output

When `imp.registry.src` is set, the registry is exposed as a flake output. Run `nix eval .#registry` to inspect the structure.
