/**
  Anchor ID: IMP_ANCHOR_COLLECT_KEYED
  Shared helpers for collectors that flatten nested declarations into
  dotted-key record buckets.

  Used by `collect-exports.nix` and `collect-outputs.nix`.

  Responsibilities:
  * flatten nested attr syntax like `foo.bar.baz`
  * normalize leaf entries through `{ value, strategy }`
  * emit `{ source, value, strategy }` records
  * merge per-file record buckets by dotted key
*/
let
  utils = import ../lib.nix;
in
{
  isLeaf,
}:
let
  flattenDeclarations =
    prefix: declarations:
    let
      keys = builtins.attrNames declarations;
    in
    builtins.concatMap (
      key:
      let
        entry = declarations.${key};
        dottedKey = if prefix == "" then key else "${prefix}.${key}";
      in
      if isLeaf entry then [ { inherit dottedKey entry; } ] else flattenDeclarations dottedKey entry
    ) keys;

  processFileDeclarations =
    sourcePath: declarations:
    let
      flattened = flattenDeclarations "" declarations;
    in
    builtins.foldl' (
      acc: item:
      let
        entry = utils.normalizeValueStrategy item.entry;
      in
      acc
      // {
        ${item.dottedKey} =
          (acc.${item.dottedKey} or [ ])
          ++ [
            {
              source = toString sourcePath;
              inherit (entry) value strategy;
            }
          ];
      }
    ) { } flattened;

  mergeKeyedRecords =
    acc: newRecords:
    let
      allKeys = builtins.attrNames acc ++ builtins.attrNames newRecords;
      uniqueKeys = builtins.foldl' (
        keys: key: if builtins.elem key keys then keys else keys ++ [ key ]
      ) [ ] allKeys;
    in
    builtins.foldl' (
      result: key:
      result
      // {
        ${key} = (acc.${key} or [ ]) ++ (newRecords.${key} or [ ]);
      }
    ) { } uniqueKeys;
in
{
  inherit
    flattenDeclarations
    processFileDeclarations
    mergeKeyedRecords
    ;
}
