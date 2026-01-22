/**
  Generic directory scanner for collecting special attributes.

  Provides shared traversal logic used by all collect-*.nix modules.
  Parameterized by extraction and accumulation callbacks.

  # Type

  ```
  mkScanner :: {
    extract :: path -> a | null;     # Extract data from a file
    processResult :: acc -> path -> a -> acc;  # Accumulate result
    initial :: acc;                  # Initial accumulator
  } -> (path | [path]) -> acc
  ```

  # Example

  ```nix
  mkScanner {
    extract = path: let v = import path; in v.__foo or null;
    processResult = acc: path: data: acc // { ${getName path} = data; };
    initial = { };
  } ./src
  ```
*/
let
  utils = import ./lib.nix;

  /**
    Check if a path should be excluded (basename starts with `_`).
  */
  isExcluded =
    path:
    let
      str = toString path;
      parts = builtins.filter (x: x != "" && builtins.isString x) (builtins.split "/" str);
      basename = builtins.elemAt parts (builtins.length parts - 1);
    in
    builtins.substring 0 1 basename == "_";

  /**
    Check if a filename is a Nix file.
  */
  isNixFile = name: builtins.match ".*\\.nix" name != null;

  /**
    Resolve symlink to actual file type.
  */
  resolveType =
    path: entryType: if entryType == "symlink" then builtins.readFileType path else entryType;

  /**
    Create a scanner with custom extraction and accumulation logic.

    extract: path -> result | null
      Called for each .nix file. Return null to skip.

    processResult: acc -> path -> result -> acc
      Called when extract returns non-null. Accumulates results.

    initial: acc
      Starting accumulator value.
  */
  mkScanner =
    {
      extract,
      processResult,
      initial,
    }:
    let
      processFile =
        acc: path:
        let
          result = extract path;
        in
        if result == null then acc else processResult acc path result;

      processDir =
        acc: path:
        let
          entries = builtins.readDir path;
          names = builtins.attrNames entries;

          process =
            acc: name:
            let
              entryPath = path + "/${name}";
              entryType = resolveType entryPath entries.${name};
            in
            if isExcluded entryPath then
              acc
            else if entryType == "regular" && isNixFile name then
              processFile acc entryPath
            else if entryType == "directory" then
              let
                defaultPath = entryPath + "/default.nix";
                hasDefault = builtins.pathExists defaultPath;
              in
              if hasDefault then processFile acc defaultPath else processDir acc entryPath
            else
              acc;
        in
        builtins.foldl' process acc names;

      processPath =
        acc: path:
        let
          rawPathType = builtins.readFileType path;
          pathType = if rawPathType == "symlink" then builtins.readFileType path else rawPathType;
        in
        if pathType == "regular" then
          processFile acc path
        else if pathType == "directory" then
          processDir acc path
        else
          acc;

      scan =
        pathOrPaths:
        let
          paths = if builtins.isList pathOrPaths then pathOrPaths else [ pathOrPaths ];
        in
        builtins.foldl' processPath initial paths;
    in
    scan;

in
{
  inherit
    mkScanner
    isExcluded
    isNixFile
    resolveType
    ;
}
