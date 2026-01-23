{
  lib,
  imp,
}:
let
  collectOutputs = imp.collectOutputs;
  buildOutputs = imp.buildOutputs;

  testPath = ./fixtures/bundles/outputs/bundles;
in
{
  # Test basic output collection
  outputs."test collect finds __outputs declarations" = {
    expr =
      let
        collected = collectOutputs testPath;
        hasPackagesLint = collected ? "perSystem.packages.lint";
        hasOverlay = collected ? "overlays.myOverlay";
      in
      hasPackagesLint && hasOverlay;
    expected = true;
  };

  outputs."test collected outputs have source paths" = {
    expr =
      let
        collected = collectOutputs testPath;
        lintOutputs = collected."perSystem.packages.lint";
        allHaveSources = lib.all (e: e ? source) lintOutputs;
      in
      allHaveSources;
    expected = true;
  };

  outputs."test collected outputs track strategies" = {
    expr =
      let
        collected = collectOutputs testPath;
        devShellOutputs = collected."perSystem.devShells.default";
        # Both should have merge strategy
        allMerge = lib.all (e: e.strategy == "merge") devShellOutputs;
      in
      allMerge;
    expected = true;
  };

  # Test exclusion of underscore-prefixed files
  outputs."test underscore prefixed files are ignored" = {
    expr =
      let
        collected = collectOutputs testPath;
      in
      !(collected ? "perSystem.packages.shouldNotExist");
    expected = true;
  };

  # Test files without __outputs are skipped
  outputs."test files without __outputs are skipped" = {
    expr =
      let
        collected = collectOutputs testPath;
        # no-outputs.nix has no __outputs, so foo shouldn't appear
        keys = builtins.attrNames collected;
        noFoo = !(lib.any (k: lib.hasInfix "foo" k) keys);
      in
      noFoo;
    expected = true;
  };

  # Test buildOutputs partitioning
  outputs."test buildOutputs separates perSystem and flake" = {
    expr =
      let
        collected = collectOutputs testPath;
        built = buildOutputs { inherit lib collected; };
        hasPerSystem = built ? perSystem;
        hasFlake = built ? flake;
        perSystemHasPackages = built.perSystem ? "packages.lint";
        flakeHasOverlay = built.flake ? "overlays.myOverlay";
      in
      hasPerSystem && hasFlake && perSystemHasPackages && flakeHasOverlay;
    expected = true;
  };

  # Test merge strategy for multiple contributions
  # Note: recursiveUpdate replaces nested values, so lists are last-writer-wins
  outputs."test merge strategy combines function outputs" = {
    expr =
      let
        collected = collectOutputs testPath;
        built = buildOutputs { inherit lib collected; };
        # devShells.default should be a merged function
        devShellFn = built.perSystem."devShells.default";
        # Simulate calling with mock args
        mockPkgs = {
          shellcheck = "shellcheck-pkg";
          jq = "jq-pkg";
        };
        result = devShellFn { pkgs = mockPkgs; };
        # recursiveUpdate replaces lists; tools.nix sorts after lint/ so its value wins
        hasNativeBuildInputs = result ? nativeBuildInputs;
      in
      hasNativeBuildInputs;
    expected = true;
  };

  # Test single contributor uses override by default
  outputs."test single contributor uses override strategy" = {
    expr =
      let
        collected = collectOutputs testPath;
        built = buildOutputs { inherit lib collected; };
        # packages.lint has single contributor
        lintFn = built.perSystem."packages.lint";
        mockPkgs = {
          writeShellScript = name: _: "script-${name}";
        };
        result = lintFn { pkgs = mockPkgs; };
      in
      result == "script-lint";
    expected = true;
  };

  # Test flake-level outputs
  outputs."test flake-level overlays work" = {
    expr =
      let
        collected = collectOutputs testPath;
        built = buildOutputs { inherit lib collected; };
        overlay = built.flake."overlays.myOverlay";
        # Apply overlay
        result = overlay { hello = "hello-pkg"; } { hello = "hello-pkg"; };
      in
      result.myTool == "hello-pkg";
    expected = true;
  };

  # Test multiple paths
  outputs."test multiple source paths work" = {
    expr =
      let
        collected = collectOutputs [ testPath ];
        hasLint = collected ? "perSystem.packages.lint";
      in
      hasLint;
    expected = true;
  };

  # Test empty directory
  outputs."test empty directory returns empty collected" = {
    expr =
      let
        collected = collectOutputs ./fixtures/hello;
      in
      collected == { };
    expected = true;
  };

  # Test single file path
  outputs."test single file path works" = {
    expr =
      let
        collected = collectOutputs ./fixtures/bundles/outputs/bundles/overlay.nix;
        hasOverlay = collected ? "overlays.myOverlay";
      in
      hasOverlay;
    expected = true;
  };

  # Test conflict detection with different strategies
  outputs."test conflicting strategies throw error" = {
    expr = buildOutputs {
      inherit lib;
      collected = {
        "perSystem.packages.foo" = [
          {
            source = "/a.nix";
            value = { };
            strategy = "merge";
          }
          {
            source = "/b.nix";
            value = { };
            strategy = "override";
          }
        ];
      };
    };
    expectedError.type = "ThrownError";
    expectedError.msg = ".*conflicting strategies.*";
  };

  # Test deep merge combines nested attrsets
  outputs."test deep merge combines nested attrsets" = {
    expr =
      let
        collected = collectOutputs testPath;
        built = buildOutputs { inherit lib collected; };
        deepTestFn = built.perSystem."packages.deepTest";
        result = deepTestFn { pkgs = { }; };
        # Both files contribute to nested; recursiveUpdate merges at each level
        hasFromA = result.nested ? fromA;
        hasFromB = result.nested ? fromB;
        # shared.a from first file, shared.b from second - deep merge
        hasSharedA = result.nested.shared ? a;
        hasSharedB = result.nested.shared ? b;
      in
      hasFromA && hasFromB && hasSharedA && hasSharedB;
    expected = true;
  };
}
