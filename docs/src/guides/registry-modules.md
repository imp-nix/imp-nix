# Registry Module Pattern

Registry modules can declare flake inputs and overlays inline, alongside the module definition. The module that needs NUR extensions declares the NUR input right there, not in `flake.nix`.

```nix
# nix/registry/modules/home/features/firefox/default.nix
{
  __inputs = {
    nur.url = "github:nix-community/NUR";
    nur.inputs.nixpkgs.follows = "nixpkgs";
  };

  __functor = _: { inputs, ... }: {
    __overlays.nur = inputs.nur.overlays.default;

    __module = { config, lib, pkgs, ... }: {
      programs.firefox = {
        enable = true;
        extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
          ublock-origin
          darkreader
        ];
      };
    };
  };
}
```

The file returns an attrset with `__inputs` at the top level and `__functor` containing the callable module logic. When `nix run .#imp-flake` scans this file, it reads `__inputs` directly from the attrset without calling anything. At runtime, imp calls `__functor` to get the registry wrapper containing `__overlays` and `__module`.

## Why `__functor`

Input collection happens before the flake is evaluated, so `inputs` doesn't exist yet. If a file is a plain function `{ inputs, ... }: { __inputs = ...; }`, the collector would have to call it to read `__inputs`, but it can't supply valid `inputs`.

The `__functor` pattern separates static metadata from runtime logic. `__inputs` sits outside the function, readable by simple attrset inspection. The actual module code goes in `__functor`, evaluated later when `inputs` is available.

Files that don't declare `__inputs` can use either pattern. A plain function `{ pkgs, ... }: { ... }` works fine for registry modules that only reference inputs already declared elsewhere.

## How `imp.imports` Extracts `__module`

User configs call `imp.imports` to process registry paths:

```nix
{ registry, imp, lib, ... }:
{
  imports = imp.imports [
    registry.modules.home.base
    registry.modules.home.features.firefox
  ];
}
```

The function distinguishes three cases:

1. Registry nodes (attrsets with `__path`): import the path and process
2. Plain paths: import and process
3. Everything else: pass through unchanged

Processing means detecting registry wrappers and extracting `__module`. A registry wrapper is a function that takes `inputs` but not `config` or `pkgs`. Normal NixOS modules take `{ config, lib, pkgs, ... }`, so the heuristic reliably separates the two.

For `__functor` attrsets, `imp.imports` calls the functor to get the registry wrapper, then extracts `__module` from the result. For plain registry wrapper functions, it calls them with the module args.

## Why Two Function Calls

Consider the evaluation sequence for a `__functor` file:

1. Import returns `{ __inputs; __functor }`
2. Call `__functor _` with module args to get `{ __overlays; __module }`
3. `__module` is itself a function `{ config, lib, pkgs, ... }: { ... }`
4. Call `__module` with module args to get the final config

The module system calls a module function once and expects an attrset. The wrapper must invoke both: first the registry wrapper to obtain `__module`, then `__module` itself to produce the config the module system expects.

## Overlay Application

The `__overlays` attribute declares overlays this module needs applied to nixpkgs. A typical setup has an `overlays.nix` in outputs that aggregates them:

```nix
# nix/outputs/overlays.nix
{
  __inputs = {
    nur.url = "github:nix-community/NUR";
    nur.inputs.nixpkgs.follows = "nixpkgs";
  };

  __functor = _: { inputs, ... }: {
    nur = inputs.nur.overlays.default;
  };
}
```

A base NixOS module applies them:

```nix
# nix/registry/modules/nixos/base.nix
{ self, lib, ... }:
{
  nixpkgs.overlays = lib.attrValues (self.overlays or { });
}
```

Automatic overlay collection from `__overlays` in registry modules is not implemented. The declarations serve as documentation and require manual aggregation in `overlays.nix`.

## Limitations

Registry wrapper detection uses a heuristic: "takes `inputs`, not `config` or `pkgs`". A function taking both `inputs` and `config` won't be detected as a registry wrapper. Structure such modules with a clear separation: the outer `__functor` receives `inputs`, the inner `__module` receives `config`.
