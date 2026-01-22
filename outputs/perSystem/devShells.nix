{
  __inputs.nix-unit.url = "github:nix-community/nix-unit";

  __functor =
    _:
    {
      pkgs,
      system,
      inputs,
      ...
    }:
    {
      default = pkgs.mkShell {
        packages = [
          inputs.nix-unit.packages.${system}.default
        ];
      };
    };
}
