# services/nginx/default.nix - becomes { services.nginx = { ... }; }
# Using default.nix to test directory-as-module pattern
{ ... }:
{
  enable = true;
  recommendedGzipSettings = true;
}
