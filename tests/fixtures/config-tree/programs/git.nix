# programs/git.nix - becomes { programs.git = { ... }; }
{ pkgs, ... }:
{
  enable = true;
  userName = "Test User";
}
