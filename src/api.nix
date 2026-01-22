/**
  API method definitions for imp.

  This module defines all chainable methods available on the imp object.
  Methods are organized into categories:

  - Filtering: `filter`, `filterNot`, `match`, `matchNot`, `initFilter`
  - Transforming: `map`, `mapTree`
  - Tree building: `tree`, `treeWith`, `configTree`, `configTreeWith`
  - Fragments: `fragments`, `fragmentsWith`
  - File lists: `leaves`, `files`, `pipeTo`
  - Extending: `addRoot`, `addAPI`, `withLib`, `new`
*/
let
  utils = import ./lib.nix;
  inherit (utils)
    compose
    and
    andNot
    matchesRegex
    mapAttr
    ;
in

{
  config,
  update,
  updated,
  current,
  callable,
}:
let
  # Accumulates values into a config attribute
  accAttr = attrName: acc: config (c: mapAttr (update c) attrName acc);

  # Merges attributes into config
  mergeAttrs = attrs: config (c: (update c) // attrs);
in
{
  /**
    Filter paths by predicate. Multiple filters compose with AND.

    # Example

    ```nix
    imp.filter (lib.hasInfix "/services/") ./modules
    imp.filterNot (lib.hasInfix "/deprecated/") ./modules
    ```

    # Arguments

    predicate
    : Function that receives a path string and returns boolean.
  */
  filter = predicate: accAttr "filterf" (and predicate);

  /**
    Exclude paths matching predicate. Opposite of filter.

    # Example

    ```nix
    imp.filterNot (lib.hasInfix "/deprecated/") ./modules
    ```

    # Arguments

    predicate
    : Function that receives a path string and returns boolean.
  */
  filterNot = predicate: accAttr "filterf" (andNot predicate);

  /**
    Filter paths by regex. Uses `builtins.match`.

    # Example

    ```nix
    imp.match ".*[/]services[/].*" ./nix
    ```

    # Arguments

    regex
    : Regular expression string.
  */
  match = regex: accAttr "filterf" (and (matchesRegex regex));

  /**
    Exclude paths matching regex. Opposite of match.

    # Example

    ```nix
    imp.matchNot ".*[/]test[/].*" ./src
    ```

    # Arguments

    regex
    : Regular expression string.
  */
  matchNot = regex: accAttr "filterf" (andNot (matchesRegex regex));

  /**
    Replace the default filter. By default, imp finds `.nix` files
    and excludes paths containing underscore prefixes.

    # Example

    ```nix
    # Import markdown files instead of nix files
    imp.initFilter (lib.hasSuffix ".md") ./docs
    ```

    # Arguments

    predicate
    : Function that receives a path string and returns boolean.
  */
  initFilter = predicate: mergeAttrs { initf = predicate; };

  /**
    Transform each matched path. Composes with multiple calls.

    # Example

    ```nix
    imp.map import ./packages
    ```

    # Arguments

    f
    : Transformation function applied to each path or value.
  */
  map = f: accAttr "mapf" (compose f);

  /**
    Transform values when building a tree with `.tree`. Composes with multiple calls.

    # Example

    ```nix
    (imp.withLib lib)
      .mapTree (drv: drv // { meta.priority = 5; })
      .tree ./packages
    ```

    # Arguments

    f
    : Transformation function applied to each tree value.
  */
  mapTree = f: accAttr "treef" (compose f);

  /**
    Provide nixpkgs `lib`. Required before using `.leaves`, `.files`, `.tree`, or `.configTree`.

    # Example

    ```nix
    imp.withLib pkgs.lib
    imp.withLib inputs.nixpkgs.lib
    ```

    # Arguments

    lib
    : The nixpkgs lib attribute set.
  */
  withLib = lib: mergeAttrs { inherit lib; };

  /**
    Add additional roots to search.

    # Example

    ```nix
    (imp.withLib lib)
      .addRoot ./modules
      .addRoot ./vendor
      .leaves
    ```

    # Arguments

    root
    : Root path to add to the search.
  */
  addRoot = root: accAttr "roots" (r: r ++ [ root ]);

  /**
    Extend imp with custom methods. Methods receive `self` for chaining.

    # Example

    ```nix
    let
      myImp = imp.addAPI {
        services = self: self.filter (lib.hasInfix "/services/");
        packages = self: self.filter (lib.hasInfix "/packages/");
      };
    in
    myImp.services ./nix
    ```

    # Arguments

    api
    : Attribute set of name = self: ... methods.
  */
  addAPI = api: accAttr "api" (a: a // api);

  /**
    Apply a function to the final file list.

    # Example

    ```nix
    (imp.withLib lib).pipeTo builtins.length ./modules
    ```

    # Arguments

    f
    : Function to apply to the file list.
  */
  pipeTo = f: mergeAttrs { pipef = f; };

  /**
    Get the list of matched files. Requires `.withLib`.

    # Example

    ```nix
    (imp.withLib lib).leaves ./modules
    ```
  */
  leaves = mergeAttrs { pipef = (i: i); };

  result = current [ ];
  files = current.leaves.result;

  /**
    Build a nested attrset from directory structure. Requires `.withLib`.

    Directory names become attribute names. Files are imported and their
    values placed at the corresponding path.

    # Example

    ```nix
    (imp.withLib lib).tree ./outputs
    # { packages.hello = <imported>; apps.run = <imported>; }
    ```

    # Arguments

    path
    : Root directory to build tree from.
  */
  tree =
    path:
    if updated.lib == null then
      throw "You need to call withLib before using tree."
    else
      import ./tree.nix {
        inherit (updated) lib treef filterf;
      } path;

  /**
    Convenience function combining `.withLib`, `.mapTree`, and `.tree`.

    # Example

    ```nix
    # These are equivalent:
    ((imp.withLib lib).mapTree (f: f args)).tree ./outputs
    imp.treeWith lib (f: f args) ./outputs
    ```

    # Arguments

    lib
    : The nixpkgs lib attribute set.

    f
    : Transformation function for tree values.

    path
    : Root directory to build tree from.
  */
  treeWith =
    lib: f: path:
    ((current.withLib lib).mapTree f).tree path;

  /**
    Build a module where directory structure maps to NixOS option paths.
    Each file receives module args and returns config values.

    # Example

    ```nix
    { inputs, lib, ... }: {
      imports = [ ((inputs.imp.withLib lib).configTree ./config) ];
    }
    # File ./config/programs/git.nix sets config.programs.git
    ```

    # Arguments

    path
    : Root directory containing config files.
  */
  configTree =
    path:
    if updated.lib == null then
      throw "You need to call withLib before using configTree."
    else
      import ./config-tree.nix {
        inherit (updated) lib filterf;
      } path;

  /**
    Like `.configTree` but passes extra arguments to each file.

    # Example

    ```nix
    (imp.withLib lib).configTreeWith { myArg = "value"; } ./config
    ```

    # Arguments

    extraArgs
    : Additional arguments passed to each config file.

    path
    : Root directory containing config files.
  */
  configTreeWith =
    extraArgs: path:
    if updated.lib == null then
      throw "You need to call withLib before using configTreeWith."
    else
      import ./config-tree.nix {
        inherit (updated) lib filterf;
        inherit extraArgs;
      } path;

  /**
    Merge multiple config trees into a single module.

    # Example

    ```nix
    # Later trees override earlier (default)
    (imp.withLib lib).mergeConfigTrees [ ./base ./overrides ]

    # With mkMerge semantics
    (imp.withLib lib).mergeConfigTrees { strategy = "merge"; } [ ./base ./local ]
    ```

    # Arguments

    options (optional)
    : Attribute set with `strategy` (`"override"` or `"merge"`) and `extraArgs`.

    paths
    : List of directories to merge.
  */
  mergeConfigTrees =
    arg:
    if updated.lib == null then
      throw "You need to call withLib before using mergeConfigTrees."
    else if builtins.isList arg then
      # Called as: mergeConfigTrees [ paths ]
      import ./merge-config-trees.nix {
        inherit (updated) lib filterf;
      } arg
    else
      # Called as: mergeConfigTrees { options } [ paths ]
      paths:
      import ./merge-config-trees.nix {
        inherit (updated) lib filterf;
        strategy = arg.strategy or "override";
        extraArgs = arg.extraArgs or { };
      } paths;

  /**
    Returns a fresh imp instance with empty state, preserving custom API extensions.

    # Example

    ```nix
    let
      customImp = imp.addAPI { myMethod = self: self.filter predicate; };
      fresh = customImp.new;
    in
    fresh.myMethod ./src
    ```
  */
  new = callable;

  /**
    Build a modules list from mixed items. Handles paths, registry nodes, and modules.

    For registry nodes or paths that import to attrsets with `__module`,
    extracts just the `__module`. For functions that are "registry wrappers"
    (take `inputs` arg and return attrsets with `__module`), wraps them to
    extract `__module` from the result.

    This allows registry modules to declare `__inputs` and `__overlays`
    without polluting the module system.

    # Example

    ```nix
    modules = imp.imports [
      registry.hosts.server
      registry.modules.nixos.base
      ./local-module.nix
      inputs.home-manager.nixosModules.home-manager
      { services.openssh.enable = true; }
    ];
    ```

    # Arguments

    items
    : List of paths, registry nodes, or module values.
  */
  imports =
    items:
    let
      registryLib = import ./registry.nix { lib = updated.lib or builtins; };
      isPath = p: builtins.isPath p || (builtins.isString p && builtins.substring 0 1 p == "/");

      # Registry wrappers: functions taking flake-level args (inputs, exports, registry)
      # that are NOT NixOS module functions (which take config, pkgs, etc.)
      # Also handles attrsets with `__functor` (callable attrsets)
      isRegistryWrapper =
        value:
        let
          fn = if builtins.isAttrs value && value ? __functor then value.__functor value else value;
          args = if builtins.isFunction fn then builtins.functionArgs fn else { };
          hasFlakeArgs = args ? inputs || args ? exports || args ? registry;
          hasModuleArgs = args ? config || args ? pkgs;
        in
        hasFlakeArgs && !hasModuleArgs;

      # For attrsets with `__module`, extract it directly.
      # For registry wrapper functions (or `__functor` attrsets), create a wrapper that calls the function,
      # extracts `__module`, and calls it with module args. Explicit arg declarations
      # are required because the module system uses `builtins.functionArgs`.
      extractModule =
        value:
        if builtins.isAttrs value && value ? __module then
          value.__module
        else if
          (builtins.isFunction value || (builtins.isAttrs value && value ? __functor))
          && isRegistryWrapper value
        then
          {
            config ? null,
            lib ? null,
            pkgs ? null,
            options ? null,
            modulesPath ? null,
            inputs ? null,
            exports ? null,
            registry ? null,
            osConfig ? null,
            ...
          }@args:
          let
            result = value args;
            module = if builtins.isAttrs result && result ? __module then result.__module else result;
          in
          if builtins.isFunction module then module args else module
        else
          value;

      process =
        item:
        if registryLib.isRegistryNode item then
          extractModule (import item.__path)
        else if isPath item then
          extractModule (import item)
        else
          item;
    in
    builtins.map process items;

  /**
    Collect fragments from a `.d` directory. Requires `.withLib`.

    Follows the `.d` convention where fragments are sorted by filename
    and composed together. Files are processed in order (00-base before 10-extra).

    Returns an attrset with multiple access methods:
    - `.list` - raw list of fragment contents
    - `.asString` - fragments concatenated with newlines (for shell scripts)
    - `.asList` - fragments flattened (for lists of packages)
    - `.asAttrs` - fragments merged (for attrsets)

    Note: For known flake output directories (packages.d, devShells.d, etc.),
    tree.nix auto-merges fragments. Use `imp.fragments` for other `.d` dirs
    like shellHook.d or shell-packages.d.

    # Example

    ```nix
    let
      imp = inputs.imp.withLib lib;

      # Shell scripts concatenated
      shellHookFragments = imp.fragments ./shellHook.d;

      # Package lists merged
      shellPkgFragments = imp.fragmentsWith { inherit pkgs self'; } ./shell-packages.d;
    in
    pkgs.mkShell {
      packages = shellPkgFragments.asList;
      shellHook = shellHookFragments.asString;
    }
    ```

    # Arguments

    dir
    : Directory ending in `.d` containing fragments (.nix or .sh files).
  */
  fragments =
    dir:
    if updated.lib == null then
      throw "You need to call withLib before using fragments."
    else
      (import ./fragments.nix { inherit (updated) lib; }).collectFragments dir;

  /**
    Collect fragments with arguments passed to each .nix file.

    Like `fragments`, but calls each .nix fragment as a function with the
    provided arguments. Shell (.sh) files are still read as strings.

    # Example

    ```nix
    # Each file in shell-packages.d/ is called with { pkgs, self' }
    # and should return a list like [ pkgs.ripgrep pkgs.fd ]
    shellPkgs = (imp.withLib lib).fragmentsWith { inherit pkgs self'; } ./shell-packages.d;
    packages = shellPkgs.asList;
    ```

    # Arguments

    args
    : Attrset of arguments to pass to each fragment function.

    dir
    : Directory containing fragments.
  */
  fragmentsWith =
    args: dir:
    if updated.lib == null then
      throw "You need to call withLib before using fragmentsWith."
    else
      (import ./fragments.nix { inherit (updated) lib; }).collectFragmentsWith args dir;
}
