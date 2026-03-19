/**
  Anchor ID: IMP_ANCHOR_CONFIG_TREE
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
  fs = import ../fs-model.nix;

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
          entries = fs.listDir {
            inherit dir filterf;
            normalize = fs.normalizeAttrName { };
            entryPointNames = [ "default.nix" ];
          };

          processEntry =
            entry:
            if !entry.included || (isRoot && entry.name == "default.nix") then
              { }
            else if entry.isRegular && entry.isNixFile then
              let
                fileContent = import entry.path;
                value = if builtins.isFunction fileContent then fileContent args else fileContent;
              in
              {
                ${entry.attrName} = value;
              }
            else if entry.isDirectory then
              if entry.hasEntryPoint then
                let
                  fileContent = import entry.path;
                  value = if builtins.isFunction fileContent then fileContent args else fileContent;
                in
                {
                  ${entry.attrName} = value;
                }
              else
                { ${entry.attrName} = buildFromDir entry.path; }
            else
              { };

          processed = map processEntry entries;
        in
        lib.foldl' lib.recursiveUpdate { } processed;
    in
    {
      config = buildFromDir root;
    };
in
buildConfigTree
