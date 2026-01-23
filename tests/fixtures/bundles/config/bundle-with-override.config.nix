# Outer config (owned by parent project, overrides inner)
{
  message = "from outer";
  outerOnly = "only in outer";
  nested = {
    b = 20;
    c = 30;
  };
}
