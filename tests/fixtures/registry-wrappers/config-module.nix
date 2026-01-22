# Registry wrapper whose __module sets config values
# Uses __functor pattern so collectInputs can extract __inputs without calling the function
{
  __inputs = {
    foo.url = "github:foo/bar";
  };

  __functor =
    _:
    { inputs, ... }:
    {
      __module =
        { lib, ... }:
        {
          config.test.fromRegistry = "hello from registry wrapper";
        };
    };
}
