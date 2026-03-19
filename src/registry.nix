/**
  Anchor ID: IMP_ANCHOR_REGISTRY
  Registry: named module discovery and resolution.

  Scans a directory tree and builds a nested attrset mapping names to paths.
  Files reference modules by name instead of relative paths.

  # Example

  ```
  nix/
    home/
      alice/default.nix
      bob.nix
    modules/
      nixos/base.nix
      home/base.nix
  ```

  Produces:

  ```nix
  {
    home = {
      __path = <nix/home>;
      alice = <path>;
      bob = <path>;
    };
    modules.nixos = { __path = <nix/modules/nixos>; base = <path>; };
  }
  ```

  Usage:

  ```nix
  { registry, ... }:
  {
    imports = [ (imp registry.modules.nixos) ];  # directory
    imports = [ registry.modules.home.base ];    # file
  }
  ```

  Directories have `__path` so they work with `imp`.
  In the flake module, `imp.registry.modules` can inject/override entries,
  letting external inputs or hand-picked modules live at registry paths.
*/
{
  lib,
  filterf ? _: true,
}:
let
  fs = import ./fs-model.nix;
  utils = import ./lib.nix;
  inherit (utils) isRegistryNode toPath;

  /**
    Build registry from a directory. Each directory gets `__path` plus child entries.

    # Arguments

    * `root` (path): Root directory path to scan.
  */
  buildRegistry =
    root:
    let
      entries = fs.listDir {
        dir = root;
        inherit filterf;
        normalize = fs.normalizeAttrName { };
        entryPointNames = [ "default.nix" ];
      };

      checkCollisions = fs.selectUniqueByAttrName {
        scope = "imp.registry";
        entries = builtins.filter (
          entry: entry.included && ((entry.isRegular && entry.isNixFile) || entry.isDirectory)
        ) entries;
      };

      processSource =
        attrName: source:
        let
          inherit (source) path;
        in
        if source.isRegular then
          path
        else
          if source.hasEntryPoint then path else { __path = path; } // buildRegistry path;
    in
    lib.mapAttrs processSource checkCollisions;

  /**
    Flatten registry to dot-notation paths.

    ```nix
    flattenRegistry registry
    # => { home.alice = <path>; modules.nixos.base = <path>; }
    ```
  */
  flattenRegistry =
    registry:
    let
      flatten =
        prefix: attrs:
        lib.foldlAttrs (
          acc: name: value:
          let
            key = if prefix == "" then name else "${prefix}.${name}";
          in
          if name == "__path" then
            if prefix == "" then acc else acc // { ${prefix} = value; }
          else if isRegistryNode value then
            acc // { ${key} = value.__path; } // flatten key value
          else if lib.isAttrs value && !(lib.isDerivation value) && !(value ? outPath) then
            acc // flatten key value
          else
            acc // { ${key} = value; }
        ) { } attrs;
    in
    flatten "" registry;

  /**
    Lookup a dotted path in the registry.

    ```nix
    lookup "home.alice" registry  # => <path>
    ```
  */
  lookup =
    path: registry:
    let
      parts = lib.splitString "." path;
      result = lib.getAttrFromPath parts registry;
    in
    toPath result;

  /**
    Create resolver function: name -> path.

    ```nix
    resolve = makeResolver registry;
    resolve "home.alice"  # => <path>
    ```
  */
  makeResolver =
    registry:
    let
      flat = flattenRegistry registry;
    in
    name:
    flat.${name}
      or (throw "imp registry: module '${name}' not found. Available: ${toString (builtins.attrNames flat)}");

in
{
  inherit
    buildRegistry
    flattenRegistry
    lookup
    makeResolver
    toPath
    isRegistryNode
    ;
}
