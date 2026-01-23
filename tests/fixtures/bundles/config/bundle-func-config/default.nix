# Bundle using function config
{ config, pkgs, ... }:
{
  __outputs.perSystem.packages.func-config-test =
    pkgs.writeText "func-config" config.greeting;
}
