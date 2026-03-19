/**
  Anchor ID: IMP_ANCHOR_TREE_ENGINE
  Internal implementation for directory-to-attrset tree building.
*/
{
  lib,
  treef ? import,
  filterf,
}:
let
  fs = import ../fs-model.nix;

  hasFragmentEntries =
    path:
    let
      entries = fs.listDir {
        dir = path;
        excludeHidden = true;
        entryPointNames = [
          "default.nix"
          "package.nix"
        ];
      };
    in
    builtins.any (
      entry: entry.included && ((entry.isRegular && entry.isNixFile) || entry.hasEntryPoint)
    ) entries;

  collectFragmentValue =
    path:
    let
      entries = fs.listDir {
        dir = path;
        excludeHidden = true;
        entryPointNames = [
          "default.nix"
          "package.nix"
        ];
      };

      validEntries = builtins.filter (
        entry: entry.included && ((entry.isRegular && entry.isNixFile) || entry.hasEntryPoint)
      ) entries;

      fragments = map (
        entry:
        treef (
          if entry.hasEntryPoint then
            entry.entryPoint
          else
            entry.path
        )
      ) validEntries;
    in
    if fragments == [ ] then null else lib.foldl' lib.recursiveUpdate { } fragments;

  buildTree =
    root:
    let
      entries = fs.listDir {
        dir = root;
        inherit filterf;
        normalize = fs.normalizeAttrName { stripFragment = true; };
        entryPointNames = [ "default.nix" ];
      };

      checkCollisions = fs.selectUniqueByAttrName {
        scope = "imp.tree";
        entries = builtins.filter (
          entry: entry.included && ((entry.isRegular && entry.isNixFile) || (entry.isDirectory && !entry.isFragmentDir))
        ) entries;
      };

      fragmentValues = builtins.foldl' (
        acc: entry:
        if !(entry.included && entry.isFragmentDir && hasFragmentEntries entry.path) then
          acc
        else
          acc // { ${entry.attrName} = collectFragmentValue entry.path; }
      ) { } entries;

      # Process a single validated source (after collision check)
      processSource =
        attrName: source:
        let
          inherit (source) path;
          fragmentValue = fragmentValues.${attrName} or null;
          baseValue =
            if source.isRegular then
              treef path
            else if source.hasEntryPoint then
              treef path
            else
              buildTree path;
        in
        if fragmentValue == null then
          baseValue
        else
          lib.recursiveUpdate baseValue fragmentValue;

      # Combine checked sources with standalone .d directories
      processedSources = lib.mapAttrs processSource checkCollisions;
    in
    processedSources // builtins.removeAttrs fragmentValues (builtins.attrNames processedSources);
in
buildTree
