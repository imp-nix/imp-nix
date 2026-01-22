# Test __functor pattern with exports
{
  __exports."hm.role.desktop" = {
    value = { programs.fish.enable = true; };
    strategy = "merge";
  };

  __functor = _: { inputs, ... }: {
    __module = { ... }: {
      programs.fish.enable = true;
    };
  };
}
