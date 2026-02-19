/**
  Builds a NixOS/Home Manager module where directory structure = option paths.

  Each file receives module args (`{ config, lib, pkgs, ... }`) plus `extraArgs`,
  and returns config values. The path becomes the option path:

  * `programs/git.nix` -> `{ programs.git = <result>; }`
  * `services/nginx/default.nix` -> `{ services.nginx = <result>; }`

  Treat the directory as a table of contents for your configuration:
  if `programs/git.nix` exists, `programs.git` is defined.

  # Example

  Directory structure:

  ```
  home/
    programs/
      git.nix
      zsh.nix
    services/
      syncthing.nix
  ```

  Example file (home/programs/git.nix):

  ```nix
  { pkgs, ... }: {
    enable = true;
    userName = "Alice";
  }
  ```

  # Usage

  ```nix
  { inputs, ... }:
  {
    imports = [ ((inputs.imp.withLib lib).configTree ./home) ];
  }
  ```

  Equivalent to manually writing:

  ```nix
  programs.git = { enable = true; userName = "Alice"; };
  programs.zsh = { ... };
  services.syncthing = { ... };
  ```

  With extra args:

  ```nix
  ((inputs.imp.withLib lib).configTreeWith { myArg = "value"; } ./home)
  ```
*/
{
  lib,
  filterf,
  extraArgs ? { },
}:
let
  buildConfigTree =
    root:
    {
      config,
      lib,
      pkgs,
      ...
    }@moduleArgs:
    let
      args = moduleArgs // extraArgs;

      buildFromDir =
        dir:
        let
          isRoot = dir == root;
          entries = builtins.readDir dir;

          toAttrName =
            name:
            let
              withoutNix = lib.removeSuffix ".nix" name;
            in
            lib.removeSuffix "_" withoutNix;

          shouldInclude =
            name:
            !(lib.hasPrefix "_" name)
            && !(isRoot && name == "default.nix")
            && filterf (toString dir + "/" + name);

          processEntry =
            name: type:
            let
              path = dir + "/${name}";
              attrName = toAttrName name;
            in
            if type == "regular" && lib.hasSuffix ".nix" name then
              let
                fileContent = import path;
                value = if builtins.isFunction fileContent then fileContent args else fileContent;
              in
              {
                ${attrName} = value;
              }
            else if type == "directory" then
              let
                defaultPath = path + "/default.nix";
                hasDefault = builtins.pathExists defaultPath;
              in
              if hasDefault then
                let
                  fileContent = import path;
                  value = if builtins.isFunction fileContent then fileContent args else fileContent;
                in
                {
                  ${attrName} = value;
                }
              else
                { ${attrName} = buildFromDir path; }
            else
              { };

          filteredEntries = lib.filterAttrs (name: _: shouldInclude name) entries;
          processed = lib.mapAttrsToList processEntry filteredEntries;
        in
        lib.foldl' lib.recursiveUpdate { } processed;
    in
    {
      config = buildFromDir root;
    };
in
buildConfigTree
