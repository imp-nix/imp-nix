# Standard NixOS module (not a registry wrapper)
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
