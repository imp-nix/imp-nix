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
      entries = builtins.readDir root;
      sortedNames = lib.sort (a: b: a < b) (builtins.attrNames entries);

      toAttrName =
        name:
        let
          withoutNix = lib.removeSuffix ".nix" name;
        in
        lib.removeSuffix "_" withoutNix;

      shouldInclude = name: !(lib.hasPrefix "_" name) && filterf (toString root + "/" + name);

      # Build a map from attrName -> list of sources for collision detection
      buildSourceMap =
        let
          addSource =
            acc: name:
            let
              type = entries.${name};
              attrName = toAttrName name;
              path = root + "/${name}";
              isNixFile = type == "regular" && lib.hasSuffix ".nix" name;
              isDir = type == "directory";
            in
            if !shouldInclude name then
              acc
            else if isNixFile || isDir then
              let
                existing = acc.${attrName} or [ ];
              in
              acc // { ${attrName} = existing ++ [ { inherit name path type; } ]; }
            else
              acc;
        in
        lib.foldl' addSource { } sortedNames;

      # Check for collisions and throw descriptive errors
      checkCollisions = lib.mapAttrs (
        attrName: sources:
        if builtins.length sources > 1 then
          let
            paths = map (s: toString s.path) sources;
            pathList = lib.concatStringsSep ", " paths;
          in
          throw "imp.registry: collision for attribute '${attrName}' from multiple sources: ${pathList}"
        else
          builtins.head sources
      ) buildSourceMap;

      processSource =
        attrName: source:
        let
          inherit (source) path type;
        in
        if type == "regular" then
          path
        else
          let
            hasDefault = builtins.pathExists (path + "/default.nix");
          in
          if hasDefault then path else { __path = path; } // buildRegistry path;
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
