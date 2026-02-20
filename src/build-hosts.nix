/**
  Anchor ID: IMP_ANCHOR_BUILD_HOSTS
  Generates `nixosConfigurations` from collected host declarations.

  Takes `collectHosts` output and produces NixOS system configurations for
  `flake.nixosConfigurations`. Each host's `__host` schema controls module
  assembly and Home Manager integration.

  # Type

  ```
  buildHosts :: {
    lib, imp, hosts, flakeArgs, hostDefaults?
  } -> { <hostName> = <nixosConfiguration>; }
  ```

  # Module Assembly Order

  1. Merged config tree from `bases` + `config` paths
  2. `home-manager.nixosModules.home-manager`
  3. Resolved sink modules from `sinks`
  4. Home Manager integration module (if `user` set)
  5. Extra modules from `modules`
  6. `extraConfig` module (if present)
  7. `{ system.stateVersion = ...; }`

  # Path Resolution

  Strings in `bases`, `sinks`, `hmSinks`, `modules` resolve as:

  * `"hosts.shared.base"` -> `registry.hosts.shared.base`
  * `"@nixos-wsl.nixosModules.default"` -> `inputs.nixos-wsl.nixosModules.default`

  # Modules as Function

  The `modules` field can be a function receiving `{ registry, inputs, exports }`
  for direct registry access, enabling static analysis:

  ```nix
  __host = {
    modules = { registry, ... }: [
      registry.mod.os.desktop.keyboard
      registry.mod.niri
    ];
  };
  ```

  # Home Manager Integration

  When `user` is set:

  ```nix
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inputs, exports, imp, registry };
    users.${user}.imports = [ <hmSinks> <registry.users.${user}> ];
  };
  ```

  # Example

  ```nix
  buildHosts {
    inherit lib imp;
    hosts = collectHosts ./registry/hosts;
    flakeArgs = { inherit self inputs registry exports; };
    hostDefaults = { system = "x86_64-linux"; };
  }
  # => { desktop = <nixosConfiguration>; server = <nixosConfiguration>; }
  ```
*/
{
  lib,
  imp,
  hosts,
  flakeArgs,
  hostDefaults ? { },
}:
let
  inherit (flakeArgs)
    self
    inputs
    registry
    exports
    ;

  resolveRegistryPath =
    pathStr:
    let
      parts = lib.splitString "." pathStr;
    in
    lib.getAttrFromPath parts registry;

  resolveInputPath =
    pathStr:
    let
      parts = lib.splitString "." pathStr;
    in
    lib.getAttrFromPath parts inputs;

  buildHostModules =
    hostName: hostDef:
    let
      host = hostDef.__host;
      configPath = hostDef.config;
      extraConfig = hostDef.extraConfig;

      basePaths = map (base: if builtins.isString base then (resolveRegistryPath base).__path else base) (
        host.bases or [ ]
      );

      configTreeModule =
        if basePaths != [ ] || configPath != null then
          imp.mergeConfigTrees (basePaths ++ lib.optional (configPath != null) configPath)
        else
          { };

      resolveSink =
        sinkPath:
        let
          parts = lib.splitString "." sinkPath;
        in
        (lib.getAttrFromPath parts exports).__module;

      sinkModules = map resolveSink (host.sinks or [ ]);

      hmModule =
        if host.user or null != null then
          let
            hmSinkModules = map resolveSink (host.hmSinks or [ ]);
            userName = host.user;
            userRegistry =
              if registry ? users && registry.users ? ${userName} then [ registry.users.${userName} ] else [ ];
          in
          {
            home-manager = {
              extraSpecialArgs = {
                inherit
                  inputs
                  exports
                  imp
                  registry
                  ;
              };
              useGlobalPkgs = true;
              useUserPackages = true;

              users.${userName} = {
                imports = hmSinkModules ++ imp.imports userRegistry;
              };
            };
          }
        else
          { };

      resolveModule =
        mod:
        if builtins.isString mod then
          if lib.hasPrefix "@" mod then
            resolveInputPath (lib.removePrefix "@" mod)
          else
            resolveRegistryPath mod
        else
          mod;

      rawModules =
        let
          mods = host.modules or [ ];
        in
        if builtins.isFunction mods then mods { inherit registry inputs exports; } else mods;

      extraModules = map resolveModule rawModules;

      allModules = [
        configTreeModule
        inputs.home-manager.nixosModules.home-manager
      ]
      ++ sinkModules
      ++ [ hmModule ]
      ++ imp.imports extraModules
      ++ lib.optional (extraConfig != null) extraConfig
      ++ [
        { system.stateVersion = host.stateVersion; }
      ];
    in
    allModules;

  buildHost =
    hostName: hostDef:
    let
      host = hostDef.__host;
      system = host.system or hostDefaults.system or "x86_64-linux";
    in
    lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit
          self
          inputs
          exports
          imp
          registry
          ;
      };
      modules = buildHostModules hostName hostDef;
    };

in
lib.mapAttrs buildHost hosts
