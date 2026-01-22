# NixOS Configuration

A complete NixOS configuration using imp's registry and config trees.

```
my-flake/
  flake.nix
  nix/
    flake/
      default.nix
      inputs.nix
    outputs/
      nixosConfigurations/
        server.nix
      perSystem/
        packages.nix
    registry/
      hosts/
        server/
          default.nix
          hardware.nix
          config/
            networking.nix
            boot.nix
      modules/
        nixos/
          base.nix
          features/
            ssh.nix
      users/
        alice/default.nix
```

## flake.nix

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    imp.url = "github:imp-nix/imp-nix";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = inputs: import ./nix/flake inputs;
}
```

## nix/flake/default.nix

The flake-parts entry point with imp configured:

```nix
inputs:
flake-parts.lib.mkFlake { inherit inputs; } {
  imports = [ inputs.imp.flakeModules.default ];
  systems = [ "x86_64-linux" "aarch64-linux" ];
  imp = {
    src = ../outputs;
    registry.src = ../registry;
  };
}
```

## nix/outputs/nixosConfigurations/server.nix

The flake output that builds the system. It pulls modules from the registry by name:

```nix
{ lib, inputs, imp, registry, ... }:
lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = { inherit inputs imp registry; };
  modules = imp.imports [
    registry.hosts.server
    registry.modules.nixos.base
    registry.modules.nixos.features.ssh
  ];
}
```

## nix/registry/hosts/server/default.nix

The host definition. It imports its hardware config and uses a config tree for system settings:

```nix
{ inputs, imp, registry, ... }:
{
  imports = [
    ./hardware.nix
    (imp.configTree ./config)
  ];

  home-manager = {
    useGlobalPkgs = true;
    extraSpecialArgs = { inherit inputs imp registry; };
    users.alice = import registry.users.alice;
  };
}
```

## nix/registry/hosts/server/config/networking.nix

Config tree files are minimal, just the option values:

```nix
{
  hostName = "server";
  firewall.allowedTCPPorts = [ 80 443 ];
}
```

## nix/registry/modules/nixos/base.nix

Shared module for all hosts:

```nix
{ pkgs, ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  environment.systemPackages = with pkgs; [ vim git curl ];
}
```
