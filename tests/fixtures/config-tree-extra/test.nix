# Test file that uses customArg passed via configTreeWith
{ customArg, ... }:
{
  fromCustomArg = customArg;
}
