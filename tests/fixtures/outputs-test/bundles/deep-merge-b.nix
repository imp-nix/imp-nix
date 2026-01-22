# Second contributor to deep merge test
{
  __outputs.perSystem.packages.deepTest = {
    value = { pkgs, ... }: {
      nested = {
        fromB = "value-b";
        shared = { b = 2; };
      };
    };
    strategy = "merge";
  };
}
