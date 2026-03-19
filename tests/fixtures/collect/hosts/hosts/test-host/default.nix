# Test host with modules as a list (raw path resolution)
{
  __host = {
    system = "x86_64-linux";
    stateVersion = "24.11";
    modules = [
      ../../mod/test-module.nix
    ];
  };
  config = ./config;
}
