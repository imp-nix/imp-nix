# Export Sinks

Modules typically pull in dependencies: you write `imports = [ registry.features.audio ];` and the configuration loads. Export sinks reverse this. A feature declares "push my configuration into sink X" and consumers import the aggregated result. Multiple features targeting the same sink merge automatically according to their strategy.

This solves composition where features shouldn't know about their consumers. A desktop audio stack exports to `nixos.role.desktop`, a Wayland compositor exports to the same sink, and the desktop role configuration imports the merged result without listing every feature explicitly.

## Declaration

Files declare exports using the `__exports` attribute with nested attribute paths:

```nix
{
  __exports.nixos.role.desktop.services = {
    value = {
      pipewire.enable = true;
      wireplumber.enable = true;
    };
    strategy = "merge";
  };

  __module = { ... }: {
    services.pipewire.enable = true;
  };
}
```

The nested path `__exports.nixos.role.desktop.services` identifies the sink. All exports targeting this path merge into a single value. The `strategy` field controls merge behavior; `merge` performs deep attrset merging where later values override earlier ones for non-attrset types.

String keys also work (`__exports."nixos.role.desktop.services"`), but nested attributes enable static analysis by tools that scan for registry references without evaluation.

If a file needs arguments (like `inputs` or `pkgs`), use the `__functor` pattern so `__exports` remains accessible without function evaluation:

```nix
{
  __exports.hm.role.desktop = {
    value = { programs.fish.enable = true; };
  };

  __functor = _: { inputs, ... }: {
    __module = inputs.foo.lib.buildModule;
  };
}
```

Multiple exports from a single file work by adding more paths under `__exports`:

```nix
{
  __exports.nixos.role.desktop.services = {
    value = { greetd.enable = true; };
    strategy = "merge";
  };
  __exports.nixos.role.desktop.programs = {
    value = { wayland.enable = true; };
  };
}
```

Omitting `strategy` uses the sink's default strategy, configured per-pattern in the flake module options.

## Merge strategies

Exports specify how values combine when multiple sources write to the same sink:

**merge** performs `lib.recursiveUpdate`, recursing into nested attrsets. Primitive values (strings, bools, numbers) take the last writer's value, determined by alphabetical source path sorting. Most sinks use this.

**override** replaces the entire value. Last writer wins completely. Useful for sinks where composition doesn't make sense, like theme selection or hostname.

**list-append** concatenates lists in source path order. Fails if values aren't lists. Works for package lists or import arrays where order matters.

**mkMerge** uses the module system's `lib.mkMerge` for proper NixOS/Home Manager option semantics. Lists concatenate, conflicting options error unless one uses `mkForce` or `mkDefault`. Appropriate when the sink contains module fragments with typed options.

Strategy conflicts (different strategies targeting the same sink) fail at evaluation time with a clear error listing all contributors and their strategies.

## Sink structure

The `buildExportSinks` function scans paths for `__exports` declarations, groups them by sink key, applies merge strategies, and produces a nested attrset:

```nix
exports = {
  nixos.role.desktop.services = {
    __module = {
      pipewire.enable = true;
      greetd.enable = true;
    };
    __meta = {
      contributors = [
        "/nix/features/audio/pipewire.nix"
        "/nix/features/wayland/base.nix"
      ];
      strategy = "merge";
    };
  };
};
```

Each leaf node contains `__module` with the merged value and `__meta` with contributor paths and the effective strategy. Consumers import `__module`:

```nix
# registry/mod/features/audio/default.nix
{
  __exports.desktop.nixos = {
    value = { services.pipewire.enable = true; };
  };
}
```

Disabling debug mode (`enableDebug = false`) removes `__meta` and returns raw values without wrapping, trading introspection for slightly simpler access.

## Flake integration

The flake-parts module automatically builds and exposes export sinks when `imp.exports.enable = true` (the default). It scans both `imp.registry.src` and `imp.src`:

```nix
{
  imp = {
    src = ./outputs;
    registry.src = ./nix/registry;
    exports = {
      enable = true;
      sinkDefaults = {
        "nixos.*" = "merge";
        "hm.*" = "mkMerge";
        "packages.*" = "list-append";
      };
    };
  };
}
```

Sink patterns use glob syntax where `*` matches any suffix. The first matching pattern provides the default strategy for exports that don't specify one.

The resulting sinks appear as `flake.exports` in your flake outputs. External flakes importing yours can reference these sinks directly. Within the same flake, outputs see them as `inputs.self.exports`.

## When to use exports

Exports fit scenarios where features compose toward a shared aggregate but shouldn't couple to specific consumers. Desktop roles pulling in audio, graphics, networking, and input features work well. Each feature exports its requirements independently; the role imports the merged configuration.

Direct imports remain simpler for explicit dependencies where modules know exactly what they need. Use exports when the dependency graph inverts: features declaring where they belong rather than roles declaring what they contain.

The pattern also works for cross-cutting concerns that many configurations share. Monitoring agents, backup configurations, or security hardening profiles can export to multiple role sinks without those roles needing to track every available plugin.
