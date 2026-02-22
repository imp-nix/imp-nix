# Imp 😈

Imp maps filesystem structure to Nix attribute sets, `.nix` file becomes attributes, with nesting following the directory hierarchy. This works for flake outputs, NixOS modules and development environments.

Simple file drop-ins with no explicit import wires are the core of Imp. Add a file (and track with git) and it will be imported and evaluated. Renames and deletions are automatically taken care of during eval.

```nix
outputs = inputs: inputs.imp.tree ./src;
# src/foo/bar.nix -> { foo.bar = <contents>; }
```

## Development projects

For a typical dev project, imp generates flake outputs from a directory structure:

```
nix/
  outputs/
    perSystem/
      packages.d/
        cli.nix         # packages.cli
        lib.nix         # packages.lib
      devShells.d/
        rust.nix        # devShells components
        lint.nix
      formatter.d/
        nix.nix         # formatter components
        rust.nix
      checks.nix        # checks.*
```

Fragment directories (`.d`) merge their contents, so multiple files can contribute to `devShells.default` or `formatter`. Configure imp with flake-parts:

```nix
{
  imports = [ inputs.imp.flakeModules.default ];
  imp.src = ./nix/outputs;
}
```

In monorepos, `srcDiscover` can auto-add workspace-local outputs roots so root and
subprojects share the same `nix/outputs/perSystem` shape:

```nix
{
  imports = [ inputs.imp.flakeModules.default ];
  imp = {
    src = ./nix/outputs;
    srcDiscover = [
      {
        root = ./workspaces;
        suffix = "nix/outputs";
      }
    ];
  };
}
```

Post-merge transforms let you wrap or rename full per-system sections after
all modules are merged:

```nix
{
  __outputs.perSystemTransforms.devShells = shells:
    shells // {
      default = shells."my-workspace";
    };
}
```

Transforms can also be defined as per-system arg builders when they need
shared helpers from `imp.args`:

```nix
# flake.nix
{
  imp = {
    src = ./nix/outputs;
    args.nciLib = import ./nix/nci/lib.nix;
  };
}

# workspace output file
{
  __outputs.perSystemTransforms.devShells = { nciLib, ... }:
    nciLib.mkWorkspaceShellTransform {
      workspace = "my-workspace";
      aliases = [ "default" ];
    };
}
```

## NixOS configurations

For system configuration, imp adds registries, export sinks, and host declarations:

```
mod/
  os/
    base.nix          # NixOS modules
    audio.nix
  hm/
    git.nix           # Home Manager modules
    shell.nix
hosts/
  desktop/
    default.nix       # __host declaration
    hardware.nix
    networking.nix
users/
  alice.nix
```

Modules export to named sinks by role:

```nix
# mod/os/audio.nix
let
  mod = { ... }: {
    services.pipewire.enable = true;
  };
in
{
  __exports.desktop.os.value = mod;
  __module = mod;
}
```

Hosts declare which sinks to include:

```nix
# hosts/desktop/default.nix
{
  __host = {
    system = "x86_64-linux";
    stateVersion = "24.11";
    sinks = [ "shared.os" "desktop.os" ];
    hmSinks = [ "shared.hm" "desktop.hm" ];
    user = "alice";
  };
}
```

Imp generates `nixosConfigurations.desktop`, importing the specified sinks and wiring Home Manager. Configuration files in the same directory (`hardware.nix`, `networking.nix`) are imported automatically.

```nix
{
  imports = [ inputs.imp.flakeModules.default ];
  imp = {
    src = ./outputs;
    registry.src = [ ./mod ./hosts ./users ];
    hosts.enable = true;
    exports.enable = true;
  };
}
```

## Input collection

Declare flake inputs where they're used:

```nix
# hosts/wsl/default.nix
{
  __inputs.nixos-wsl.url = "github:nix-community/NixOS-WSL";

  __host = {
    system = "x86_64-linux";
    modules = [ inputs.nixos-wsl.nixosModules.default ];
  };
}
```

Run `nix run .#imp-flake` to regenerate `flake.nix` with collected inputs.

## Documentation

Reference and conceptual documentation is colocated with implementation in
`src/*.nix` `/** */` comments.
