# Another function that receives args
{ prefix, ... }:
{
  extra = { name = "${prefix}-extra"; };
}
