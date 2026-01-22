# Collect Inputs

Flake inputs accumulate at the top of `flake.nix`, divorced from the code that uses them. A formatter needs `treefmt-nix`; that fact is visible only if you read both the inputs block and the formatter definition and connect the dots.

Input collection inverts this. Declare inputs next to the code that uses them:

```nix
# outputs/perSystem/formatter.nix
{
  __inputs.treefmt-nix.url = "github:numtide/treefmt-nix";

  __functor = _: { pkgs, inputs, ... }:
    inputs.treefmt-nix.lib.evalModule pkgs {
      projectRootFile = "flake.nix";
      programs.nixfmt.enable = true;
    };
}
```

imp scans your codebase for `__inputs` declarations and regenerates `flake.nix` with all of them collected.

## How it works

The `__functor` pattern separates declaration from evaluation. When imp-flake runs, it reads `__inputs` from each file without calling the functor, collecting all declarations into the generated `flake.nix`. At evaluation time, the functor receives the full `inputs` attrset containing everything declared across all files, plus your core inputs.

This matters because flake inputs must be known statically. You can't compute a flake input URL at runtime. The functor pattern lets files declare what they need (statically extractable) while still receiving runtime arguments like `pkgs` and `inputs`.

## The functor pattern

Files with `__inputs` must be attrsets with `__functor`. The functor receives flake-parts arguments and returns the actual output value:

```nix
{
  __inputs = {
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  __functor = _: { pkgs, inputs, ... }:
    inputs.treefmt-nix.lib.evalModule pkgs {
      projectRootFile = "flake.nix";
      programs.nixfmt.enable = true;
    };
}
```

The first argument to `__functor` is the attrset itself (ignored here with `_`). The second is the flake-parts args. Access your declared inputs through `inputs.treefmt-nix`, not as a direct destructured argument. The input name becomes an attribute on `inputs` after flake resolution.

For perSystem files, the functor receives `pkgs`, `lib`, `system`, `self`, `self'`, `inputs`, `inputs'`, plus `imp` and `registry` if configured. Flake-level files receive `lib`, `self`, `inputs`, `config`, `systems`, and optionally `exports`.

## Setup

```nix
imp = {
  src = ../outputs;
  flakeFile = {
    enable = true;
    coreInputs = import ./inputs.nix;
    outputsFile = "./nix/flake";
  };
};
```

Core inputs (nixpkgs, flake-parts, imp itself) belong in a separate `inputs.nix` that `coreInputs` imports. Single-use dependencies go in `__inputs` in the file that needs them. After adding or modifying `__inputs` declarations, regenerate with `nix run .#imp-flake`.

## Conflicts

If two files declare the same input name with different URLs, imp-flake errors with both sources listed. Move the shared input to `coreInputs` to resolve this. Identical declarations across files are deduplicated silently.
