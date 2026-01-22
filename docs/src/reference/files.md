# File Reference

<!-- Auto-generated - do not edit -->

## Core

### default.nix

Entry point for imp - directory-based Nix imports.

This module exports the main imp API including:

- Chainable filtering and transformation methods
- Tree building from directory structure
- Registry for named module discovery
- Utilities for flake input collection

### api.nix

API method definitions for imp.

This module defines all chainable methods available on the imp object.
Methods are organized into categories:

- Filtering: `filter`, `filterNot`, `match`, `matchNot`, `initFilter`
- Transforming: `map`, `mapTree`
- Tree building: `tree`, `treeWith`, `configTree`, `configTreeWith`
- Fragments: `fragments`, `fragmentsWith`
- File lists: `leaves`, `files`, `pipeTo`
- Extending: `addRoot`, `addAPI`, `withLib`, `new`

### lib.nix

Internal utility functions for imp.

## Import & Collection

### collect.nix

File collection and filtering logic.

This module handles:

- Recursive file discovery from paths
- Filter composition and application
- Path normalization (absolute to relative)

### tree.nix

Builds nested attrset from directory structure.

Naming: `foo.nix` | `foo/default.nix` -> `{ foo = ... }`
`foo_.nix` -> `{ foo = ... }` (escapes reserved names)
`_foo.nix` | `_foo/` -> ignored
`foo.d/` -> fragment directory (merged attrsets)

Fragment directories (`*.d/`):
Any `foo.d/` directory is processed as a fragment directory. The `.nix`
files inside are imported in sorted order (00-base.nix before 10-extra.nix)
and combined with `lib.recursiveUpdate`.

If `foo.d/` contains no valid `.nix` files, it is skipped entirely.
Non-`.nix` files in `.d` directories (e.g., `.sh` files for shell hooks)
should be consumed via `imp.fragments` or `imp.fragmentsWith`.

Merging with base:
If both `foo.nix` (or `foo/default.nix`) and `foo.d/` exist, they are
combined: the base is imported first, then `foo.d/*.nix` fragments are
merged on top using `lib.recursiveUpdate`. This allows a base file to
define core outputs while fragments add or extend them.

Collision detection:
If multiple entries resolve to the same attribute name (e.g., `foo.nix`
and `foo/default.nix`), an error is thrown. The `.d` suffix is NOT a
collision - it explicitly merges with the base.

#### Example

Directory structure:

```
outputs/
  apps.nix
  checks.nix
  packages.d/
    00-core.nix       # { default = ...; foo = ...; }
    10-extras.nix     # { bar = ...; }
```

```nix
imp.treeWith lib import ./outputs
```

Returns:

```nix
{
  apps = <imported from apps.nix>;
  checks = <imported from checks.nix>;
  packages = { default = ...; foo = ...; bar = ...; };  # merged
}
```

#### Usage

```nix
(imp.withLib lib).tree ./outputs
```

Or with transform:

```nix
((imp.withLib lib).mapTree (f: f args)).tree ./outputs
imp.treeWith lib (f: f args) ./outputs
```

### fragments.nix

Fragment collection and composition for `.d` directories.

Follows the `.d` convention (like conf.d, init.d) where:

- `foo.d/` contains fragments that compose into `foo`
- Fragments are sorted by filename for deterministic ordering
- Composition strategy depends on content type

#### Supported fragment types

- `*.nix` - Nix expressions (imported directly)
- `*.sh` - Shell scripts (read as strings)
- `<fragment root>/default.nix` - Directory with default.nix entry point
- `<fragment root>/package.nix` - Fallback for default.nix

Directory fragments may be useful for bundling resources, e.g. agent skills.

#### Composition patterns

String concatenation (shellHook.d/):
shellHook.d/
00-base.sh
10-rust.sh
-> concatenated in order

List merging (packages.d/):
packages.d/
base.nix # returns [ pkgs.git ]
cargo-rail/ # directory with default.nix or package.nix
-> merged into single list

Attrset merging (env.d/):
env.d/
base.nix # returns { FOO = "bar"; }
extra.nix # returns { BAZ = "qux"; }
-> merged into single attrset

#### Usage

```nix
let
  fragments = imp.collectFragments ./shellHook.d;
in
pkgs.mkShell {
  shellHook = fragments.asString;
  # or: shellHook = lib.concatStringsSep "\n" fragments.list;
}
```

## Config Trees

### config-tree.nix

Builds a NixOS/Home Manager module where directory structure = option paths.

Each file receives module args (`{ config, lib, pkgs, ... }`) plus `extraArgs`,
and returns config values. The path becomes the option path:

