# Registry wrapper with nested options and imports usage
# Uses __functor pattern so collectInputs can extract __inputs without calling the function
{
  __inputs = {
    nested.url = "github:nested/dep";
  };

  __functor =
    _:
    { inputs, ... }:
    {
      __module =
        { lib, config, ... }:
        {
          options.test.nested = {
            enable = lib.mkEnableOption "nested test";
            value = lib.mkOption {
              type = lib.types.str;
              default = "default-value";
            };
          };
          config = lib.mkIf config.test.nested.enable {
            test.nested.value = "enabled-value";
          };
        };
    };
}
