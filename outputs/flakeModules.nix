/**
  Usage: imports = [ inputs.imp.flakeModules.default ];
*/
{ self, ... }:
{
  default = self + "/src/flake-module.nix";
}