- `programs/git.nix` -> `{ programs.git = <result>; }`
- `services/nginx/default.nix` -> `{ services.nginx = <result>; }`

#### Example

Directory structure:

```
home/
  programs/
    git.nix
    zsh.nix
  services/
    syncthing.nix
```

Example file (home/programs/git.nix):

```nix
{ pkgs, ... }: {
  enable = true;
  userName = "Alice";
}
```

#### Usage

```nix
{ inputs, ... }:
{
  imports = [ ((inputs.imp.withLib lib).configTree ./home) ];
}
```

Equivalent to manually writing:

```nix
programs.git = { enable = true; userName = "Alice"; };
programs.zsh = { ... };
services.syncthing = { ... };
```

With extra args:

```nix
((inputs.imp.withLib lib).configTreeWith { myArg = "value"; } ./home)
```

### merge-config-trees.nix

Merges multiple config trees into a single NixOS/Home Manager module.

Supports two merge strategies:

- `override` (default): Later trees override earlier (`lib.recursiveUpdate`)
- `merge`: Use module system's `mkMerge` for proper option merging

This enables composable features where one extends another:

```
features/
  shell/programs/{zsh,starship}.nix    # base shell config
  devShell/programs/{git,zsh}.nix      # extends shell, overrides zsh
```

#### Usage

Override strategy (default):

```nix
# devShell/default.nix
{ imp, ... }:
{
  imports = [
    (imp.mergeConfigTrees [ ../shell ./. ])
  ];
}
```

Or with merge strategy for concatenating list options:

```nix
{ imp, ... }:
{
  imports = [
    (imp.mergeConfigTrees { strategy = "merge"; } [ ../shell ./. ])
  ];
}
```

With `override`: later values completely replace earlier ones.
With `merge`: options combine according to module system rules:

- lists concatenate
- strings may error (use `mkForce`/`mkDefault` to control)
- nested attrs merge recursively

## Registry

### registry.nix

Registry: named module discovery and resolution.

Scans a directory tree and builds a nested attrset mapping names to paths.
Files reference modules by name instead of relative paths.

#### Example

```
nix/
  home/
    alice/default.nix
    bob.nix
  modules/
    nixos/base.nix
    home/base.nix
```

Produces:

```nix
{
  home = {
    __path = <nix/home>;
    alice = <path>;
    bob = <path>;
  };
  modules.nixos = { __path = <nix/modules/nixos>; base = <path>; };
}
```

Usage:

```nix
{ registry, ... }:
{
  imports = [ (imp registry.modules.nixos) ];  # directory
  imports = [ registry.modules.home.base ];    # file
}
```

Directories have `__path` so they work with `imp`.

## Export Sinks

### collect-exports.nix

Collects `__exports` declarations from directory trees.

Recursively scans `.nix` files for `__exports` attributes and collects them
with source paths for debugging and conflict detection. No nixpkgs dependency.

Static exports sit at the top level. Functor exports (`__functor`) are called
with stub args to extract declarations; values remain lazy thunks until use.

#### Export Syntax

Both flat string keys and nested attribute paths work:

```nix
# Flat string keys
{ __exports."sink.name".value = { config = ...; }; }

# Nested paths (enables static analysis)
{ __exports.sink.name.value = { config = ...; }; }

# Functor pattern for modules needing inputs
{
  __inputs = { foo.url = "..."; };
  __functor = _: { inputs, ... }:
    let mod = { ... };
    in { __exports.sink.name.value = mod; __module = mod; };
}
```

#### Arguments

pathOrPaths
: Directory, file, or list of paths to scan.

### export-sinks.nix

Materializes sinks from collected exports by applying merge strategies.

Takes `collectExports` output and produces usable Nix values (modules or
attrsets) by merging contributions according to their strategies.

#### Merge Strategies

- `merge`: Deep merge via `lib.recursiveUpdate` (last wins for primitives)
- `override`: Last writer completely replaces earlier values
- `list-append`: Concatenate lists (errors on non-lists)
- `mkMerge`: Module functions become `{ imports = [...]; }`;
  plain attrsets use `lib.mkMerge`

#### Example

```nix
buildExportSinks {
  lib = nixpkgs.lib;
  collected = {
    "nixos.role.desktop" = [
      { source = "/audio.nix"; value = { services.pipewire.enable = true; }; strategy = "merge"; }
      { source = "/wayland.nix"; value = { services.greetd.enable = true; }; strategy = "merge"; }
    ];
  };
  sinkDefaults = { "nixos.*" = "merge"; };
}
# => { nixos.role.desktop = { __module = { ... }; __meta = { ... }; }; }
```

#### Arguments

