/**
  Usage: nix-unit --flake .#tests
*/
{ self, lib, ... }: import (self + "/tests") { inherit lib; }
