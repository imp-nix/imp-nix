{
  lib,
  imp,
}:
let
  registryLib = import ../src/registry.nix { inherit lib; };
  lit = imp.withLib lib;
in
{
  # buildRegistry tests
  registry."test builds nested attrset from directory" = {
    expr = registryLib.buildRegistry ./fixtures/registry-test;
    expected = {
      home = {
        __path = ./fixtures/registry-test/home;
        alice = ./fixtures/registry-test/home/alice;
        bob = ./fixtures/registry-test/home/bob.nix;
      };
      modules = {
        __path = ./fixtures/registry-test/modules;
        nixos = {
          __path = ./fixtures/registry-test/modules/nixos;
          base = ./fixtures/registry-test/modules/nixos/base.nix;
        };
        home = {
          __path = ./fixtures/registry-test/modules/home;
          base = ./fixtures/registry-test/modules/home/base.nix;
        };
      };
      hosts = {
        __path = ./fixtures/registry-test/hosts;
        server = ./fixtures/registry-test/hosts/server;
        workstation = ./fixtures/registry-test/hosts/workstation;
      };
    };
  };

  registry."test directory with default.nix returns directory path" = {
    expr = (registryLib.buildRegistry ./fixtures/registry-test).home.alice;
    expected = ./fixtures/registry-test/home/alice;
  };

  registry."test file returns file path" = {
    expr = (registryLib.buildRegistry ./fixtures/registry-test).home.bob;
    expected = ./fixtures/registry-test/home/bob.nix;
  };

  registry."test nested module access" = {
    expr = (registryLib.buildRegistry ./fixtures/registry-test).modules.nixos.base;
    expected = ./fixtures/registry-test/modules/nixos/base.nix;
  };

  registry."test directory without default.nix has __path" = {
    expr = (registryLib.buildRegistry ./fixtures/registry-test).modules.nixos.__path;
    expected = ./fixtures/registry-test/modules/nixos;
  };

  # toPath tests
  registry."test toPath extracts path from registry node" = {
    expr = registryLib.toPath {
      __path = ./test;
      foo = "bar";
    };
    expected = ./test;
  };

  registry."test toPath returns path as-is" = {
    expr = registryLib.toPath ./test;
    expected = ./test;
  };

  # flattenRegistry tests
  registry."test flattens nested attrset to dot notation" = {
    expr = registryLib.flattenRegistry {
      home = {
        __path = ./home;
        alice = ./a;
        bob = ./b;
      };
      modules = {
        __path = ./modules;
        nixos = ./c;
      };
    };
    expected = {
      "home" = ./home;
      "home.alice" = ./a;
      "home.bob" = ./b;
      "modules" = ./modules;
      "modules.nixos" = ./c;
    };
  };

  # lookup tests
  registry."test lookup finds nested path" = {
    expr = registryLib.lookup "modules.nixos" {
      modules = {
        __path = ./modules;
        nixos = {
          __path = ./test-path;
        };
      };
    };
    expected = ./test-path;
  };

  # makeResolver tests
  registry."test resolver returns path for known module" = {
    expr =
      let
        registry = {
          home = {
            __path = ./home;
            alice = ./alice-path;
          };
        };
        resolve = registryLib.makeResolver registry;
      in
      resolve "home.alice";
    expected = ./alice-path;
  };

  registry."test resolver throws for unknown module" = {
    expr =
      let
        registry = {
          home = {
            __path = ./home;
            alice = ./alice-path;
          };
        };
        resolve = registryLib.makeResolver registry;
      in
      resolve "home.unknown";
    expectedError.type = "ThrownError";
  };

  # imp.registry integration
  registry."test imp.registry builds registry from path" = {
    expr = lit.registry ./fixtures/registry-test;
    expected = {
      home = {
        __path = ./fixtures/registry-test/home;
        alice = ./fixtures/registry-test/home/alice;
        bob = ./fixtures/registry-test/home/bob.nix;
      };
      modules = {
        __path = ./fixtures/registry-test/modules;
        nixos = {
          __path = ./fixtures/registry-test/modules/nixos;
          base = ./fixtures/registry-test/modules/nixos/base.nix;
        };
        home = {
          __path = ./fixtures/registry-test/modules/home;
          base = ./fixtures/registry-test/modules/home/base.nix;
        };
      };
      hosts = {
        __path = ./fixtures/registry-test/hosts;
        server = ./fixtures/registry-test/hosts/server;
        workstation = ./fixtures/registry-test/hosts/workstation;
      };
    };
  };

  registry."test imp.registry fails without lib" = {
    expr = imp.registry ./fixtures/registry-test;
    expectedError.type = "EvalError";
  };

  # Using registry paths with imp
  registry."test registry path can be used with imp" = {
    expr =
      let
        reg = lit.registry ./fixtures/registry-test;
        imported = import reg.home.alice;
      in
      imported.name;
    expected = "alice";
  };

  registry."test registry node can be passed to imp" = {
    expr =
      let
        reg = lit.registry ./fixtures/registry-test;
        # modules.nixos is a registry node with __path
        result = imp reg.modules.nixos;
      in
      # Just verify it doesn't throw
      builtins.isAttrs result;
    expected = true;
  };

  registry."test registry node __path works with imp" = {
    expr =
      let
        reg = lit.registry ./fixtures/registry-test;
        # Access __path directly
        result = imp reg.modules.nixos.__path;
      in
      builtins.isAttrs result;
    expected = true;
  };

  # Collision detection tests
  registry."test collision between foo.nix and foo/ throws error" = {
    expr = registryLib.buildRegistry ./fixtures/registry-collision-test;
    expectedError.type = "ThrownError";
    expectedError.msg = ".*collision for attribute 'foo' from multiple sources.*";
  };
}
