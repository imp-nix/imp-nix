/**
  Anchor ID: IMP_ANCHOR_TREE_FRAGMENTS
  Fragment collection and composition for `.d` directories.

  Follows the `.d` convention (like conf.d, init.d) where:
  * `foo.d/` contains fragments that compose into `foo`
  * Fragments are sorted by filename for deterministic ordering
  * Composition strategy depends on content type

  # Supported fragment types

  * `*.nix` - Nix expressions (imported directly)
  * `*.sh` - Shell scripts (read as strings)
  * `<fragment root>/default.nix` - Directory with default.nix entry point
  * `<fragment root>/package.nix` - Fallback for default.nix

  Directory fragments may be useful for bundling resources.

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
  fs = import ../fs-model.nix;

  emptyResult = {
    list = [ ];
    asString = "";
    asList = [ ];
    asAttrs = { };
  };

  /**
    Check if directory has a valid entry point.

    Accepts either default.nix or package.nix (nixpkgs convention).
  */
  hasDirEntryPoint =
    dir: name:
    fs.findEntryPoint {
      path = dir + "/${name}";
      candidates = [
        "default.nix"
        "package.nix"
      ];
    } != null;

  /**
    Get the entry point path for a directory.

    Prefers default.nix over package.nix when both exist.
  */
  getDirEntryPoint =
    dir: name:
    fs.findEntryPoint {
      path = dir + "/${name}";
      candidates = [
        "default.nix"
        "package.nix"
      ];
    };

  collectFragmentsGeneric =
    args: dir:
    if !builtins.pathExists dir then
      emptyResult
    else
      let
        entries = fs.listDir {
          inherit dir;
          excludeHidden = false;
          entryPointNames = [
            "default.nix"
            "package.nix"
          ];
        };

        validEntries = builtins.filter (
          entry:
          (entry.isRegular && (entry.isNixFile || fs.hasSuffix ".sh" entry.name)) || entry.hasEntryPoint
        ) entries;

        loadFragment =
          entry:
          if fs.hasSuffix ".sh" entry.name then
            builtins.readFile entry.path
          else
            let
              importPath = if entry.hasEntryPoint then entry.entryPoint else entry.path;
              imported = import importPath;
            in
            if args != null && builtins.isFunction imported then imported args else imported;

        fragments = map loadFragment validEntries;
        nonStrings = builtins.filter (f: !builtins.isString f) fragments;
        nonLists = builtins.filter (f: !builtins.isList f) fragments;
        nonAttrs = builtins.filter (f: !lib.isAttrs f) fragments;
        prefix = if args == null then "imp.collectFragments" else "imp.collectFragmentsWith";
      in
      {
        list = fragments;
        asString =
          if nonStrings != [ ] then
            throw "${prefix}: asString requires all fragments to be strings, got ${builtins.typeOf (builtins.head nonStrings)}"
          else
            lib.concatStringsSep "\n" fragments;
        asList =
          if nonLists != [ ] then
            throw "${prefix}: asList requires all fragments to be lists, got ${builtins.typeOf (builtins.head nonLists)}"
          else
            lib.flatten fragments;
        asAttrs =
          if nonAttrs != [ ] then
            throw "${prefix}: asAttrs requires all fragments to be attrsets, got ${builtins.typeOf (builtins.head nonAttrs)}"
          else
            lib.foldl' lib.recursiveUpdate { } fragments;
      };

  /**
    Collect fragments from a .d directory.

    # Arguments

    * `dir` (path): Directory ending in .d containing fragments

    # Returns

    Attrset with:
    * `list`: List of fragment contents in sorted order
    * `asString`: Fragments concatenated with newlines
    * `asList`: Fragments flattened (for lists of lists)
    * `asAttrs`: Fragments merged (for attrsets)

    Returns empty results if directory doesn't exist.
  */
  collectFragments = dir: collectFragmentsGeneric null dir;

  /**
    Collect fragments with arguments passed to each .nix file.

    # Arguments

    * `args` (attrset): Arguments to pass to each fragment function
    * `dir` (path): Directory containing fragments

    # Returns

    Same as collectFragments but each .nix fragment is called with args.
  */
  collectFragmentsWith = args: dir: collectFragmentsGeneric args dir;

in
{
  inherit collectFragments collectFragmentsWith;
}