- `lib` (attrset): nixpkgs lib for merge operations.
- `collected` (attrset): Output from `collectExports`.
- `sinkDefaults` (attrset): Glob patterns to default strategies (e.g., `{ "nixos.*" = "merge"; }`).
- `enableDebug` (bool): Include `__meta` with contributor info (default: true).

## Host Configuration

### collect-hosts.nix

Scans directories for `__host` declarations and collects host metadata.

Recursively walks paths, importing each `.nix` file and extracting any
`__host` attrset. Returns host names mapped to declarations. Names derive
from directory names (for `default.nix`) or filenames (minus `.nix`).

Files and directories starting with `_` are excluded. Directories with
`default.nix` are treated as single modules; subdirectories are not scanned.

#### Type

```
collectHosts :: (path | [path]) -> {
  <hostName> = {
    __host = { system, stateVersion, bases?, sinks?, hmSinks?, modules?, user? };
    config = path | null;
    extraConfig = module | null;
    __source = string;
  };
}
```

#### Example

```nix
collectHosts ./registry/hosts
# => {
#   desktop = { __host = { system = "x86_64-linux"; ... }; config = ./desktop/config; };
#   server = { __host = { ... }; ... };
# }
```

#### Host Schema

```nix
{
  __host = {
    system = "x86_64-linux";
    stateVersion = "24.11";
    bases = [ "hosts.shared.base" ];       # registry paths to base config trees
    sinks = [ "shared.nixos" ];            # export sink paths for NixOS
    hmSinks = [ "shared.hm" ];             # export sink paths for Home Manager
    modules = [ "mod.nixos.ssh" ];         # or function: { registry, ... }: [ ... ]
    user = "alice";                        # HM integration username
  };
  config = ./config;
  extraConfig = { modulesPath, ... }: { }; # optional
}
```

Modules resolve as registry paths, `@`-prefixed input paths, or raw values.

### build-hosts.nix

Generates `nixosConfigurations` from collected host declarations.

Takes `collectHosts` output and produces NixOS system configurations for
`flake.nixosConfigurations`. Each host's `__host` schema controls module
assembly and Home Manager integration.

#### Type

```
buildHosts :: {
  lib, imp, hosts, flakeArgs, hostDefaults?
} -> { <hostName> = <nixosConfiguration>; }
```

#### Module Assembly Order

1. Merged config tree from `bases` + `config` paths
1. `home-manager.nixosModules.home-manager`
1. Resolved sink modules from `sinks`
1. Home Manager integration module (if `user` set)
1. Extra modules from `modules`
1. `extraConfig` module (if present)
1. `{ system.stateVersion = ...; }`

#### Path Resolution

Strings in `bases`, `sinks`, `hmSinks`, `modules` resolve as:

- `"hosts.shared.base"` -> `registry.hosts.shared.base`
- `"@nixos-wsl.nixosModules.default"` -> `inputs.nixos-wsl.nixosModules.default`

#### Modules as Function

The `modules` field can be a function receiving `{ registry, inputs, exports }`
for direct registry access, enabling static analysis:

```nix
__host = {
  modules = { registry, ... }: [
    registry.mod.os.desktop.keyboard
    registry.mod.niri
  ];
};
```

#### Home Manager Integration

When `user` is set:

```nix
home-manager = {
  useGlobalPkgs = true;
  useUserPackages = true;
  extraSpecialArgs = { inputs, exports, imp, registry };
  users.${user}.imports = [ <hmSinks> <registry.users.${user}> ];
};
```

#### Example

```nix
buildHosts {
  inherit lib imp;
  hosts = collectHosts ./registry/hosts;
  flakeArgs = { inherit self inputs registry exports; };
  hostDefaults = { system = "x86_64-linux"; };
}
# => { desktop = <nixosConfiguration>; server = <nixosConfiguration>; }
```

## Flake Integration

### flake-module.nix

flake-parts module, defines `imp.*` options.

### options-schema.nix

Shared options schema for imp.\* options.

### collect-inputs.nix

`__inputs` collection from flake inputs.

### format-flake.nix

Formats flake inputs and generates flake.nix content.
Standalone implementation - no nixpkgs dependency, only builtins.

#### Example

```nix
formatInputs { treefmt-nix = { url = "..."; }; }
# => "treefmt-nix = {\n  url = \"...\";\n};\n"

formatFlake {
  description = "My flake";
  coreInputs = { nixpkgs.url = "..."; };
  collectedInputs = { treefmt-nix.url = "..."; };
  outputsFile = "./outputs.nix";
}
# => full flake.nix content as string
```

## Submodules

### formatter/default.nix

Reusable treefmt configuration with opinionated defaults.
