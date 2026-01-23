# Wayland base feature exporting to desktop role
{
  __exports = {
    "nixos.role.desktop.services" = {
      value = {
        greetd.enable = true;
      };
      strategy = "merge";
    };
    "nixos.role.desktop.programs" = {
      value = {
        wayland.enable = true;
      };
    };
  };

  __module = { ... }: {
    programs.wayland.enable = true;
  };
}
