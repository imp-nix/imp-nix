/**
  Anchor ID: IMP_ANCHOR_COLLECT_HOSTS
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
  scanner = import ../scanner.nix;
  utils = import ../lib.nix;

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

  importAndExtract =
    path:
    let
      imported = builtins.tryEval (import path);
    in
    if !imported.success then
      null
    else if builtins.isAttrs imported.value then
      let
        host = utils.extractHost imported.value;
      in
      if host == null then
        null
      else
        {
          __host = host;
          config = imported.value.config or null;
          extraConfig = imported.value.extraConfig or null;
        }
    else
      null;

  collectHosts = scanner.mkScanner {
    extract = importAndExtract;
    processResult =
      acc: path: extracted:
      acc
      // {
        ${getHostName path} = extracted // {
          __source = toString path;
        };
      };
    initial = { };
  };

in
collectHosts
