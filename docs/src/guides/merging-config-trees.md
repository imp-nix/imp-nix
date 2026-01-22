# Merging Config Trees

Say you want to import a shell configuration in combination with a dev tools configuration. Each is a config tree with its own `programs/zsh.nix`. You want to compose them, using the shell config as a base and layering dev tools on top, without duplicating files or manually merging attrsets.

```nix
{ imp, registry, ... }:
{
  imports = [
    (imp.mergeConfigTrees [
      registry.modules.home.features.shell
      registry.modules.home.features.devTools
      ./.  # local overrides
    ])
  ];
}
```

`mergeConfigTrees` takes multiple config tree sources and combines them into a single module. Later sources override earlier ones.

## Strategies

The `override` strategy (default) replaces values completely using `recursiveUpdate`:

```nix
imp.mergeConfigTrees { strategy = "override"; } [ ../base ./. ]
```

If base sets `shell.aliases.ll = "ls -l"` and local sets `shell.aliases.ll = "ls -la"`, you get `"ls -la"`.

The `merge` strategy uses `mkMerge`, which follows NixOS module system rules:

```nix
imp.mergeConfigTrees { strategy = "merge"; } [ ../base ./. ]
```

With `merge`, multiple definitions of the same option are combined according to NixOS module semantics. Lists concatenate. Attrsets recursively merge. Strings (e.g. shell init text content) concatenate rather than one replacing the other.

Use `lib.mkBefore`/`lib.mkAfter` to control ordering within merged values:

```nix
# programs/zsh.nix
{ lib, ... }:
{
  initContent = lib.mkAfter ''
    export EDITOR="nvim"
  '';
  shellAliases.nb = "nix build";
}
```

## Extra arguments

Pass additional arguments to all files in the merged trees:

```nix
imp.mergeConfigTrees {
  strategy = "merge";
  extraArgs = { secrets = ./secrets; };
} [ ../base ./. ]
```

## Shorthand

If you don't need options, just pass the list directly:

```nix
imp.mergeConfigTrees [ ../base ./. ]  # uses "override"
```
