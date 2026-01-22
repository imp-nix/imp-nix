# Output Declarations

Output declarations let self-contained bundles contribute to multiple flake output types from a single location. A lint bundle can provide a package, add tools to the devShell, and configure the formatter—all without the consumer needing to wire up each piece.

This solves the composition problem for drop-in functionality. You copy a bundle directory into your project, and its outputs automatically integrate with your flake. The bundle declares where its outputs belong rather than requiring explicit plumbing.

## Declaration

Files declare outputs using the `__outputs` attribute with nested paths targeting flake outputs:

```nix
{
  __outputs.perSystem.packages.lint = { pkgs, ... }:
    pkgs.writeShellScript "lint" ''
      shellcheck "$@"
    '';

  __outputs.perSystem.devShells.default = {
    value = { pkgs, ... }: {
      nativeBuildInputs = [ pkgs.shellcheck ];
    };
    strategy = "merge";
  };
}
```

The path `__outputs.perSystem.packages.lint` maps directly to `perSystem.packages.lint` in flake-parts. Outputs under `perSystem.*` receive per-system arguments (`pkgs`, `lib`, `system`, etc.) at evaluation time. Top-level outputs like `overlays` receive flake-level arguments.

For outputs needing inputs, use the `__functor` pattern:

```nix
{
  __inputs.rust-overlay.url = "github:oxalica/rust-overlay";

  __functor = _: { pkgs, rust-overlay, ... }: {
    __outputs.perSystem.packages.default = pkgs.hello;
  };
}
```

## Output types

**perSystem outputs** receive `{ pkgs, lib, system, self, self', inputs, inputs', ... }` when evaluated. These include packages, devShells, checks, apps, and formatter.

```nix
{
  __outputs.perSystem.packages.hello = { pkgs, ... }:
    pkgs.hello;

  __outputs.perSystem.checks.lint = { pkgs, self', ... }:
    pkgs.runCommand "lint" { } ''
      ${self'.packages.lint} src/
      touch $out
    '';
}
```

**Flake-level outputs** receive `{ lib, self, inputs, config, ... }`. These include overlays, nixosModules, and nixosConfigurations.

```nix
{
  __outputs.overlays.default = final: prev: {
    myTool = prev.callPackage ./package.nix { };
  };

  __outputs.nixosModules.myModule = { config, lib, ... }: {
    options.my.enable = lib.mkEnableOption "my feature";
  };
}
```

## Merge strategies

When multiple files target the same output path, the merge strategy controls how values combine:

**merge** performs `lib.recursiveUpdate`, deeply merging attrsets. Nested attrsets combine; primitive values take the last writer (alphabetically by source path). This is the default when multiple contributors exist.

```nix
# bundles/lint/default.nix
{
  __outputs.perSystem.devShells.default = {
    value = { pkgs, ... }: {
      nativeBuildInputs = [ pkgs.shellcheck ];
      env.LINT = "1";
    };
    strategy = "merge";
  };
}

# bundles/format/default.nix
{
  __outputs.perSystem.devShells.default = {
    value = { pkgs, ... }: {
      nativeBuildInputs = [ pkgs.nixfmt ];
      env.FORMAT = "1";
    };
    strategy = "merge";
  };
}

# Result: devShells.default has both packages and both env vars
# Note: nativeBuildInputs is replaced (last writer), not concatenated
```

**override** replaces the entire value. Last writer wins completely. This is the default for single contributors.

For list concatenation (like `nativeBuildInputs`), structure your outputs to merge at a higher level or use the module system's `mkMerge` within your values.

## Formatter fragments

The `formatter` output receives special handling. Instead of outputting a derivation directly, `__outputs.perSystem.formatter` declares treefmt configuration fragments that merge with `formatter.d/` fragments:

```nix
{
  __outputs.perSystem.formatter = {
    value = {
      programs.rustfmt.enable = true;
      settings.formatter.cargo-sort = {
        command = "${cargoSortWrapper}/bin/cargo-sort-wrapper";
        includes = [ "Cargo.toml" "**/Cargo.toml" ];
      };
    };
    strategy = "merge";
  };
}
```

All formatter fragments from bundles and `formatter.d/` are merged together, then wrapped with treefmt-nix to produce the final formatter derivation. This allows bundles to contribute formatter configuration without owning the entire formatter.

The merge happens in order: `formatter.d/` fragments first (sorted by filename), then `__outputs.perSystem.formatter` fragments. Later values override earlier ones for non-attrset fields.

## Flake integration

The flake-parts module automatically collects and builds outputs when `imp.outputs.enable = true` (the default). It scans both `imp.registry.src` and `imp.src`:

```nix
{
  imp = {
    src = ./outputs;
    registry.src = ./nix/registry;
    outputs = {
      enable = true;
      # Optionally restrict which paths to scan
      sources = [ ./bundles ];
    };
  };
}
```

Collected outputs merge with outputs from the standard directory structure. A bundle's `__outputs.perSystem.packages.foo` combines with packages defined in `outputs/perSystem/packages.nix`.

## Bundle structure

A typical bundle is self-contained in a directory:

```
bundles/
  lint/
    default.nix      # __outputs declarations
    config/          # Optional additional files
  format/
    default.nix
```

The bundle's `default.nix` declares all its contributions:

```nix
{
  __inputs.rust-overlay.url = "github:oxalica/rust-overlay";

  __functor = _: { pkgs, rust-overlay, rootSrc, ... }:
    let
      rustToolchain = pkgs.rust-bin.fromRustupToolchainFile (rootSrc + "/rust-toolchain.toml");
    in
    {
      __outputs.perSystem.packages.default = pkgs.rustPlatform.buildRustPackage { ... };

      __outputs.perSystem.devShells.default = {
        value = { pkgs, ... }: {
          nativeBuildInputs = [ rustToolchain ];
        };
        strategy = "merge";
      };

      # Formatter config fragment (merges with formatter.d/)
      __outputs.perSystem.formatter = {
        value = {
          programs.rustfmt.enable = true;
        };
        strategy = "merge";
      };
    };
}
```

Copy this directory into any imp-based project, and the outputs integrate automatically.

## When to use outputs

Output declarations fit scenarios where functionality should be self-contained and portable. Development tooling bundles (linting, formatting, testing), feature flags that add packages and shell tools, or reusable CI/CD configurations work well.

For outputs that belong to a single logical location without reuse, the standard directory structure (`outputs/perSystem/packages.nix`) remains simpler. Use `__outputs` when the bundle needs to contribute to multiple output types or when portability matters.

The pattern complements export sinks: exports push configuration into merge points for NixOS/Home Manager modules, while outputs push into flake outputs for packages, shells, and apps.
