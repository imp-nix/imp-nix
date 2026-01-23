# Bundle that uses config - receives config in args
{ config, pkgs, ... }:
{
  __outputs.perSystem.packages.config-test = pkgs.writeText "config-test" config.message;
}
