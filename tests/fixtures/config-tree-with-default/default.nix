# This default.nix should be skipped when configTree is called on this directory
{ imp, ... }:
{
  # This import would cause infinite recursion if not skipped
  imports = [ (imp.configTree ./.) ];
}
