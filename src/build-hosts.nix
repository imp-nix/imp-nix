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

  Strings in `sinks` and `hmSinks` resolve as export sink paths:

  * `"shared.nixos"` -> `exports.shared.nixos`

  Strings in `bases` and `modules` resolve only as `@`-prefixed input paths:

  * `"@nixos-wsl.nixosModules.default"` -> `inputs.nixos-wsl.nixosModules.default`
  * otherwise use raw path values

  # Modules as Function

  The `modules` field can be a function receiving `{ inputs, exports }`:

  ```nix
  __host = {
    modules = { inputs, ... }: [
      inputs.agenix.nixosModules.default
      ./desktop-module.nix
    ];
  };
  ```

  # Home Manager Integration

  When `user` is set:

  ```nix
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inputs, exports, imp };
    users.${user}.imports = [ <hmSinks> ];
  };
  ```

  # Example

  ```nix
  buildHosts {
    inherit lib imp;
    hosts = collectHosts ./hosts;
    flakeArgs = { inherit self inputs exports; };
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
    exports
    ;

  resolveInputPath =
    pathStr:
    let
      parts = lib.splitString "." pathStr;
    in
    lib.getAttrFromPath parts inputs;

  buildHostModules =
    hostName: hostDef:
    let
      isAbsolutePathString = value: builtins.isString value && lib.hasPrefix "/" value;

      resolveHostPath =
        kind: value:
        if builtins.isString value then
          if lib.hasPrefix "@" value then
            resolveInputPath (lib.removePrefix "@" value)
          else if isAbsolutePathString value then
            value
          else
            throw "imp.buildHosts: host '${hostName}' ${kind} '${value}' must be a path or @input.path."
        else
          value;

      host = hostDef.__host;
      configPath = hostDef.config;
      extraConfig = hostDef.extraConfig;

      basePaths = map (resolveHostPath "base") (host.bases or [ ]);

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
          in
          {
            home-manager = {
              extraSpecialArgs = {
                inherit
                  inputs
                  exports
                  imp
                  ;
              };
              useGlobalPkgs = true;
              useUserPackages = true;

              users.${userName} = {
                imports = hmSinkModules;
              };
            };
          }
        else
          { };

      resolveModule =
        mod:
        if builtins.isString mod then
          resolveHostPath "module" mod
        else
          mod;

      rawModules =
        let
          mods = host.modules or [ ];
        in
        if builtins.isFunction mods then mods { inherit inputs exports; } else mods;

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
          ;
      };
      modules = buildHostModules hostName hostDef;
    };

in
lib.mapAttrs buildHost hosts
