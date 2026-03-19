# Test host with modules as a function (input access)
{
  __host = {
    system = "x86_64-linux";
    stateVersion = "24.11";
    modules = { inputs, ... }: [
      inputs.test.module
    ];
  };
  config = ./config;
}
