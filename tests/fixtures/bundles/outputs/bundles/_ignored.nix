# Should be ignored due to underscore prefix
{
  __outputs.perSystem.packages.shouldNotExist = { pkgs, ... }:
    pkgs.hello;
}
