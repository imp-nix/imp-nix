# More packages to test list-append merging
{
  __exports."nixos.role.desktop.packages" = {
    value = [ "git" "tmux" ];
    strategy = "list-append";
  };
}
