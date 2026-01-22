# Test host with modules as a function (direct registry access)
{
  __host = {
    system = "x86_64-linux";
    stateVersion = "24.11";
    modules = { registry, ... }: [
      registry.mod.test-module
    ];
  };
  config = ./config;
}
