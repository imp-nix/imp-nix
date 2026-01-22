# Test list-append strategy
{
  __exports."nixos.role.desktop.packages" = {
    value = [ "htop" "vim" ];
    strategy = "list-append";
  };
}
