# Home Manager

Home Manager configurations using registry references and config tree composition.

```
registry/
  users/
    alice/
      default.nix
      programs/
        git.nix
        zsh.nix
  modules/
    home/
      features/
        shell/
          default.nix
          programs/
            zsh.nix
            starship.nix
        devTools/
          programs/
            git.nix
            neovim.nix
```

## User configuration

The user definition imports feature modules from the registry and adds personal settings from a local config tree:

```nix
# registry/users/alice/default.nix
{ imp, registry, ... }:
{
  imports = [
    registry.modules.home.features.shell
    registry.modules.home.features.devTools
    (imp.configTree ./.)
  ];

  home.username = "alice";
  home.homeDirectory = "/home/alice";
  home.stateVersion = "24.05";
}
```

## Personal overrides

Files in the user's directory add to or replace values from feature modules. The NixOS module system merges definitions according to each option's type: lists concatenate, attrsets merge recursively, and singular values take the last definition.

```nix
# registry/users/alice/programs/git.nix
{
  enable = true;
  userName = "Alice Smith";
  userEmail = "alice@example.com";
  extraConfig.init.defaultBranch = "main";
  delta.enable = true;
}
```

```nix
# registry/users/alice/programs/zsh.nix
{ lib, ... }:
{
  shellAliases.projects = "cd ~/projects";
  initContent = lib.mkAfter ''
    export EDITOR="nvim"
  '';
}
```

## Feature modules

Each feature is a config tree that can be imported independently:

```nix
# registry/modules/home/features/shell/default.nix
{ imp, ... }:
{
  imports = [ (imp.configTree ./.) ];
}
```

```nix
# registry/modules/home/features/shell/programs/zsh.nix
{
  enable = true;
  enableCompletion = true;
  autosuggestion.enable = true;
  syntaxHighlighting.enable = true;
  history = { size = 10000; ignoreDups = true; };
  shellAliases = { ll = "ls -la"; ".." = "cd .."; };
}
```

## Using mergeConfigTrees

When features share files at the same paths (both shell and devTools have `programs/zsh.nix`), use `mergeConfigTrees` to compose them properly:

```nix
{ imp, registry, ... }:
{
  imports = [
    (imp.mergeConfigTrees { strategy = "merge"; } [
      registry.modules.home.features.shell
      registry.modules.home.features.devTools
      ./.
    ])
  ];
  home.username = "alice";
  home.homeDirectory = "/home/alice";
  home.stateVersion = "24.05";
}
```

## Flake output

```nix
# outputs/homeConfigurations/alice@workstation.nix
{ inputs, nixpkgs, imp, registry, ... }:
inputs.home-manager.lib.homeManagerConfiguration {
  pkgs = nixpkgs.legacyPackages.x86_64-linux;
  extraSpecialArgs = { inherit inputs imp registry; };
  modules = [ (import registry.users.alice) ];
}
```
