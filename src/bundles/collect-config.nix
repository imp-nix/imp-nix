/**
  Anchor ID: IMP_ANCHOR_BUNDLES_CONFIG
  Scan bundle directories for config files.

  Returns: { bundlePath = { inner = ...; outer = ...; }; ... }

  For each bundle directory, checks for:

  Inner config (inside bundle, owned by bundle/submodule):
  * <bundle>/config.nix
  * <bundle>/config/default.nix

  Outer config (sibling to bundle, owned by parent project):
  * <bundle>.config.nix

  Outer config is useful when bundles are git submodules - the parent
  project can override/extend the bundle's config without modifying
  the submodule.

  Config files can be:
  * Static attrsets: `{ key = "value"; }`
  * Functions receiving args: `{ pkgs, ... }: { tools = [ pkgs.jq ]; }`
  * Functors: `{ __functor = _: { pkgs, ... }: { ... }; }`

  Config values are returned as-is (not evaluated). Evaluation and
  merging (outer overrides inner) happens at bundle evaluation time.

  # Arguments

  bundlesParentPaths
  : List of bundles parent directories (e.g., [ ./nix/bundles ])
*/
let
  fs = import ../fs-model.nix;
  pathExists = builtins.pathExists;
  foldl' = builtins.foldl';
  toString = builtins.toString;
  baseNameOf = builtins.baseNameOf;
  dirOf = builtins.dirOf;

  /**
    Check if a path is a directory bundle (not a .nix file).
  */
  isBundleDir =
    path:
    let
      pathStr = toString path;
    in
    pathExists path && !(fs.hasSuffix ".nix" pathStr);

  /**
    Find inner config file for a bundle directory.

    Returns the config path if found, null otherwise.
    Priority: config.nix > config/default.nix
  */
  findInnerConfigPath =
    bundlePath:
    let
      configNix = bundlePath + "/config.nix";
      configDir = fs.findEntryPoint {
        path = bundlePath + "/config";
        candidates = [ "default.nix" ];
      };
    in
    if pathExists configNix then
      configNix
    else if configDir != null then
      configDir
    else
      null;

  /**
    Find outer config file (sibling to bundle directory).

    Given /path/bundles/lint, looks for /path/bundles/lint.config.nix
  */
  findOuterConfigPath =
    bundlePath:
    let
      bundleName = baseNameOf bundlePath;
      parentDir = dirOf bundlePath;
      outerConfigPath = parentDir + "/${bundleName}.config.nix";
    in
    if pathExists outerConfigPath then outerConfigPath else null;

  /**
    Import a config file safely.

    Returns { value = ...; source = ...; } or null on failure.
  */
  importConfig =
    configPath:
    if configPath == null then
      null
    else
      let
        imported = builtins.tryEval (import configPath);
      in
      if imported.success then
        {
          value = imported.value;
          source = toString configPath;
        }
      else
        null;

  /**
    Collect config from a single bundle directory.

    Returns: { ${bundlePathStr} = { inner = ...; outer = ...; }; } or { }
  */
  collectBundleConfig =
    bundlePath:
    let
      bundlePathStr = toString bundlePath;
      innerConfigPath = findInnerConfigPath bundlePath;
      outerConfigPath = findOuterConfigPath bundlePath;
      innerConfig = importConfig innerConfigPath;
      outerConfig = importConfig outerConfigPath;
      hasAnyConfig = innerConfig != null || outerConfig != null;
    in
    if !isBundleDir bundlePath || !hasAnyConfig then
      { }
    else
      {
        ${bundlePathStr} =
          { }
          // (if innerConfig != null then { inner = innerConfig; } else { })
          // (if outerConfig != null then { outer = outerConfig; } else { });
      };

  /**
    Get all bundle subdirectories from a bundles parent directory.

    Given a path like ./nix/bundles, returns paths to subdirectories
    that are actual bundles (directories, not .nix files).
  */
  getBundleSubdirs =
    bundlesDir:
    if !pathExists bundlesDir then
      [ ]
    else
      map (entry: entry.path) (
        builtins.filter (entry: entry.isDirectory) (
          fs.listDir {
            dir = bundlesDir;
            excludeHidden = false;
            normalize = name: name;
            entryPointNames = [ ];
          }
        )
      );

  /**
    Main collection function.

    Accepts a list of bundles parent directories (e.g., [ ./nix/bundles ])
    and returns { bundlePath = { inner = ...; outer = ...; }; ... }
    mapping bundle paths to their config records.
  */
  collectConfig =
    bundlesParentPaths:
    let
      allBundlePaths = builtins.concatMap getBundleSubdirs bundlesParentPaths;
    in
    foldl' (acc: bundlePath: acc // collectBundleConfig bundlePath) { } allBundlePaths;

in
collectConfig
