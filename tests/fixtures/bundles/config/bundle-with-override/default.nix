# Bundle testing inner/outer config merge
{ config, ... }:
{
  __outputs.perSystem.packages.override-test = { pkgs, ... }:
    pkgs.writeText "override-test" ''
      message: ${config.message}
      innerOnly: ${config.innerOnly}
      outerOnly: ${config.outerOnly}
      nested.a: ${toString config.nested.a}
      nested.b: ${toString config.nested.b}
      nested.c: ${toString config.nested.c}
    '';
}
