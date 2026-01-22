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
      tests = {
        type = "app";
        meta.description = "Run imp unit tests";
        program = toString (
          pkgs.writeShellScript "run-tests" ''
            ${inputs.nix-unit.packages.${system}.default}/bin/nix-unit --flake .#tests
          ''
        );
      };
    };
}
