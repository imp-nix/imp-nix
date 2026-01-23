{
  lib,
  imp,
}:
let
  lit = imp.withLib lib;
  registryLib = import ../src/registry.nix { inherit lib; };
in
{
  # Basic registry wrapper detection
  imports."test extracts __module from registry wrapper function" = {
    expr =
      let
        modules = lit.imports [ ./fixtures/registry/wrappers/basic.nix ];
        evaluated = lib.evalModules { inherit modules; };
      in
      evaluated.config.test.basic;
    expected = true;
  };

  imports."test extracts __module from attrset with __module" = {
    expr =
      let
        modules = lit.imports [ ./fixtures/registry/wrappers/attrset-with-module.nix ];
        evaluated = lib.evalModules { inherit modules; };
      in
      evaluated.config.test.attrsetModule;
    expected = true;
  };

  imports."test passes through standard modules unchanged" = {
    expr =
      let
        modules = lit.imports [ ./fixtures/registry/wrappers/standard-module.nix ];
        evaluated = lib.evalModules { inherit modules; };
      in
      evaluated.config.test.standard;
    expected = true;
  };

  imports."test handles mixed list of wrappers and standard modules" = {
    expr =
      let
        modules = lit.imports [
          ./fixtures/registry/wrappers/basic.nix
          ./fixtures/registry/wrappers/standard-module.nix
          ./fixtures/registry/wrappers/attrset-with-module.nix
        ];
        evaluated = lib.evalModules { inherit modules; };
      in
      evaluated.config.test.basic
      && evaluated.config.test.standard
      && evaluated.config.test.attrsetModule;
    expected = true;
  };

  imports."test registry wrapper __module can set config values" = {
    expr =
      let
        optionsModule = {
          options.test.fromRegistry = lib.mkOption {
            type = lib.types.str;
            default = "";
          };
        };
        modules = [ optionsModule ] ++ lit.imports [ ./fixtures/registry/wrappers/config-module.nix ];
        evaluated = lib.evalModules { inherit modules; };
      in
      evaluated.config.test.fromRegistry;
    expected = "hello from registry wrapper";
  };

  imports."test nested module with mkIf works" = {
    expr =
      let
        modules = lit.imports [ ./fixtures/registry/wrappers/nested-module.nix ];
        evaluated = lib.evalModules {
          inherit modules;
          specialArgs = { };
        };
      in
      evaluated.config.test.nested.value;
    expected = "default-value";
  };

  imports."test nested module mkIf activates when enabled" = {
    expr =
      let
        modules = lit.imports [ ./fixtures/registry/wrappers/nested-module.nix ] ++ [
          { test.nested.enable = true; }
        ];
        evaluated = lib.evalModules { inherit modules; };
      in
      evaluated.config.test.nested.value;
    expected = "enabled-value";
  };

  # Registry node handling
  imports."test accepts registry nodes with __path" = {
    expr =
      let
        registry = registryLib.buildRegistry ./fixtures/registry/wrappers;
        modules = lit.imports [ registry.basic ];
        evaluated = lib.evalModules { inherit modules; };
      in
      evaluated.config.test.basic;
    expected = true;
  };

  # Inline attrset modules pass through
  imports."test inline attrset modules pass through" = {
    expr =
      let
        modules = lit.imports [
          {
            options.test.inline = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
          }
        ];
        evaluated = lib.evalModules { inherit modules; };
      in
      evaluated.config.test.inline;
    expected = true;
  };

  # Heuristic detection: takes inputs but not config/pkgs
  imports."test isRegistryWrapper heuristic excludes config+inputs" = {
    expr =
      let
        # A function with both config and inputs is NOT a registry wrapper
        mixedModule =
          {
            config,
            inputs ? { },
            lib,
            ...
          }:
          {
            options.test.mixed = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
          };
        modules = lit.imports [ mixedModule ];
        evaluated = lib.evalModules { inherit modules; };
      in
      evaluated.config.test.mixed;
    expected = true;
  };
}
