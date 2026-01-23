{
  lib,
  imp,
}:
let
  collectHosts = imp.collectHosts;

  testPath = ./fixtures/collect/hosts;
  hostsPath = testPath + "/hosts";
  registryPath = testPath;
in
{
  # Test basic host collection
  hosts."test collectHosts finds __host declarations" = {
    expr =
      let
        collected = collectHosts hostsPath;
        hasTestHost = collected ? test-host;
        hasFuncHost = collected ? func-host;
      in
      hasTestHost && hasFuncHost;
    expected = true;
  };

  hosts."test collected hosts have system field" = {
    expr =
      let
        collected = collectHosts hostsPath;
        host = collected.test-host.__host;
      in
      host.system;
    expected = "x86_64-linux";
  };

  hosts."test collected hosts have stateVersion field" = {
    expr =
      let
        collected = collectHosts hostsPath;
        host = collected.test-host.__host;
      in
      host.stateVersion;
    expected = "24.11";
  };

  hosts."test modules as list is preserved" = {
    expr =
      let
        collected = collectHosts hostsPath;
        host = collected.test-host.__host;
        modules = host.modules;
      in
      builtins.isList modules && builtins.length modules == 1;
    expected = true;
  };

  hosts."test modules as function is preserved" = {
    expr =
      let
        collected = collectHosts hostsPath;
        host = collected.func-host.__host;
        modules = host.modules;
      in
      builtins.isFunction modules;
    expected = true;
  };

  hosts."test modules function receives registry" = {
    expr =
      let
        collected = collectHosts hostsPath;
        host = collected.func-host.__host;
        # Create a mock registry
        mockRegistry = {
          mod.test-module = {
            __path = "/mock/path";
          };
        };
        # Call the modules function
        result = host.modules {
          registry = mockRegistry;
          inputs = { };
          exports = { };
        };
      in
      builtins.isList result && builtins.length result == 1;
    expected = true;
  };

  hosts."test modules function can access registry nodes" = {
    expr =
      let
        collected = collectHosts hostsPath;
        host = collected.func-host.__host;
        # Create a mock registry with a test module
        mockRegistry = {
          mod.test-module = {
            __path = "/mock/path/to/module.nix";
            __isRegistryNode = true;
          };
        };
        # Call the modules function
        result = host.modules {
          registry = mockRegistry;
          inputs = { };
          exports = { };
        };
        firstMod = builtins.elemAt result 0;
      in
      firstMod.__path == "/mock/path/to/module.nix";
    expected = true;
  };
}
