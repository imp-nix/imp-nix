# Test fixture: file with __inputs using functor pattern
{
  __inputs.treefmt-nix = {
    url = "github:numtide/treefmt-nix";
  };

  __functor = _: { pkgs, inputs, ... }:
    inputs.treefmt-nix.lib.evalModule pkgs {
      projectRootFile = "flake.nix";
    };
}
