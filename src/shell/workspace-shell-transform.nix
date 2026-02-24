/**
  Build a perSystem transform that wraps one workspace shell with extra tools.

  This avoids relying on `overrideAttrs` behavior for devShell derivations.
  The transform builds a new shell via `pkgs.mkShell` and composes the target
  workspace shell through `inputsFrom`.

  # Example

  ```nix
  __outputs.perSystemTransforms.devShells = imp.mkWorkspaceShellTransform {
    workspace = "my-workspace";
    aliases = [ "default" ];
    packages = [ pkgs.cargo-edit pkgs.clang pkgs.mold ];
    shellHook = ''
      export MY_FLAG=1
    '';
  };
  ```
*/
{
  workspace,
  aliases ? [ ],
  packages ? [ ],
  nativeBuildInputs ? [ ],
  buildInputs ? [ ],
  inputsFrom ? [ ],
  shellHook ? "",
  extraMkShellArgs ? { },
}:
{
  pkgs,
  lib,
  ...
}:
shells:
let
  workspaceShell =
    if !builtins.hasAttr workspace shells then
      throw "imp.mkWorkspaceShellTransform: devShells.${workspace} not found"
    else
      shells.${workspace};

  aliasConflicts = builtins.filter (alias: builtins.hasAttr alias shells) aliases;

  aliasConflictGuard =
    if aliasConflicts == [ ] then
      null
    else
      throw (
        "imp.mkWorkspaceShellTransform: aliases already defined for workspace '${workspace}': "
        + builtins.concatStringsSep ", " aliasConflicts
      );

  hookParts = builtins.filter (part: builtins.isString part && part != "") [
    (workspaceShell.shellHook or "")
    shellHook
  ];

  mergedShellHook = lib.concatStringsSep "\n" hookParts;

  mkShellArgs = {
    inputsFrom = lib.unique ([ workspaceShell ] ++ inputsFrom);
  }
  // (if packages == [ ] then { } else { inherit packages; })
  // (if nativeBuildInputs == [ ] then { } else { inherit nativeBuildInputs; })
  // (if buildInputs == [ ] then { } else { inherit buildInputs; })
  // (if mergedShellHook == "" then { } else { shellHook = mergedShellHook; })
  // extraMkShellArgs;

  wrapped = pkgs.mkShell mkShellArgs;

  aliasAttrs = builtins.listToAttrs (
    builtins.map (alias: {
      name = alias;
      value = wrapped;
    }) aliases
  );
in
builtins.seq aliasConflictGuard (shells // { "${workspace}" = wrapped; } // aliasAttrs)
