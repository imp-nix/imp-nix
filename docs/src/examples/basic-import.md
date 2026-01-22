# Basic Import

The simplest use of imp: import all modules in a directory.

```
modules/
  networking.nix
  users/
    alice.nix
    bob.nix
  services/
    ssh.nix
```

```nix
{ inputs, ... }:
{
  imports = [ (inputs.imp ./modules) ];
}
```

Every `.nix` file gets imported. Subdirectories are traversed recursively. Just add a file to the directory tree (and `git add` it), it gets imported for you.

## Basic Import In a Flake

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    imp.url = "github:imp-nix/imp-nix";
  };

  outputs = { nixpkgs, imp, ... }:
    {
      nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          (imp ./modules)
          ./hardware-configuration.nix
        ];
      };
    };
}
```

## Module files

Standard NixOS modules:

```nix
# modules/networking.nix
{ ... }:
{
  networking.hostName = "myhost";
  networking.networkmanager.enable = true;
}
```

## Filtering

When you don't want to import everything:

```nix
let imp = inputs.imp.withLib lib; in
{
  imports = [ (imp.filter (lib.hasInfix "/services/") ./modules) ];
}
```

This imports only modules under `modules/services/`.
