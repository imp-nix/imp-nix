/**
  Anchor ID: IMP_ANCHOR_FS_MODEL
  Shared filesystem model for imp internals.

  Centralizes the directory semantics that define imp's mental model:

  * `_`-prefixed entries may be excluded by consumers
  * `default.nix` / `package.nix` can make directories act as leaf entry points
  * `.d` directories can be recognized as fragment directories
  * attr names derive from filenames with optional `.nix`, `.d`, and trailing `_`
    normalization

  This module intentionally depends only on builtins so scanner-based collectors
  keep their "no nixpkgs lib required" property.

  Consumers use it to agree on:
  * hidden-entry filtering
  * attr-name normalization
  * directory leaf entrypoint detection
  * fragment-directory detection
  * collision grouping by normalized attr name
*/
let
  stringLength = builtins.stringLength;
  substring = builtins.substring;

  hasPrefix =
    prefix: str:
    let
      prefixLen = stringLength prefix;
      strLen = stringLength str;
    in
    strLen >= prefixLen && substring 0 prefixLen str == prefix;

  hasSuffix =
    suffix: str:
    let
      suffixLen = stringLength suffix;
      strLen = stringLength str;
    in
    strLen >= suffixLen && substring (strLen - suffixLen) suffixLen str == suffix;

  removeSuffix =
    suffix: str:
    let
      suffixLen = stringLength suffix;
      strLen = stringLength str;
    in
    if hasSuffix suffix str then substring 0 (strLen - suffixLen) str else str;

  sortNames = names: builtins.sort (a: b: a < b) names;

  isHiddenName = name: stringLength name > 0 && substring 0 1 name == "_";
  isNixFile = hasSuffix ".nix";

  resolveType =
    path: entryType: if entryType == "symlink" then builtins.readFileType path else entryType;

  normalizeAttrName =
    {
      stripNix ? true,
      stripFragment ? false,
      stripEscape ? true,
    }:
    name:
    let
      withoutNix = if stripNix then removeSuffix ".nix" name else name;
      withoutFragment = if stripFragment then removeSuffix ".d" withoutNix else withoutNix;
    in
    if stripEscape then removeSuffix "_" withoutFragment else withoutFragment;

  findEntryPoint =
    {
      path,
      candidates ? [ "default.nix" ],
    }:
    let
      matches = builtins.filter (candidate: builtins.pathExists (path + "/${candidate}")) candidates;
    in
    if matches == [ ] then null else path + "/${builtins.head matches}";

  mkDirEntry =
    {
      dir,
      name,
      type,
      filterf ? _: true,
      excludeHidden ? true,
      normalize ? normalizeAttrName { },
      entryPointNames ? [ "default.nix" ],
    }:
    let
      path = dir + "/${name}";
      resolvedType = resolveType path type;
      hidden = isHiddenName name;
      entryPoint = if resolvedType == "directory" then findEntryPoint { inherit path; candidates = entryPointNames; } else null;
    in
    {
      inherit
        name
        path
        entryPoint
        ;
      type = resolvedType;
      attrName = normalize name;
      included = (!excludeHidden || !hidden) && filterf (toString path);
      isHidden = hidden;
      isRegular = resolvedType == "regular";
      isDirectory = resolvedType == "directory";
      isNixFile = resolvedType == "regular" && isNixFile name;
      isFragmentDir = resolvedType == "directory" && hasSuffix ".d" name;
      hasEntryPoint = entryPoint != null;
    };

  listDir =
    {
      dir,
      filterf ? _: true,
      excludeHidden ? true,
      normalize ? normalizeAttrName { },
      entryPointNames ? [ "default.nix" ],
    }:
    let
      entries = builtins.readDir dir;
      names = sortNames (builtins.attrNames entries);
    in
    map (
      name:
      mkDirEntry {
        inherit
          dir
          name
          filterf
          excludeHidden
          normalize
          entryPointNames
          ;
        type = entries.${name};
      }
    ) names;

  groupByAttrName =
    entries:
    builtins.foldl' (
      acc: entry:
      acc
      // {
        ${entry.attrName} = (acc.${entry.attrName} or [ ]) ++ [ entry ];
      }
    ) { } entries;

  selectUniqueByAttrName =
    {
      scope,
      entries,
    }:
    builtins.mapAttrs (
      attrName: sources:
      if builtins.length sources > 1 then
        let
          paths = map (source: toString source.path) sources;
        in
        throw "${scope}: collision for attribute '${attrName}' from multiple sources: ${builtins.concatStringsSep ", " paths}"
      else
        builtins.head sources
    ) (groupByAttrName entries);
in
{
  inherit
    findEntryPoint
    groupByAttrName
    hasPrefix
    hasSuffix
    isHiddenName
    isNixFile
    listDir
    mkDirEntry
    normalizeAttrName
    removeSuffix
    resolveType
    selectUniqueByAttrName
    sortNames
    ;
}
