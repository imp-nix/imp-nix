{ lib }:
let
  imp = import ./../src;
  args = { inherit lib imp; };
in
(import ./core.nix args)
// (import ./imp.nix args)
// (import ./tree.nix args)
// (import ./flake-file.nix args)
// (import ./registry.nix args)
// (import ./collect.nix args)
// (import ./imports.nix args)
// (import ./exports.nix args)
// (import ./hosts.nix args)
// (import ./fragments.nix args)
