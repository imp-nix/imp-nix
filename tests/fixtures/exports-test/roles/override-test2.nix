# Second override - should win due to alphabetical ordering
{
  __exports."test.override" = {
    value = { foo = "second"; bar = "added"; };
    strategy = "override";
  };
}
