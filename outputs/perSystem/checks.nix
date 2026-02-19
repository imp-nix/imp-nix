{
  __inputs.nix-unit.url = "github:nix-community/nix-unit";

  __functor =
    _:
    {
      self,
      self',
      pkgs,
      system,
      inputs,
      ...
    }:
    {
      nix-unit =
        pkgs.runCommand "nix-unit-tests"
          {
            nativeBuildInputs = [ inputs.nix-unit.packages.${system}.default ];
          }
          ''
            export HOME=$TMPDIR
            nix-unit --expr 'import ${self}/tests { lib = import ${inputs.nixpkgs}/lib; }'
            touch $out
          '';
    };
}
