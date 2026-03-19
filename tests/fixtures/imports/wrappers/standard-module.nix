# Standard NixOS module (not a module wrapper)
{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.test.standard = lib.mkOption {
    type = lib.types.bool;
    default = true;
  };
}
