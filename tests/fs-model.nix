{
  lib,
  ...
}:
let
  fs = import ../src/fs-model.nix;
in
{
  fsModel."test normalizeAttrName strips nix fragment and escape suffixes" = {
    expr = fs.normalizeAttrName { stripFragment = true; } "packages_.d";
    expected = "packages";
  };

  fsModel."test listDir classifies directory entry points and fragments" = {
    expr =
      let
        entries = fs.listDir {
          dir = ./fixtures/tree/fragments;
          normalize = fs.normalizeAttrName { stripFragment = true; };
          entryPointNames = [ "default.nix" ];
        };
        byName = builtins.listToAttrs (map (entry: lib.nameValuePair entry.name entry) entries);
      in
      {
        appsIsNixFile = (builtins.getAttr "apps.nix" byName).isNixFile;
        packagesIsFragment = (builtins.getAttr "packages.d" byName).isFragmentDir;
      };
    expected = {
      appsIsNixFile = true;
      packagesIsFragment = true;
    };
  };

  fsModel."test listDir reports fragment directories and leaf directories" = {
    expr =
      let
        entries = fs.listDir {
          dir = ./fixtures/collect/hosts/hosts;
          normalize = fs.normalizeAttrName { };
          entryPointNames = [ "default.nix" ];
        };
        byName = builtins.listToAttrs (map (entry: lib.nameValuePair entry.name entry) entries);
      in
      {
        funcHostHasEntryPoint = (builtins.getAttr "func-host" byName).hasEntryPoint;
        testHostHasEntryPoint = (builtins.getAttr "test-host" byName).hasEntryPoint;
      };
    expected = {
      funcHostHasEntryPoint = true;
      testHostHasEntryPoint = true;
    };
  };
}
