# Bundle using config from config/default.nix
{ config, ... }:
{
  __outputs.perSystem.packages.config-dir-test = { pkgs, ... }:
    pkgs.writeText "config-dir-test" "name=${config.name} value=${toString config.value}";
}
