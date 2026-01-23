# Bundle with only outer config (no inner config.nix)
{ config, ... }:
{
  __outputs.perSystem.packages.outer-only-test = { pkgs, ... }:
    pkgs.writeText "outer-only" "source=${config.source} value=${toString config.value}";
}
