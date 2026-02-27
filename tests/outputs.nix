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

  outputs."test buildOutputs separates perSystemTransforms" = {
    expr =
      let
        built = buildOutputs {
          inherit lib;
          collected = {
            "perSystemTransforms.devShells" = [
              {
                source = "/transform.nix";
                value = shells: shells;
                strategy = null;
              }
            ];
          };
        };
      in
      built ? perSystemTransforms && built.perSystemTransforms ? devShells;
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

  outputs."test shell-merge strategy composes shell fields" = {
    expr =
      let
        built = buildOutputs {
          inherit lib;
          collected = {
            "perSystem.devShells.default" = [
              {
                source = "/shell-a.nix";
                strategy = "shell-merge";
                value = { };
              }
              {
                source = "/shell-b.nix";
                strategy = "shell-merge";
                value = {
                  packages = [
                    "git"
                    "jq"
                  ];
                  nativeBuildInputs = [ "clang" ];
                  inputsFrom = [ "base" ];
                  shellHook = "echo from-b";
                };
              }
              {
                source = "/shell-c.nix";
                strategy = "shell-merge";
                value = {
                  packages = [
                    "jq"
                    "fd"
                  ];
                  nativeBuildInputs = [
                    "clang"
                    "mold"
                  ];
                  shellHook = "echo from-c";
                };
              }
            ];
          };
        };
        shell = built.perSystem."devShells.default";
      in
      shell.packages == [
        "git"
        "jq"
        "fd"
      ]
      &&
        shell.nativeBuildInputs == [
          "clang"
          "mold"
        ]
      && shell.inputsFrom == [ "base" ]
      && shell.shellHook == "echo from-b\necho from-c";
    expected = true;
  };

  outputs."test shell-merge strategy composes function outputs" = {
    expr =
      let
        built = buildOutputs {
          inherit lib;
          collected = {
            "perSystem.devShells.default" = [
              {
                source = "/shell-a.nix";
                strategy = "shell-merge";
                value = _args: {
                  packages = [ "git" ];
                  shellHook = "echo a";
                };
              }
              {
                source = "/shell-b.nix";
                strategy = "shell-merge";
                value = _args: {
                  packages = [ "jq" ];
                  nativeBuildInputs = [ "clang" ];
                  shellHook = "echo b";
                };
              }
            ];
          };
        };
        shell = built.perSystem."devShells.default" { };
      in
      shell.packages == [
        "git"
        "jq"
      ]
      && shell.nativeBuildInputs == [ "clang" ]
      && shell.shellHook == "echo a\necho b";
    expected = true;
  };

  outputs."test shell-merge strategy rejects non-attrset values" = {
    expr = buildOutputs {
      inherit lib;
      collected = {
        "perSystem.devShells.default" = [
          {
            source = "/bad-shell.nix";
            strategy = "shell-merge";
            value = 42;
          }
        ];
      };
    };
    expectedError.type = "ThrownError";
    expectedError.msg = ".*shell-merge.*";
  };

  outputs."test perSystemTransforms compose in source order" = {
    expr =
      let
        built = buildOutputs {
          inherit lib;
          collected = {
            "perSystemTransforms.devShells" = [
              {
                source = "/10-second.nix";
                value = shells: shells // { order = (shells.order or [ ]) ++ [ "second" ]; };
                strategy = null;
              }
              {
                source = "/00-first.nix";
                value = shells: shells // { order = (shells.order or [ ]) ++ [ "first" ]; };
                strategy = null;
              }
            ];
          };
        };
        transform = built.perSystemTransforms.devShells;
        result = transform { };
      in
      result.order == [
        "first"
        "second"
      ];
    expected = true;
  };

  outputs."test perSystemTransforms override strategy keeps last transform" = {
    expr =
      let
        built = buildOutputs {
          inherit lib;
          collected = {
            "perSystemTransforms.devShells" = [
              {
                source = "/00-first.nix";
                value = shells: shells // { first = true; };
                strategy = "override";
              }
              {
                source = "/10-second.nix";
                value = _: { second = true; };
                strategy = "override";
              }
            ];
          };
        };
        transform = built.perSystemTransforms.devShells;
        result = transform { };
      in
      !(result ? first) && result.second;
    expected = true;
  };

  outputs."test perSystemTransforms supports perSystem-args builder functions" = {
    expr =
      let
        built = buildOutputs {
          inherit lib;
          collected = {
            "perSystemTransforms.devShells" = [
              {
                source = "/builder.nix";
                value = { nciLib, ... }: shells: shells // { default = nciLib.defaultShell; };
                strategy = null;
              }
            ];
          };
        };
        transformWithArgs = built.perSystemTransforms.devShells {
          pkgs = { };
          nciLib.defaultShell = "wrapped-shell";
        };
        result = transformWithArgs { workspace = "base-shell"; };
      in
      result.workspace == "base-shell" && result.default == "wrapped-shell";
    expected = true;
  };

  outputs."test mkWorkspaceShellTransform composes workspace shell with aliases" = {
    expr =
      let
        transformBuilder = imp.mkWorkspaceShellTransform {
          workspace = "workspace";
          aliases = [
            "default"
            "rust"
          ];
          packages = [ "cargo-edit" ];
          shellHook = "echo extra";
        };
        mockPkgs = {
          mkShell = args: args // { __type = "mock-shell"; };
        };
        transform = transformBuilder {
          pkgs = mockPkgs;
          inherit lib;
        };
        baseShell = {
          __type = "base-shell";
          shellHook = "echo base";
        };
        result = transform { workspace = baseShell; };
      in
      result.workspace.__type == "mock-shell"
      && result.default.__type == "mock-shell"
      && result.rust.__type == "mock-shell"
      && result.workspace.inputsFrom == [ baseShell ]
      && result.workspace.packages == [ "cargo-edit" ]
      && result.workspace.shellHook == "echo base\necho extra";
    expected = true;
  };

  outputs."test mkWorkspaceShellTransform throws on alias conflicts" = {
    expr =
      let
        transformBuilder = imp.mkWorkspaceShellTransform {
          workspace = "workspace";
          aliases = [ "default" ];
        };
        transform = transformBuilder {
          pkgs.mkShell = args: args;
          inherit lib;
        };
      in
      transform {
        workspace = { };
        default = { };
      };
    expectedError.type = "ThrownError";
    expectedError.msg = ".*aliases already defined.*";
  };

  outputs."test mkWorkspaceFlakeOutputs delegates to upstream workspace outputs" = {
    expr =
      let
        project = {
          name = "demo";
          kind = "node-workspace";
          workspace = "demo-workspace";
        };
        upstream = {
          devShells.x86_64-linux.demo-workspace = "shell-linux";
          formatter.x86_64-linux = "formatter-linux";
          packages.x86_64-linux.demo = "package-linux";
          checks.x86_64-linux.demo-tests = "check-linux";
        };
        delegated = imp.mkWorkspaceFlakeOutputs {
          inherit project;
          upstreamFlake = upstream;
        };
      in
      delegated.devShells.x86_64-linux.default == "shell-linux"
      && delegated.formatter.x86_64-linux == "formatter-linux"
      && delegated.packages.x86_64-linux.default == "package-linux"
      && delegated.checks.x86_64-linux.default == "check-linux";
    expected = true;
  };

  outputs."test mkWorkspaceFlakeOutputs standalone mode requires runtime nixpkgs" = {
    expr = imp.mkWorkspaceFlakeOutputs {
      project = {
        name = "demo";
        kind = "rust-workspace";
        workspace = "demo-workspace";
        path = ./fixtures/bundles/outputs;
      };
      upstreamFlake = {
        devShells.x86_64-linux.default = { };
      };
    };
    expectedError.type = "ThrownError";
    expectedError.msg = ".*standalone mode requires runtime.nixpkgs.*";
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

  outputs."test conflicting transform strategies throw error" = {
    expr = buildOutputs {
      inherit lib;
      collected = {
        "perSystemTransforms.devShells" = [
          {
            source = "/a.nix";
            value = shells: shells // { fromA = true; };
            strategy = "merge";
          }
          {
            source = "/b.nix";
            value = shells: shells // { fromB = true; };
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
