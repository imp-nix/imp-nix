# Feature that exports to desktop role
{
  __exports."nixos.role.desktop.services" = {
    value = {
      pipewire = {
        enable = true;
        alsa.enable = true;
      };
    };
    strategy = "merge";
  };

  # Standard module (for direct imports)
  __module = { ... }: {
    services.pipewire.enable = true;
  };
}
