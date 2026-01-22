# Directory-Based Imports

Point imp at a directory and it imports every `.nix` file inside, recursively:

```nix
{ inputs, ... }:
{
  imports = [ (inputs.imp ./modules) ];
}
```

This replaces the manual listing you'd otherwise maintain:

```nix
{
  imports = [
    ./modules/networking.nix
    ./modules/users/alice.nix
    ./modules/users/bob.nix
    ./modules/services/nginx.nix
  ];
}
```

Add a file, it gets imported. Delete it, it's gone. The filesystem is the source of truth.

## Filtering

Sometimes you don't want everything. The chainable filter methods let you narrow what gets imported:

```nix
let imp = inputs.imp.withLib lib; in
{
  imports = [
    (imp.filter (lib.hasInfix "/services/") ./modules)
    (imp.filterNot (lib.hasSuffix ".test.nix") ./modules)
    (imp.match ".*/(users|groups)/.*" ./modules)
  ];
}
```

Filters compose: calling `.filter` multiple times ANDs them together. Each filter method returns a new imp instance with the additional predicate, so you can chain them.

Note the `.withLib lib` call. Filter predicates like `lib.hasInfix` come from nixpkgs; `withLib` makes them available. The flake-parts module handles this automatically.

## Getting the file list

If you need the raw list of paths rather than importing them:

```nix
(imp.withLib lib).leaves ./modules
# => [ "/path/to/modules/networking.nix" "/path/to/modules/users/alice.nix" ... ]
```

The `.leaves` method is useful for debugging or when you need to process paths before importing.
