# Basic registry wrapper: attrset with __inputs and __functor returning __module
# Uses __functor pattern so collectInputs can extract __inputs without calling the function
{
  __inputs = {
    example.url = "github:example/repo";
  };

  __functor =
    _:
    { inputs, ... }:
    {
      __module =
        { config, lib, ... }:
        {
          options.test.basic = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
        };
    };
}
