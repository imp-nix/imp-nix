{
  lib,
  imp,
}:
let
  it = imp;
  lit = it.withLib lib;
in
{
  # Tree tests
  tree."test fails if no lib has been set" = {
    expr = it.tree ./fixtures/tree-test;
    expectedError.type = "EvalError";
  };

  tree."test builds nested attrset from directory" = {
    expr = lit.tree ./fixtures/tree-test;
    expected = {
      default = {
        isDefault = true;
      };
      top = {
        level = "top";
      };
      packages = {
        foo = {
          name = "foo";
        };
        bar = {
          name = "bar";
        };
      };
      modules = {
        simple = {
          value = "simple";
        };
        nested = {
          deep = {
            value = "deep";
          };
        };
      };
    };
  };

  tree."test can access nested attributes" = {
    expr = (lit.tree ./fixtures/tree-test).packages.foo.name;
    expected = "foo";
  };

  tree."test suffix_ escapes to attribute name" = {
    expr = (lit.tree ./fixtures/tree-test).default;
    expected = {
      isDefault = true;
    };
  };

  tree."test deeply nested access" = {
    expr = (lit.tree ./fixtures/tree-test).modules.nested.deep.value;
    expected = "deep";
  };

  tree."test filter applies to tree" = {
    expr = (lit.filter (lib.hasInfix "packages")).tree ./fixtures/tree-test;
    expected = {
      packages = {
        foo = {
          name = "foo";
        };
        bar = {
          name = "bar";
        };
      };
    };
  };

  tree."test .d directories merge nix files as attrsets" = {
    expr = lit.tree ./fixtures/tree-d-test;
    expected = {
      apps = {
        myApp = {
          type = "app";
        };
      };
      packages = {
        default = {
          name = "default-pkg";
        };
        # core is recursively merged: base + override
        core = {
          name = "core-pkg";
          version = "2.0";
        };
        extra = {
          name = "extra-pkg";
        };
      };
    };
  };

  tree."test .d directories process files in sorted order" = {
    # 10-extras.nix comes after 00-core.nix, so its values take precedence
    expr = (lit.tree ./fixtures/tree-d-test).packages.core;
    expected = {
      name = "core-pkg"; # from 00-core
      version = "2.0"; # from 10-extras (recursiveUpdate adds this)
    };
  };

  tree."test .d and .nix with same name are merged" = {
    # packages.nix provides base, packages.d/ adds more - they should merge
    expr = lit.tree ./fixtures/tree-conflict-test;
    expected = {
      packages = {
        fromBase = {
          name = "base-pkg";
        };
        fromFragment = {
          name = "fragment-pkg";
        };
      };
    };
  };

  tree."test .d directories work with mapTree (functions)" = {
    expr = (lit.mapTree (f: f { prefix = "test"; })).tree ./fixtures/tree-d-functor;
    expected = {
      packages = {
        default = {
          name = "test-default";
        };
        extra = {
          name = "test-extra";
        };
      };
    };
  };

  tree."test .d with only shell files is skipped" = {
    # shellHook.d/ contains .sh files, not .nix - should be skipped entirely
    # (shell files are handled by imp.fragments for string concatenation)
    expr = (lit.tree ./fixtures/tree-test) ? shellHook;
    expected = false; # shellHook.d should not create a shellHook attr (no .nix files)
  };

  tree."test collision between foo.nix and foo/ throws error" = {
    expr = lit.tree ./fixtures/tree-collision-test;
    expectedError.type = "ThrownError";
    expectedError.msg = ".*collision for attribute 'foo' from multiple sources.*";
  };

  tree."test .d works for arbitrary names (not just flake outputs)" = {
    # myCustom.d/ is not a known flake output name, but should still work
    expr = lit.tree ./fixtures/tree-generic-d;
    expected = {
      myCustom = {
        first = true;
        second = true;
        common = "from-second"; # later fragment wins
      };
      regular = {
        value = "regular";
      };
    };
  };

  # mapTree tests
  mapTree."test transforms imported values" = {
    expr = (lit.mapTree (x: x // { extra = true; })).tree ./fixtures/tree-test/packages;
    expected = {
      foo = {
        name = "foo";
        extra = true;
      };
      bar = {
        name = "bar";
        extra = true;
      };
    };
  };

  mapTree."test multiple mapTrees compose" = {
    expr =
      ((lit.mapTree (x: x // { first = true; })).mapTree (x: x // { second = true; })).tree
        ./fixtures/tree-test/packages;
    expected = {
      foo = {
        name = "foo";
        first = true;
        second = true;
      };
      bar = {
        name = "bar";
        first = true;
        second = true;
      };
    };
  };

  # configTree tests - builds modules where path = option path
  configTree."test fails if no lib has been set" = {
    expr = it.configTree ./fixtures/config-tree;
    expectedError.type = "EvalError";
  };

  configTree."test builds nested config from directory structure" = {
    expr =
      let
        module = lit.configTree ./fixtures/config-tree;
        mockArgs = {
          config = { };
          lib = lib;
          pkgs = { };
        };
        result = module mockArgs;
      in
      result.config;
    expected = {
      programs = {
        git = {
          enable = true;
          userName = "Test User";
        };
        zsh = {
          enable = true;
          autosuggestion.enable = true;
        };
      };
      services = {
        nginx = {
          enable = true;
          recommendedGzipSettings = true;
        };
      };
      top-level = {
        value = "top";
        computed = "ab";
      };
    };
  };

  configTree."test can access deeply nested config values" = {
    expr =
      let
        module = lit.configTree ./fixtures/config-tree;
        mockArgs = {
          config = { };
          lib = lib;
          pkgs = { };
        };
        result = module mockArgs;
      in
      result.config.programs.git.userName;
    expected = "Test User";
  };

  configTree."test directory with default.nix is treated as single value" = {
    expr =
      let
        module = lit.configTree ./fixtures/config-tree;
        mockArgs = {
          config = { };
          lib = lib;
          pkgs = { };
        };
        result = module mockArgs;
      in
      result.config.services.nginx;
    expected = {
      enable = true;
      recommendedGzipSettings = true;
    };
  };

  configTree."test filter applies to configTree" = {
    expr =
      let
        module = (lit.filter (lib.hasInfix "programs")).configTree ./fixtures/config-tree;
        mockArgs = {
          config = { };
          lib = lib;
          pkgs = { };
        };
        result = module mockArgs;
      in
      result.config;
    expected = {
      programs = {
        git = {
          enable = true;
          userName = "Test User";
        };
        zsh = {
          enable = true;
          autosuggestion.enable = true;
        };
      };
    };
  };

  # configTreeWith tests
  configTreeWith."test passes extra args to config files" = {
    expr =
      let
        module = lit.configTreeWith { customArg = "hello"; } ./fixtures/config-tree-extra;
        mockArgs = {
          config = { };
          lib = lib;
          pkgs = { };
        };
        result = module mockArgs;
      in
      result.config;
    expected = {
      test = {
        fromCustomArg = "hello";
      };
    };
  };

  # Test that default.nix at root is skipped (to allow wrapper pattern)
  configTree."test skips default.nix at root level" = {
    expr =
      let
        module = lit.configTree ./fixtures/config-tree-with-default;
        mockArgs = {
          config = { };
          lib = lib;
          pkgs = { };
          imp = lit;
        };
        result = module mockArgs;
      in
      result.config;
    expected = {
      programs = {
        git = {
          enable = true;
          userName = "Test";
        };
      };
    };
  };

  # mergeConfigTrees tests - merge multiple trees with later overriding earlier
  mergeConfigTrees."test fails if no lib has been set" = {
    expr = it.mergeConfigTrees [ ./fixtures/mixed-tree/base ];
    expectedError.type = "EvalError";
  };

  mergeConfigTrees."test merges multiple trees" = {
    expr =
      let
        module = lit.mergeConfigTrees [
          ./fixtures/mixed-tree/base
          ./fixtures/mixed-tree/extended
        ];
        mockArgs = {
          config = { };
          lib = lib;
          pkgs = { };
        };
        result = module mockArgs;
      in
      result.config;
    expected = {
      programs = {
        # From base only
        starship = {
          enable = true;
        };
        # From extended only
        git = {
          enable = true;
          userName = "Alice";
        };
        # Merged: base + extended overrides
        zsh = {
          enable = true; # from base
          autocd = false; # from extended (overrides base's true)
          dotDir = ".config/zsh"; # from extended (new)
        };
        # Merged: bash from both
        bash = {
          shellAliases = {
            ll = "ls -l";
            la = "ls -la";
            g = "git";
            ga = "git add";
          };
          initExtra = "# Dev shell init\nexport VISUAL=nvim\n"; # extended overrides
        };
      };
    };
  };

  mergeConfigTrees."test single tree works like configTree" = {
    expr =
      let
        module = lit.mergeConfigTrees [ ./fixtures/mixed-tree/base ];
        mockArgs = {
          config = { };
          lib = lib;
          pkgs = { };
        };
        result = module mockArgs;
      in
      result.config;
    expected = {
      programs = {
        starship = {
          enable = true;
        };
        zsh = {
          enable = true;
          autocd = true;
        };
        bash = {
          shellAliases = {
            ll = "ls -l";
            la = "ls -la";
          };
          initExtra = "# Base shell init\nexport EDITOR=vim\n";
        };
      };
    };
  };

  mergeConfigTrees."test order matters - later overrides earlier" = {
    expr =
      let
        # Reverse order - base should override extended
        module = lit.mergeConfigTrees [
          ./fixtures/mixed-tree/extended
          ./fixtures/mixed-tree/base
        ];
        mockArgs = {
          config = { };
          lib = lib;
          pkgs = { };
        };
        result = module mockArgs;
      in
      result.config.programs.zsh;
    expected = {
      enable = true;
      autocd = true; # base wins now
      dotDir = ".config/zsh"; # extended's addition preserved
    };
  };

  mergeConfigTrees."test options syntax - strategy override" = {
    expr =
      let
        module = lit.mergeConfigTrees { strategy = "override"; } [
          ./fixtures/mixed-tree/base
          ./fixtures/mixed-tree/extended
        ];
        mockArgs = {
          config = { };
          lib = lib;
          pkgs = { };
        };
        result = module mockArgs;
      in
      result.config.programs.zsh;
    expected = {
      enable = true;
      autocd = false;
      dotDir = ".config/zsh";
    };
  };

  # Test merge strategy with actual module evaluation
  mergeConfigTrees."test merge strategy concatenates lines options" = {
    expr =
      let
        testModule =
          { lib, ... }:
          {
            options.shell = {
              aliases = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = { };
              };
              init = lib.mkOption {
                type = lib.types.lines;
                default = "";
              };
            };
          };

        mergeTree = lit.mergeConfigTrees { strategy = "merge"; } [
          ./fixtures/merge-strategy/base
          ./fixtures/merge-strategy/extended
        ];

        evaluated = lib.evalModules {
          modules = [
            testModule
            mergeTree
          ];
        };
      in
      evaluated.config.shell;
    expected = {
      aliases = {
        ll = "ls -l";
        g = "git";
      };
      init = "# base init\n\n# extended init\n";
    };
  };

  mergeConfigTrees."test override strategy replaces lines options" = {
    expr =
      let
        testModule =
          { lib, ... }:
          {
            options.shell = {
              aliases = lib.mkOption {
                type = lib.types.attrsOf lib.types.str;
                default = { };
              };
              init = lib.mkOption {
                type = lib.types.lines;
                default = "";
              };
            };
          };

        overrideTree = lit.mergeConfigTrees { strategy = "override"; } [
          ./fixtures/merge-strategy/base
          ./fixtures/merge-strategy/extended
        ];

        evaluated = lib.evalModules {
          modules = [
            testModule
            overrideTree
          ];
        };
      in
      evaluated.config.shell;
    expected = {
      aliases = {
        ll = "ls -l";
        g = "git";
      };
      init = "# extended init\n"; # base's init is replaced, not concatenated
    };
  };

  mergeConfigTrees."test extraArgs option passes args to files" = {
    expr =
      let
        module =
          lit.mergeConfigTrees
            {
              extraArgs = {
                customArg = "hello";
              };
            }
            [
              ./fixtures/config-tree-extra
            ];
        mockArgs = {
          config = { };
          lib = lib;
          pkgs = { };
        };
        result = module mockArgs;
      in
      result.config;
    expected = {
      test = {
        fromCustomArg = "hello";
      };
    };
  };
}
