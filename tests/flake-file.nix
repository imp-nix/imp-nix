{
  lib,
  imp,
}:
let
  it = imp;
  coreInputsHeader = "# Core inputs";
  collectedInputsHeader = "# Collected from __inputs";
in
{
  # collectInputs tests - collects __inputs from directory tree
  collectInputs."test collects inputs from directory tree" = {
    expr = it.collectInputs ./fixtures/collect-inputs/outputs;
    expected = {
      treefmt-nix = {
        url = "github:numtide/treefmt-nix";
      };
      devenv = {
        url = "github:cachix/devenv";
        inputs.nixpkgs.follows = "nixpkgs";
      };
      home-manager = {
        url = "github:nix-community/home-manager";
        inputs.nixpkgs.follows = "nixpkgs";
      };
    };
  };

  collectInputs."test returns empty attrset for directory without __inputs" = {
    expr = it.collectInputs ./fixtures/hello;
    expected = { };
  };

  collectInputs."test ignores files starting with underscore" = {
    expr = builtins.attrNames (it.collectInputs ./fixtures/collect-inputs/outputs);
    expected = [
      "devenv"
      "home-manager"
      "treefmt-nix"
    ];
  };

  collectInputs."test allows identical duplicate definitions" = {
    expr = it.collectInputs ./fixtures/collect-inputs/duplicate;
    expected = {
      shared = {
        url = "github:owner/shared";
      };
    };
  };

  collectInputs."test throws on conflicting definitions" = {
    expr = it.collectInputs ./fixtures/collect-inputs/conflict;
    expectedError.type = "ThrownError";
  };

  collectInputs."test works on single file" = {
    expr = it.collectInputs ./fixtures/collect-inputs/outputs/perSystem/formatter.nix;
    expected = {
      treefmt-nix = {
        url = "github:numtide/treefmt-nix";
      };
    };
  };

  collectInputs."test returns empty for file without __inputs" = {
    expr = it.collectInputs ./fixtures/collect-inputs/outputs/no-inputs.nix;
    expected = { };
  };

  collectInputs."test extracts __inputs from __functor pattern" = {
    expr = it.collectInputs ./fixtures/registry-wrappers/basic.nix;
    expected = {
      example.url = "github:example/repo";
    };
  };

  collectInputs."test extracts __inputs from attrset with __module" = {
    expr = it.collectInputs ./fixtures/registry-wrappers/attrset-with-module.nix;
    expected = {
      static.url = "github:static/input";
    };
  };

  collectInputs."test collects from __functor pattern directory" = {
    expr = builtins.attrNames (it.collectInputs ./fixtures/registry-wrappers);
    expected = [
      "example"
      "foo"
      "nested"
      "nur"
      "static"
    ];
  };

  collectInputs."test accepts list of paths" = {
    expr = it.collectInputs [
      ./fixtures/registry-wrappers/basic.nix
      ./fixtures/collect-inputs/outputs/perSystem/formatter.nix
    ];
    expected = {
      example.url = "github:example/repo";
      treefmt-nix.url = "github:numtide/treefmt-nix";
    };
  };

  # formatInputs tests
  formatInputs."test formats simple input with url shorthand" = {
    expr = it.formatInputs { nixpkgs.url = "github:nixos/nixpkgs"; };
    expected = ''nixpkgs.url = "github:nixos/nixpkgs";'';
  };

  formatInputs."test formats input with follows using shorthand" = {
    expr = it.formatInputs {
      home-manager = {
        url = "github:nix-community/home-manager";
        inputs.nixpkgs.follows = "nixpkgs";
      };
    };
    expected = "home-manager.url = \"github:nix-community/home-manager\";\n  home-manager.inputs.nixpkgs.follows = \"nixpkgs\";";
  };

  formatInputs."test uses longform when input has extra attrs" = {
    expr = it.formatInputs {
      special = {
        url = "github:owner/repo";
        flake = false;
      };
    };
    expected = ''
      special = {
          flake = false;
          url = "github:owner/repo";
        };'';
  };

  formatInputs."test formats multiple follows" = {
    expr = it.formatInputs {
      multi = {
        url = "github:foo/bar";
        inputs.nixpkgs.follows = "nixpkgs";
        inputs.flake-utils.follows = "flake-utils";
      };
    };
    expected = "multi.url = \"github:foo/bar\";\n  multi.inputs.flake-utils.follows = \"flake-utils\";\n  multi.inputs.nixpkgs.follows = \"nixpkgs\";";
  };

  formatInputs."test sorts inputs alphabetically" = {
    expr = it.formatInputs {
      zzz.url = "a";
      aaa.url = "b";
    };
    expected = ''
      aaa.url = "b";
          zzz.url = "a";'';
  };

  # formatFlake tests
  formatFlake."test generates minimal flake" = {
    expr = it.formatFlake {
      coreInputs = {
        nixpkgs.url = "github:nixos/nixpkgs";
      };
      header = "# test";
    };
    expected = ''
      # test
      {
        inputs = {
          self.submodules = true;

          ${coreInputsHeader}
          nixpkgs.url = "github:nixos/nixpkgs";
        };
        outputs = inputs: import ./nix/flake inputs;
      }
    '';
  };

  formatFlake."test includes description" = {
    expr = lib.hasInfix ''description = "My flake";'' (
      it.formatFlake {
        description = "My flake";
        coreInputs = { };
        header = "";
      }
    );
    expected = true;
  };

  formatFlake."test separates core and collected inputs" = {
    expr =
      let
        result = it.formatFlake {
          coreInputs = {
            nixpkgs.url = "github:nixos/nixpkgs";
          };
          collectedInputs = {
            treefmt-nix.url = "github:numtide/treefmt-nix";
          };
          header = "";
        };
      in
      (lib.hasInfix "${coreInputsHeader}" result) && (lib.hasInfix "${collectedInputsHeader}" result);
    expected = true;
  };

  # collectAndFormatFlake tests
  collectAndFormatFlake."test collects and formats in one step" = {
    expr =
      let
        result = it.collectAndFormatFlake {
          src = ./fixtures/collect-inputs/outputs;
          coreInputs = {
            nixpkgs.url = "github:nixos/nixpkgs";
          };
          header = "";
        };
      in
      (lib.hasInfix "treefmt-nix" result) && (lib.hasInfix "home-manager" result);
    expected = true;
  };
}
