/**
  Fragment collection and composition for `.d` directories.

  Follows the `.d` convention (like conf.d, init.d) where:
  - `foo.d/` contains fragments that compose into `foo`
  - Fragments are sorted by filename for deterministic ordering
  - Composition strategy depends on content type

  # Supported fragment types

  - `*.nix` - Nix expressions (imported directly)
  - `*.sh` - Shell scripts (read as strings)
  - `<fragment root>/default.nix` - Directory with default.nix entry point
  - `<fragment root>/package.nix` - Fallback for default.nix

  Directory fragments may be useful for bundling resources, e.g. agent skills.

  # Composition patterns

  String concatenation (shellHook.d/):
    shellHook.d/
      00-base.sh
      10-rust.sh
    -> concatenated in order

  List merging (packages.d/):
    packages.d/
      base.nix       # returns [ pkgs.git ]
      cargo-rail/    # directory with default.nix or package.nix
    -> merged into single list

  Attrset merging (env.d/):
    env.d/
      base.nix      # returns { FOO = "bar"; }
      extra.nix     # returns { BAZ = "qux"; }
    -> merged into single attrset

  # Usage

  ```nix
  let
    fragments = imp.collectFragments ./shellHook.d;
  in
  pkgs.mkShell {
    shellHook = fragments.asString;
    # or: shellHook = lib.concatStringsSep "\n" fragments.list;
  }
  ```
*/
{
  lib,
}:
let
  /**
    Check if directory has a valid entry point.

    Accepts either default.nix or package.nix (nixpkgs convention).
  */
  hasDirEntryPoint =
    dir: name:
    builtins.pathExists (dir + "/${name}/default.nix")
    || builtins.pathExists (dir + "/${name}/package.nix");

  /**
    Get the entry point path for a directory.

    Prefers default.nix over package.nix when both exist.
  */
  getDirEntryPoint =
    dir: name:
    let
      defaultPath = dir + "/${name}/default.nix";
      packagePath = dir + "/${name}/package.nix";
    in
    if builtins.pathExists defaultPath then defaultPath else packagePath;

  /**
    Collect fragments from a .d directory.

    # Arguments

    - `dir` (path): Directory ending in .d containing fragments

    # Returns

    Attrset with:
    - `list`: List of fragment contents in sorted order
    - `asString`: Fragments concatenated with newlines
    - `asList`: Fragments flattened (for lists of lists)
    - `asAttrs`: Fragments merged (for attrsets)

    Returns empty results if directory doesn't exist.
  */
  collectFragments =
    dir:
    if !builtins.pathExists dir then
      {
        list = [ ];
        asString = "";
        asList = [ ];
        asAttrs = { };
      }
    else
      let
        entries = builtins.readDir dir;
        sortedNames = lib.sort (a: b: a < b) (builtins.attrNames entries);

        isValidFragment =
          name:
          let
            type = entries.${name};
          in
          if type == "regular" then
            lib.hasSuffix ".nix" name || lib.hasSuffix ".sh" name
          else if type == "directory" then
            hasDirEntryPoint dir name
          else
            false;

        validNames = builtins.filter isValidFragment sortedNames;

        loadFragment =
          name:
          let
            path = dir + "/${name}";
            type = entries.${name};
          in
          if lib.hasSuffix ".sh" name then
            builtins.readFile path
          else if type == "directory" then
            import (getDirEntryPoint dir name)
          else
            import path;

        fragments = map loadFragment validNames;
        nonStrings = builtins.filter (f: !builtins.isString f) fragments;
        nonLists = builtins.filter (f: !builtins.isList f) fragments;
        nonAttrs = builtins.filter (f: !lib.isAttrs f) fragments;
      in
      {
        list = fragments;
        asString =
          if nonStrings != [ ] then
            throw "imp.collectFragments: asString requires all fragments to be strings, got ${builtins.typeOf (builtins.head nonStrings)}"
          else
            lib.concatStringsSep "\n" fragments;
        asList =
          if nonLists != [ ] then
            throw "imp.collectFragments: asList requires all fragments to be lists, got ${builtins.typeOf (builtins.head nonLists)}"
          else
            lib.flatten fragments;
        asAttrs =
          if nonAttrs != [ ] then
            throw "imp.collectFragments: asAttrs requires all fragments to be attrsets, got ${builtins.typeOf (builtins.head nonAttrs)}"
          else
            lib.foldl' lib.recursiveUpdate { } fragments;
      };

  /**
    Collect fragments with arguments passed to each .nix file.

    # Arguments

    - `args` (attrset): Arguments to pass to each fragment function
    - `dir` (path): Directory containing fragments

    # Returns

    Same as collectFragments but each .nix fragment is called with args.
  */
  collectFragmentsWith =
    args: dir:
    if !builtins.pathExists dir then
      {
        list = [ ];
        asString = "";
        asList = [ ];
        asAttrs = { };
      }
    else
      let
        entries = builtins.readDir dir;
        sortedNames = lib.sort (a: b: a < b) (builtins.attrNames entries);

        isValidFragment =
          name:
          let
            type = entries.${name};
          in
          if type == "regular" then
            lib.hasSuffix ".nix" name || lib.hasSuffix ".sh" name
          else if type == "directory" then
            hasDirEntryPoint dir name
          else
            false;

        validNames = builtins.filter isValidFragment sortedNames;

        loadFragment =
          name:
          let
            path = dir + "/${name}";
            type = entries.${name};
            importPath = if type == "directory" then getDirEntryPoint dir name else path;
            imported = import importPath;
          in
          if lib.hasSuffix ".sh" name then
            builtins.readFile path
          else if builtins.isFunction imported then
            imported args
          else
            imported;

        fragments = map loadFragment validNames;
        nonStrings = builtins.filter (f: !builtins.isString f) fragments;
        nonLists = builtins.filter (f: !builtins.isList f) fragments;
        nonAttrs = builtins.filter (f: !lib.isAttrs f) fragments;
      in
      {
        list = fragments;
        asString =
          if nonStrings != [ ] then
            throw "imp.collectFragmentsWith: asString requires all fragments to be strings, got ${builtins.typeOf (builtins.head nonStrings)}"
          else
            lib.concatStringsSep "\n" fragments;
        asList =
          if nonLists != [ ] then
            throw "imp.collectFragmentsWith: asList requires all fragments to be lists, got ${builtins.typeOf (builtins.head nonLists)}"
          else
            lib.flatten fragments;
        asAttrs =
          if nonAttrs != [ ] then
            throw "imp.collectFragmentsWith: asAttrs requires all fragments to be attrsets, got ${builtins.typeOf (builtins.head nonAttrs)}"
          else
            lib.foldl' lib.recursiveUpdate { } fragments;
      };

in
{
  inherit collectFragments collectFragmentsWith;
}
