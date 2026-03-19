/**
  Anchor ID: IMP_ANCHOR_SCANNER
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
  fs = import ./fs-model.nix;

  /**
    Check if a path should be excluded (basename starts with `_`).
  */
  isExcluded = path: fs.isHiddenName (builtins.baseNameOf (toString path));

  /**
    Check if a filename is a Nix file.
  */
  isNixFile = fs.isNixFile;

  /**
    Resolve symlink to actual file type.
  */
  resolveType = fs.resolveType;

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
          entries = fs.listDir {
            dir = path;
            entryPointNames = [ "default.nix" ];
          };

          process =
            acc: entry:
            if !entry.included then
              acc
            else if entry.isRegular && entry.isNixFile then
              processFile acc entry.path
            else if entry.isDirectory then
              if entry.hasEntryPoint then processFile acc entry.entryPoint else processDir acc entry.path
            else
              acc;
        in
        builtins.foldl' process acc entries;

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
