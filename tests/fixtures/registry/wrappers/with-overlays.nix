# Registry wrapper with overlays
# Uses __functor pattern so collectInputs can extract __inputs without calling the function
{
  __inputs = {
    nur.url = "github:nix-community/NUR";
    nur.inputs.nixpkgs.follows = "nixpkgs";
  };

  __functor =
    _:
    { inputs, ... }:
    {
      __overlays.nur = _final: _prev: { nurPackages = { }; };

      __module =
        { lib, ... }:
        {
          options.test.withOverlays = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
        };
    };
}
