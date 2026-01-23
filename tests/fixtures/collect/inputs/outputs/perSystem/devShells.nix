# Test fixture: file with __inputs for devenv
{
  __inputs.devenv = {
    url = "github:cachix/devenv";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  __functor = _: { pkgs, inputs, ... }: {
    default = inputs.devenv.lib.mkShell { inherit pkgs; };
  };
}
