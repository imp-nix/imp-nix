# Test host with modules as a list (string resolution)
{
  __host = {
    system = "x86_64-linux";
    stateVersion = "24.11";
    modules = [
      "mod.test-module"
    ];
  };
  config = ./config;
}
