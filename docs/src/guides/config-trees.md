# Config Trees

Config trees are option attrsets derrived from directory structure. The file path _is_ the option path: `programs/git.nix` sets `programs.git`. That's it.

```
home/
  programs/
    git.nix      # -> programs.git = { ... }
    zsh.nix      # -> programs.zsh = { ... }
  services/
    gpg-agent.nix # -> services.gpg-agent = { ... }
```

Each file returns just that option's value:

```nix
# home/programs/git.nix
{
  enable = true;
  userName = "Alice";
}
```

Want to know if git is configured? Check if `programs/git.nix` exists. The directory becomes a table of contents.

## Usage

```nix
{ inputs, lib, ... }:
{
  imports = [ ((inputs.imp.withLib lib).configTree ./home) ];
}
```

With registry (when using the flake-parts module):

```nix
{ imp, ... }:
{
  imports = [ (imp.configTree ./.) ];
}
```

## Files can be functions

When you need access to module arguments like `pkgs` or `config`:

```nix
# programs/git.nix
{ pkgs, ... }:
{
  enable = true;
  package = pkgs.gitFull;
}
```

Config tree files receive standard module arguments (`config`, `lib`, `pkgs`, etc.) plus any extras you pass.

## Extra arguments

```nix
imp.configTreeWith { secrets = ./secrets; } ./config
```

Files then receive `secrets` alongside standard module args.

## Building attribute trees

Config trees are for NixOS/Home Manager modules. For non-module uses (packages, apps, arbitrary attrsets), use `.tree` or `.treeWith`:

```nix
let packages = (imp.withLib lib).tree ./packages; in
packages.hello  # -> imported from ./packages/hello.nix
```

When files export functions needing arguments:

```nix
# packages/hello.nix
{ pkgs }: pkgs.hello

# Build with treeWith
imp.treeWith lib (f: f { inherit pkgs; }) ./packages
# => { hello = <derivation>; }
```

## Transformation patterns

The second argument to `treeWith` is applied to every imported value. Common uses:

```nix
# Call each file with arguments
imp.treeWith lib (f: f { inherit pkgs lib; }) ./outputs

# Add metadata to all derivations
imp.treeWith lib (drv: drv // { meta.priority = 5; }) ./packages

# Wrap each module with common imports
imp.treeWith lib (mod: { imports = [ mod commonModule ]; }) ./modules
```

For multiple transformations, chain `.mapTree`:

```nix
(imp.withLib lib)
  .mapTree (f: f { inherit pkgs; })
  .mapTree (drv: drv.overrideAttrs (old: { meta.license = lib.licenses.mit; }))
  .tree ./packages
```
