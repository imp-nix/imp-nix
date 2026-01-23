{
  lib,
  imp,
}:
let
  it = imp;
  lit = it.withLib lib;
in
{
  # Test relative path normalization
  collect."test files from multiple roots are collected" = {
    expr =
      let
        result = lit.leaves [
          ./fixtures/x
          ./fixtures/hello
        ];
      in
      # x has y.nix, hello has no .nix files
      result == [ ./fixtures/x/y.nix ];
    expected = true;
  };

  collect."test nested directory structure is flattened" = {
    expr =
      let
        result = lit.leaves ./fixtures/a;
      in
      # Should find files at multiple levels
      lib.length result > 1 && lib.all (f: lib.hasSuffix ".nix" (toString f)) result;
    expected = true;
  };

  collect."test empty directory returns empty list" = {
    expr =
      let
        result = lit.leaves ./fixtures/hello;
      in
      result;
    expected = [ ];
  };

  # Test filter with registry nodes
  collect."test accepts registry node as path" = {
    expr =
      let
        registryLib = import ../src/registry.nix { inherit lib; };
        registry = registryLib.buildRegistry ./fixtures/registry/basic;
        # home.alice is a registry node with __path
        result = lit.leaves registry.home.alice;
      in
      lib.all (f: lib.hasSuffix ".nix" (toString f)) result;
    expected = true;
  };

  # Test that underscore directories are excluded from results
  collect."test underscore directories are excluded" = {
    expr =
      let
        result = lit.leaves ./fixtures/a;
        # Should not include any path with /_
        hasUnderscoreDir = lib.any (f: lib.hasInfix "/_" (toString f)) result;
      in
      !hasUnderscoreDir;
    expected = true;
  };

  # Test that hidden root directory can still be read
  collect."test hidden root directory is readable" = {
    expr =
      let
        result = lit.leaves ./fixtures/a/b/_c;
      in
      lib.length result > 0;
    expected = true;
  };

  # Test combining filter with paths
  collect."test filter applies across multiple paths" = {
    expr =
      let
        result = (lit.filter (lib.hasSuffix "a.nix")).leaves [
          ./fixtures/a
          ./fixtures/x
        ];
      in
      # Should only get files ending in a.nix from fixtures/a
      lib.all (f: lib.hasSuffix "a.nix" (toString f)) result;
    expected = true;
  };

  # Test that outPath derivations are handled
  collect."test derivation-like objects with outPath work" = {
    expr =
      let
        result = lit.leaves [
          { outPath = ./fixtures/x; }
        ];
      in
      result;
    expected = [ ./fixtures/x/y.nix ];
  };

  # Test mapf is applied after filtering
  collect."test map applies to filtered results" = {
    expr =
      let
        result = ((lit.filter (lib.hasInfix "/x")).map toString).leaves ./fixtures;
      in
      lib.all builtins.isString result;
    expected = true;
  };

  # Test multiple addRoot calls
  collect."test multiple addRoot accumulates paths" = {
    expr =
      let
        result = ((lit.addRoot ./fixtures/x).addRoot ./fixtures/a/b).files;
        paths = map toString result;
      in
      lib.any (lib.hasInfix "/x/") paths && lib.any (lib.hasInfix "/a/b/") paths;
    expected = true;
  };

  # Test pipeTo with custom function
  collect."test pipeTo applies function to results" = {
    expr = (lit.map import).pipeTo lib.length ./fixtures/x;
    expected = 1;
  };

  # Test file is returned directly when path points to file
  collect."test single file path returns that file" = {
    expr = lit.leaves ./fixtures/x/y.nix;
    expected = [ ./fixtures/x/y.nix ];
  };

  # Test initFilter changes what files are matched
  collect."test initFilter for non-nix files" = {
    expr =
      let
        result = (lit.initFilter (lib.hasSuffix ".txt")).leaves ./fixtures/a;
      in
      lib.all (f: lib.hasSuffix ".txt" (toString f)) result;
    expected = true;
  };

  # Test initFilter with non-path values
  collect."test initFilter on module attrsets" = {
    expr =
      let
        # Filter out modules that have a 'skip' attribute
        mod = (it.initFilter (x: !(x ? skip))) [
          {
            options.keep = lib.mkOption {
              default = true;
              type = lib.types.bool;
            };
          }
          {
            skip = true;
            options.remove = lib.mkOption {
              default = false;
              type = lib.types.bool;
            };
          }
        ];
        res = lib.modules.evalModules { modules = [ mod ]; };
      in
      res.config.keep && !(res.config ? remove);
    expected = true;
  };

  # Test matchNot with paths
  collect."test matchNot excludes matching files" = {
    expr =
      let
        result = (lit.matchNot ".*_.*\\.nix").leaves ./fixtures/a;
        # Should not include files with underscore in name
        hasUnderscore = lib.any (f: lib.hasInfix "_" (builtins.baseNameOf (toString f))) result;
      in
      !hasUnderscore && lib.length result > 0;
    expected = true;
  };

  # Test composed filters with match and matchNot
  collect."test match and matchNot compose correctly" = {
    expr =
      let
        # Match .nix but exclude paths with underscore in name
        result = ((lit.match ".*\\.nix").matchNot ".*_.*").leaves ./fixtures/a/b;
      in
      # Should only have m.nix
      result == [ ./fixtures/a/b/m.nix ];
    expected = true;
  };
}
