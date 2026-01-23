# top-level.nix - becomes { top-level = { ... }; }
{ lib, ... }:
{
  value = "top";
  computed = lib.concatStrings [ "a" "b" ];
}
