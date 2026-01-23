/**
  File collection and filtering logic.

  This module handles:
  - Recursive file discovery from paths
  - Filter composition and application
  - Path normalization (absolute to relative)
*/
let
  utils = import ../lib.nix;
  inherit (utils)
    compose
    and
    andNot
    isDirectory
    isPathLike
    hasOutPath
    isimp
    toPath
    ;
in

/**
  Core evaluation: applies filters/maps and produces the final result.

  When `pipef` is null, returns a NixOS module.
  Otherwise, applies `pipef` to the collected file list.
*/
{
  lib ? null,
  pipef ? null,
  initf ? null,
  filterf,
  mapf,
  roots,
  ...
}:
path:
let
  # Normalize registry nodes to their path
  normalizedPath = toPath path;

  result =
    if pipef == null then
      { imports = [ module ]; }
    else if lib == null then
      throw "You need to call withLib before trying to read the tree."
    else
      pipef (leafs lib normalizedPath);

  # Wraps file list in a module that delays lib access until NixOS evaluation
  module =
    { lib, ... }:
    {
      imports = leafs lib normalizedPath;
    };

  # Recursively collects and filters files from paths
  leafs =
    lib:
    let
      # Extract files from an imp object
      treeFiles = t: (t.withLib lib).files;

      # Normalize various path-like inputs to file lists
      listFilesRecursive =
        x:
        let
          # Convert registry nodes to paths
          p = toPath x;
        in
        if isimp x then
          treeFiles x
        else if hasOutPath p then
          listFilesRecursive p.outPath
        else if isDirectory p then
          lib.filesystem.listFilesRecursive p
        else
          [ p ];

      # Default: .nix files, excluding paths with `/_`
      nixFilter = andNot (lib.hasInfix "/_") (lib.hasSuffix ".nix");
      initialFilter = if initf != null then initf else nixFilter;

      # Compose user filters with initial filter
      pathFilter = compose (and filterf initialFilter) toString;
      otherFilter = and filterf (if initf != null then initf else (_: true));
      filter = x: if isPathLike x then pathFilter (toPath x) else otherFilter x;

      # Convert absolute paths to relative for consistent filtering across roots
      isFileRelative =
        root:
        { file, rel }:
        if file != null && lib.hasPrefix root file then
          {
            file = null;
            rel = lib.removePrefix root file;
          }
        else
          { inherit file rel; };

      getFileRelative = { file, rel }: if rel == null then file else rel;

      makeRelative =
        roots:
        lib.pipe roots [
          (lib.lists.flatten)
          (builtins.map toPath)
          (builtins.filter isDirectory)
          (builtins.map builtins.toString)
          (builtins.map isFileRelative)
          (fx: fx ++ [ getFileRelative ])
          (
            fx: file:
            lib.pipe {
              file = builtins.toString file;
              rel = null;
            } fx
          )
        ];

      rootRelative =
        roots:
        let
          mkRel = makeRelative roots;
        in
        x: if isPathLike x then mkRel (toPath x) else x;
    in
    root:
    lib.pipe
      [ roots root ]
      [
        (lib.lists.flatten)
        (map toPath)
        (map listFilesRecursive)
        (lib.lists.flatten)
        (builtins.filter (
          compose filter (rootRelative [
            roots
            root
          ])
        ))
        (map mapf)
      ];

in
result
