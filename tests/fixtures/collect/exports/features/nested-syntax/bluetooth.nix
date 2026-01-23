# Feature using nested attribute syntax for exports (new syntax)
{
  # Nested attribute path instead of string key
  __exports.nixos.role.desktop.services = {
    value = {
      bluetooth = {
        enable = true;
        powerOnBoot = true;
      };
    };
    strategy = "merge";
  };

  __module = { ... }: {
    hardware.bluetooth.enable = true;
  };
}
