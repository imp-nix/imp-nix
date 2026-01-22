# Host Declarations

NixOS configurations traditionally require boilerplate: creating a file in `nixosConfigurations/`, calling `lib.nixosSystem`, passing `specialArgs`, listing imports. The `__host` pattern declares this intent declaratively. Imp scans the registry for `__host` attributes and generates `nixosConfigurations` automatically.

```nix
{
  __host = {
    system = "x86_64-linux";
    stateVersion = "24.11";
    bases = [ "hosts.shared.base" ];
    sinks = [ "shared.nixos" "desktop.nixos" ];
    hmSinks = [ "shared.hm" ];
    modules = [ "mod.nixos.features.audio" ];
    user = "alice";
  };
  config = ./config;
}
```

This file, placed at `registry/hosts/workstation/default.nix`, produces `flake.nixosConfigurations.workstation`. The directory name becomes the host name. No separate configuration file in `outputs/nixosConfigurations/` required.

## Schema

`system` specifies the target architecture. Defaults to `x86_64-linux` if `imp.hosts.defaults.system` is set.

`stateVersion` sets `system.stateVersion`. Required unless provided in defaults.

`bases` lists registry paths to config trees that form the host's foundation. These paths resolve against the registry: `"hosts.shared.base"` becomes `registry.hosts.shared.base`. Imp calls `mergeConfigTrees` on all bases plus the host's own `config` path, producing a single module where directory structure maps to NixOS options.

`sinks` lists export sink paths to import as NixOS modules. Each sink path (like `"shared.nixos"`) resolves to `exports.shared.nixos.__module`. Features across the codebase can export configuration fragments to these sinks; the host receives the merged result without explicit imports.

`hmSinks` works identically for Home Manager. These sink modules land in `home-manager.users.${user}.imports` when `user` is set.

`modules` accepts a list of extra modules, or a function that returns a list. String values resolve as registry paths (`"mod.nixos.features.desktop.niri"` becomes `registry.mod.nixos.features.desktop.niri`). Prefix with `@` to resolve against flake inputs instead: `"@nixos-wsl.nixosModules.default"` becomes `inputs.nixos-wsl.nixosModules.default`. Raw modules (functions or attrsets) pass through unchanged.

When `modules` is a function, it receives `{ registry, inputs, exports }` and returns a list. This enables direct registry attribute access:

```nix
{
  __host = {
    system = "x86_64-linux";
    stateVersion = "24.11";
    modules = { registry, ... }: [
      registry.mod.nixos.features.audio
      registry.mod.nixos.features.desktop.niri
    ];
  };
}
```

`user` enables integrated Home Manager. Imp configures `home-manager.users.${user}` with `useGlobalPkgs = true`, `useUserPackages = true`, and appropriate `extraSpecialArgs`. If `registry.users.${user}` exists, it's automatically imported into the user's HM config.

`config` points to a directory or file containing host-specific configuration as a config tree. This merges with `bases` to form the complete configuration.

`extraConfig` provides an escape hatch for module arguments unavailable to static files. Most commonly used for `modulesPath`:

```nix
{
  __host = { ... };
  config = ./config;
  extraConfig = { modulesPath, ... }: {
    imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];
  };
}
```

## External inputs

Hosts requiring external flake inputs combine `__host` with `__inputs`:

```nix
{
  __inputs.nixos-wsl = {
    url = "github:nix-community/NixOS-WSL";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  __host = {
    system = "x86_64-linux";
    stateVersion = "24.11";
    bases = [ "hosts.shared.base" ];
    sinks = [ "shared.nixos" ];
    modules = [ "@nixos-wsl.nixosModules.default" ];
    user = "alice";
  };
  config = ./config;
}
```

Run `nix run .#imp-flake` after adding `__inputs` declarations. The generated `flake.nix` includes the new input, and the `@` prefix in `modules` resolves it at build time.

## Enabling host generation

```nix
{
  imp = {
    registry.src = ./nix/registry;
    hosts = {
      enable = true;
      sources = [ ./nix/registry/hosts ];  # optional, defaults to registry.src
      defaults = {
        system = "x86_64-linux";
        stateVersion = "24.11";
      };
    };
  };
}
```

With `hosts.enable = true`, imp scans `sources` for files containing `__host` declarations. Each file becomes a `nixosConfiguration` named after its directory (for `default.nix`) or filename (for other `.nix` files). Files in directories starting with `_` are excluded.

## Generated configuration structure

For each host, imp calls `lib.nixosSystem` with:

- `system` from `__host.system` or defaults
- `specialArgs` containing `{ self, inputs, imp, registry, exports }`
- Modules assembled from: merged config trees, `home-manager.nixosModules.home-manager`, resolved sinks, HM integration, resolved extra modules, and `extraConfig`
- `system.stateVersion` set from `__host.stateVersion`

The HM integration module sets `home-manager.extraSpecialArgs` to include `inputs`, `exports`, `imp`, and `registry`, making these available in user configurations.

## Relationship with export sinks

Sinks and hosts work together for role-based configuration. Features declare exports targeting role sinks:

```nix
# registry/mod/features/audio/default.nix
{
  __exports."desktop.nixos" = {
    value = { services.pipewire.enable = true; };
  };
}
```

Hosts import those sinks by listing them:

```nix
{
  __host = {
    sinks = [ "desktop.nixos" ];
  };
}
```

This decouples features from hosts. Adding a feature doesn't require editing host configurations; the feature exports to the appropriate sink, and any host importing that sink receives the configuration.
