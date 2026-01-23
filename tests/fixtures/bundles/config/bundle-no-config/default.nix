# Bundle without config - should get empty attrset
{ config, ... }:
{
  __outputs.perSystem.packages.no-config-test = { pkgs, ... }:
    pkgs.writeText "no-config" (if config == { } then "empty" else "not-empty");
}
