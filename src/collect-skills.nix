/**
  Scan bundle directories for skills/ subdirectories.

  Returns: { skillName = sourcePath; ... }

  For each bundle path:
  - If it's a directory (not a .nix file), check for <bundle>/skills/
  - If skills/ exists, read all top-level directories inside
  - Error on conflict if same skill name appears from multiple bundles

  # Arguments

  bundlePaths
  : List of bundle directory paths to scan.
*/
let
  pathExists = builtins.pathExists;
  readDir = builtins.readDir;
  attrNames = builtins.attrNames;
  foldl' = builtins.foldl';
  toString = builtins.toString;
  hasAttr = builtins.hasAttr;
  stringLength = builtins.stringLength;
  substring = builtins.substring;

  hasSuffix =
    suffix: str:
    let
      strLen = stringLength str;
      suffixLen = stringLength suffix;
    in
    strLen >= suffixLen && substring (strLen - suffixLen) suffixLen str == suffix;

  /**
    Check if a path is a directory bundle (not a .nix file).
  */
  isBundleDir =
    path:
    let
      pathStr = toString path;
    in
    pathExists path && !(hasSuffix ".nix" pathStr);

  /**
    Collect skills from a single bundle's skills/ directory.

    Returns: { skillName = { source = bundlePath; path = skillPath; }; }
  */
  collectBundleSkills =
    bundlePath:
    let
      skillsDir = bundlePath + "/skills";
    in
    if !isBundleDir bundlePath || !pathExists skillsDir then
      { }
    else
      let
        entries = readDir skillsDir;
        skillNames = builtins.filter (name: entries.${name} == "directory") (attrNames entries);
      in
      foldl' (
        acc: skillName:
        acc
        // {
          ${skillName} = {
            source = toString bundlePath;
            path = skillsDir + "/${skillName}";
          };
        }
      ) { } skillNames;

  /**
    Merge skill collections, erroring on conflicts.
  */
  mergeSkills =
    acc: newSkills:
    foldl' (
      result: skillName:
      if hasAttr skillName result then
        throw ''
          imp: skill name conflict: "${skillName}" found in multiple bundles:
            - ${result.${skillName}.source}
            - ${newSkills.${skillName}.source}
        ''
      else
        result // { ${skillName} = newSkills.${skillName}; }
    ) acc (attrNames newSkills);

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
      let
        entries = readDir bundlesDir;
        names = attrNames entries;
        dirs = builtins.filter (name: entries.${name} == "directory") names;
      in
      map (name: bundlesDir + "/${name}") dirs;

  /**
    Main collection function.

    Accepts a list of bundles parent directories (e.g., [ ./nix/bundles ])
    and returns { skillName = path; ... } mapping skill names to their
    absolute source paths.
  */
  collectSkills =
    bundlesParentPaths:
    let
      # Flatten: for each parent path, get all bundle subdirectories
      allBundlePaths = builtins.concatMap getBundleSubdirs bundlesParentPaths;
      allSkills = foldl' (
        acc: bundlePath: mergeSkills acc (collectBundleSkills bundlePath)
      ) { } allBundlePaths;
    in
    builtins.mapAttrs (_: skill: skill.path) allSkills;

in
collectSkills
