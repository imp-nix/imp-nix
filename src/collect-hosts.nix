/**
  Scans directories for `__host` declarations and collects host metadata.

  Recursively walks paths, importing each `.nix` file and extracting any
  `__host` attrset. Returns host names mapped to declarations. Names derive
  from directory names (for `default.nix`) or filenames (minus `.nix`).

  Files and directories starting with `_` are excluded. Directories with
  `default.nix` are treated as single modules; subdirectories are not scanned.

  # Type

  ```
  collectHosts :: (path | [path]) -> {
    <hostName> = {
      __host = { system, stateVersion, bases?, sinks?, hmSinks?, modules?, user? };
      config = path | null;
      extraConfig = module | null;
      __source = string;
    };
  }
  ```

  # Example

  ```nix
  collectHosts ./registry/hosts
  # => {
  #   desktop = { __host = { system = "x86_64-linux"; ... }; config = ./desktop/config; };
  #   server = { __host = { ... }; ... };
  # }
  ```

  # Host Schema

  ```nix
  {
    __host = {
      system = "x86_64-linux";
      stateVersion = "24.11";
      bases = [ "hosts.shared.base" ];       # registry paths to base config trees
      sinks = [ "shared.nixos" ];            # export sink paths for NixOS
      hmSinks = [ "shared.hm" ];             # export sink paths for Home Manager
      modules = [ "mod.nixos.ssh" ];         # or function: { registry, ... }: [ ... ]
      user = "alice";                        # HM integration username
    };
    config = ./config;
    extraConfig = { modulesPath, ... }: { }; # optional
  }
  ```

  Modules resolve as registry paths, `@`-prefixed input paths, or raw values.
*/
let
  isAttrs = builtins.isAttrs;
  isFunction = builtins.isFunction;

  isExcluded =
    path:
    let
      str = toString path;
      parts = builtins.filter builtins.isString (builtins.split "/" str);
      nonEmpty = builtins.filter (x: x != "") parts;
      basename = builtins.elemAt nonEmpty (builtins.length nonEmpty - 1);
    in
    builtins.substring 0 1 basename == "_";

  getHostName =
    path:
    let
      str = toString path;
      parts = builtins.filter builtins.isString (builtins.split "/" str);
      nonEmpty = builtins.filter (x: x != "") parts;
      last = builtins.elemAt nonEmpty (builtins.length nonEmpty - 1);
      isDefault = last == "default.nix";
      name =
        if isDefault then
          builtins.elemAt nonEmpty (builtins.length nonEmpty - 2)
        else
          builtins.replaceStrings [ ".nix" ] [ "" ] last;
    in
    name;

  safeExtractHost =
    value:
    let
      hasIt = builtins.tryEval (isAttrs value && value ? __host && isAttrs value.__host);
    in
    if hasIt.success && hasIt.value then
      let
        host = value.__host;
        forced = builtins.tryEval (builtins.deepSeq host host);
      in
      if forced.success then
        {
          __host = forced.value;
          config = value.config or null;
          extraConfig = value.extraConfig or null;
        }
      else
        null
    else
      null;

  importAndExtract =
    path:
    let
      imported = builtins.tryEval (import path);
    in
    if !imported.success then
      null
    else if isAttrs imported.value then
      safeExtractHost imported.value
    else
      null;

  processFile =
    acc: path:
    let
      extracted = importAndExtract path;
      hostName = getHostName path;
    in
    if extracted == null then
      acc
    else
      acc
      // {
        ${hostName} = extracted // {
          __source = toString path;
        };
      };

  processDir =
    acc: path:
    let
      entries = builtins.readDir path;
      names = builtins.attrNames entries;

      process =
        acc: name:
        let
          entryPath = path + "/${name}";
          entryType = entries.${name};
          resolvedType = if entryType == "symlink" then builtins.readFileType entryPath else entryType;
        in
        if isExcluded entryPath then
          acc
        else if resolvedType == "regular" && builtins.match ".*\\.nix" name != null then
          processFile acc entryPath
        else if resolvedType == "directory" then
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

  collectHosts =
    pathOrPaths:
    let
      paths = if builtins.isList pathOrPaths then pathOrPaths else [ pathOrPaths ];
      result = builtins.foldl' processPath { } paths;
    in
    result;

in
collectHosts
