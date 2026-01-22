# First contributor to deep merge test
{
  __outputs.perSystem.packages.deepTest = {
    value = { pkgs, ... }: {
      nested = {
        fromA = "value-a";
        shared = { a = 1; };
      };
    };
    strategy = "merge";
  };
}
