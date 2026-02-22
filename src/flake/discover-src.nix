/**
  Anchor ID: IMP_ANCHOR_FLAKE_SRC_DISCOVERY
  Discover additional imp source roots from monorepo-style project trees.

  `imp.srcDiscover` is evaluated as a list of specs:
  * `root`: directory containing project directories
  * `suffix`: per-project relative path to an imp outputs root
  * `includeHidden`: whether to include `_`-prefixed project dirs

  Discovery behavior:
  * scans immediate child directories of each `root`
  * child names are processed in lexical order for deterministic merges
  * only existing directory candidates are returned
  * roots are processed in the order provided by the caller
*/
{ lib }:
let
  pathExists = builtins.pathExists;
  readDir = builtins.readDir;
  readFileType = builtins.readFileType;
  attrNames = builtins.attrNames;
  sort = lib.sort;

  isHiddenName =
    name: builtins.stringLength name > 0 && builtins.substring 0 1 name == "_";

  discoverFromSpec =
    spec:
    let
      root = spec.root;
      suffix = spec.suffix or "nix/outputs";
      includeHidden = spec.includeHidden or false;
      rootExists = pathExists root;
      rootGuard =
        if !rootExists then
          null
        else if readFileType root == "directory" then
          null
        else
          throw "imp.srcDiscover: root '${toString root}' must be a directory";
      entries = if rootExists then readDir root else { };
      names = sort (a: b: a < b) (attrNames entries);
      childDirs = builtins.filter (
        name: entries.${name} == "directory" && (includeHidden || !isHiddenName name)
      ) names;
      candidates = builtins.map (name: root + "/${name}/${suffix}") childDirs;
    in
    builtins.seq rootGuard (
      builtins.filter (candidate: pathExists candidate && readFileType candidate == "directory") candidates
    );
in
specs: builtins.concatMap discoverFromSpec specs
