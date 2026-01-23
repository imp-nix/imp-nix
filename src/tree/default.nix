/**
  Builds nested attrset from directory structure.

  Naming:  `foo.nix` | `foo/default.nix` -> `{ foo = ... }`
           `foo_.nix`                  -> `{ foo = ... }`  (escapes reserved names)
           `_foo.nix` | `_foo/`          -> ignored
           `foo.d/`                      -> fragment directory (merged attrsets)

  Fragment directories (`*.d/`):
    Any `foo.d/` directory is processed as a fragment directory. The `.nix`
    files inside are imported in sorted order (00-base.nix before 10-extra.nix)
    and combined with `lib.recursiveUpdate`.

    If `foo.d/` contains no valid `.nix` files, it is skipped entirely.
    Non-`.nix` files in `.d` directories (e.g., `.sh` files for shell hooks)
    should be consumed via `imp.fragments` or `imp.fragmentsWith`.

  Merging with base:
    If both `foo.nix` (or `foo/default.nix`) and `foo.d/` exist, they are
    combined: the base is imported first, then `foo.d/*.nix` fragments are
    merged on top using `lib.recursiveUpdate`. This allows a base file to
    define core outputs while fragments add or extend them.

  Collision detection:
    If multiple entries resolve to the same attribute name (e.g., `foo.nix`
    and `foo/default.nix`), an error is thrown. The `.d` suffix is NOT a
    collision - it explicitly merges with the base.

  # Example

  Directory structure:

  ```
  outputs/
    apps.nix
    checks.nix
    packages.d/
      00-core.nix       # { default = ...; foo = ...; }
      10-extras.nix     # { bar = ...; }
  ```

  ```nix
  imp.treeWith lib import ./outputs
  ```

  Returns:

  ```nix
  {
    apps = <imported from apps.nix>;
    checks = <imported from checks.nix>;
    packages = { default = ...; foo = ...; bar = ...; };  # merged
  }
  ```

  # Usage

  ```nix
  (imp.withLib lib).tree ./outputs
  ```

  Or with transform:

  ```nix
  ((imp.withLib lib).mapTree (f: f args)).tree ./outputs
  imp.treeWith lib (f: f args) ./outputs
  ```
*/
{
  lib,
  treef ? import,
  filterf,
}:
let
  buildTree =
    root:
    let
      entries = builtins.readDir root;
      sortedNames = lib.sort (a: b: a < b) (builtins.attrNames entries);

      toAttrName =
        name:
        let
          withoutNix = lib.removeSuffix ".nix" name;
          withoutD = lib.removeSuffix ".d" withoutNix;
        in
        lib.removeSuffix "_" withoutD;

      isFragmentDir = name: lib.hasSuffix ".d" name;

      shouldInclude = name: !(lib.hasPrefix "_" name) && filterf (toString root + "/" + name);

      # Check if a .d directory has valid .nix fragments
      hasValidFragments =
        path:
        let
          fragEntries = builtins.readDir path;
          fragNames = builtins.attrNames fragEntries;
        in
        builtins.any (
          name:
          let
            type = fragEntries.${name};
            dirPath = path + "/${name}";
          in
          if type == "regular" then
            lib.hasSuffix ".nix" name && !(lib.hasPrefix "_" name)
          else if type == "directory" then
            !(lib.hasPrefix "_" name)
            && (
              builtins.pathExists (dirPath + "/default.nix") || builtins.pathExists (dirPath + "/package.nix")
            )
          else
            false
        ) fragNames;

      # Process a .d fragment directory: import all .nix files and merge as attrsets
      processFragmentDir =
        path:
        let
          fragEntries = builtins.readDir path;
          fragNames = lib.sort (a: b: a < b) (builtins.attrNames fragEntries);

          isValidFragment =
            name:
            let
              type = fragEntries.${name};
              dirPath = path + "/${name}";
            in
            if type == "regular" then
              lib.hasSuffix ".nix" name && !(lib.hasPrefix "_" name)
            else if type == "directory" then
              !(lib.hasPrefix "_" name)
              && (
                builtins.pathExists (dirPath + "/default.nix") || builtins.pathExists (dirPath + "/package.nix")
              )
            else
              false;

          validNames = builtins.filter isValidFragment fragNames;

          loadFragment =
            name:
            let
              fragPath = path + "/${name}";
              type = fragEntries.${name};
              # For directories, prefer default.nix, fallback to package.nix
              entryPoint =
                if type == "directory" then
                  if builtins.pathExists (fragPath + "/default.nix") then
                    fragPath + "/default.nix"
                  else
                    fragPath + "/package.nix"
                else
                  fragPath;
            in
            treef entryPoint;

          fragments = map loadFragment validNames;
        in
        lib.foldl' lib.recursiveUpdate { } fragments;

      # .d directories merge with base, so they're excluded from collision detection
      buildSourceMap =
        let
          addSource =
            acc: name:
            let
              type = entries.${name};
              attrName = toAttrName name;
              path = root + "/${name}";
              isNixFile = type == "regular" && lib.hasSuffix ".nix" name;
              isDDir = type == "directory" && isFragmentDir name;
              isDir = type == "directory" && !isDDir;
            in
            if !shouldInclude name then
              acc
            else if isDDir then
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
          throw "imp.tree: collision for attribute '${attrName}' from multiple sources: ${pathList}"
        else
          builtins.head sources
      ) buildSourceMap;

      # Process a single validated source (after collision check)
      processSource =
        attrName: source:
        let
          inherit (source) name path type;
          # Check for companion .d directory to merge with
          dDir = attrName + ".d";
          dDirPath = root + "/${dDir}";
          hasDDir = entries ? ${dDir} && entries.${dDir} == "directory";
        in
        if type == "regular" then
          let
            baseValue = treef path;
          in
          if hasDDir && hasValidFragments dDirPath then
            lib.recursiveUpdate baseValue (processFragmentDir dDirPath)
          else
            baseValue
        else
          let
            hasDefault = builtins.pathExists (path + "/default.nix");
            baseValue = if hasDefault then treef path else buildTree path;
          in
          if hasDDir && hasValidFragments dDirPath then
            lib.recursiveUpdate baseValue (processFragmentDir dDirPath)
          else
            baseValue;

      # Handle standalone .d directories (no base file/dir)
      standaloneDDirs = lib.foldl' (
        acc: name:
        let
          type = entries.${name};
          attrName = toAttrName name;
          path = root + "/${name}";
          # Check if there's a base for this .d
          baseNix = attrName + ".nix";
          baseNixEscaped = attrName + "_.nix";
          baseDir = attrName;
          hasBase =
            (entries ? ${baseNix} && shouldInclude baseNix)
            || (entries ? ${baseNixEscaped} && shouldInclude baseNixEscaped)
            || (entries ? ${baseDir} && entries.${baseDir} == "directory" && shouldInclude baseDir);
        in
        if
          type == "directory"
          && isFragmentDir name
          && shouldInclude name
          && !hasBase
          && hasValidFragments path
        then
          acc // { ${attrName} = processFragmentDir path; }
        else
          acc
      ) { } sortedNames;

      # Combine checked sources with standalone .d directories
      processedSources = lib.mapAttrs processSource checkCollisions;
    in
    processedSources // standaloneDDirs;
in
buildTree
