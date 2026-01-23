{
  lib,
  imp,
}:
let
  collectConfig = import ../src/bundles/collect-config.nix;
  fixturesPath = ./fixtures/bundles/config;
in
{
  # Inner config tests
  config."test collectConfig finds inner config.nix in bundle directories" = {
    expr =
      let
        result = collectConfig [ fixturesPath ];
        configKey = builtins.head (
          builtins.filter (k: lib.hasSuffix "bundle-with-config" k && !(lib.hasSuffix "bundle-with-config-dir" k)) (
            builtins.attrNames result
          )
        );
      in
      result.${configKey} ? inner;
    expected = true;
  };

  config."test collectConfig finds inner config/default.nix in bundle directories" = {
    expr =
      let
        result = collectConfig [ fixturesPath ];
        configKey = builtins.head (
          builtins.filter (k: lib.hasSuffix "bundle-with-config-dir" k) (builtins.attrNames result)
        );
      in
      result.${configKey} ? inner;
    expected = true;
  };

  config."test collectConfig ignores bundles without any config" = {
    expr =
      let
        result = collectConfig [ fixturesPath ];
        keys = builtins.attrNames result;
      in
      builtins.length (builtins.filter (k: lib.hasSuffix "bundle-no-config" k) keys) == 0;
    expected = true;
  };

  config."test collectConfig returns inner config value for static config" = {
    expr =
      let
        result = collectConfig [ fixturesPath ];
        configKey = builtins.head (
          builtins.filter (k: lib.hasSuffix "bundle-with-config" k && !(lib.hasSuffix "bundle-with-config-dir" k)) (
            builtins.attrNames result
          )
        );
      in
      result.${configKey}.inner.value.message;
    expected = "hello from config";
  };

  config."test collectConfig returns inner config value for config/default.nix" = {
    expr =
      let
        result = collectConfig [ fixturesPath ];
        configKey = builtins.head (
          builtins.filter (k: lib.hasSuffix "bundle-with-config-dir" k) (builtins.attrNames result)
        );
      in
      result.${configKey}.inner.value.name;
    expected = "config-dir";
  };

  config."test collectConfig returns function for function config" = {
    expr =
      let
        result = collectConfig [ fixturesPath ];
        configKey = builtins.head (
          builtins.filter (k: lib.hasSuffix "bundle-func-config" k) (builtins.attrNames result)
        );
      in
      builtins.isFunction result.${configKey}.inner.value;
    expected = true;
  };

  config."test collectConfig includes source path for inner config" = {
    expr =
      let
        result = collectConfig [ fixturesPath ];
        configKey = builtins.head (
          builtins.filter (k: lib.hasSuffix "bundle-with-config" k && !(lib.hasSuffix "bundle-with-config-dir" k)) (
            builtins.attrNames result
          )
        );
      in
      lib.hasSuffix "config.nix" result.${configKey}.inner.source;
    expected = true;
  };

  # Outer config tests
  config."test collectConfig finds outer sibling config" = {
    expr =
      let
        result = collectConfig [ fixturesPath ];
        configKey = builtins.head (
          builtins.filter (k: lib.hasSuffix "bundle-with-override" k) (builtins.attrNames result)
        );
      in
      result.${configKey} ? outer;
    expected = true;
  };

  config."test collectConfig returns outer config value" = {
    expr =
      let
        result = collectConfig [ fixturesPath ];
        configKey = builtins.head (
          builtins.filter (k: lib.hasSuffix "bundle-with-override" k) (builtins.attrNames result)
        );
      in
      result.${configKey}.outer.value.message;
    expected = "from outer";
  };

  config."test collectConfig includes source path for outer config" = {
    expr =
      let
        result = collectConfig [ fixturesPath ];
        configKey = builtins.head (
          builtins.filter (k: lib.hasSuffix "bundle-with-override" k) (builtins.attrNames result)
        );
      in
      lib.hasSuffix ".config.nix" result.${configKey}.outer.source;
    expected = true;
  };

  config."test collectConfig finds both inner and outer configs" = {
    expr =
      let
        result = collectConfig [ fixturesPath ];
        configKey = builtins.head (
          builtins.filter (k: lib.hasSuffix "bundle-with-override" k) (builtins.attrNames result)
        );
        entry = result.${configKey};
      in
      (entry ? inner) && (entry ? outer);
    expected = true;
  };

  config."test collectConfig finds outer-only config" = {
    expr =
      let
        result = collectConfig [ fixturesPath ];
        configKey = builtins.head (
          builtins.filter (k: lib.hasSuffix "bundle-outer-only" k) (builtins.attrNames result)
        );
        entry = result.${configKey};
      in
      (entry ? outer) && !(entry ? inner);
    expected = true;
  };

  config."test collectConfig outer-only value is correct" = {
    expr =
      let
        result = collectConfig [ fixturesPath ];
        configKey = builtins.head (
          builtins.filter (k: lib.hasSuffix "bundle-outer-only" k) (builtins.attrNames result)
        );
      in
      result.${configKey}.outer.value.source;
    expected = "outer";
  };

  # General tests
  config."test collectConfig is available on imp.bundles" = {
    expr = imp.bundles ? collectConfig;
    expected = true;
  };

  config."test collectConfig handles empty bundles directory" = {
    expr = collectConfig [ ./fixtures/hello ];
    expected = { };
  };
}
