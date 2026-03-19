# Plain attrset with __module (no function wrapper)
{
  __inputs = {
    static.url = "github:static/input";
  };

  __module =
    { lib, ... }:
    {
      options.test.attrsetModule = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
    };
}
