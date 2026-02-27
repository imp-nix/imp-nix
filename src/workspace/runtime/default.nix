/**
  Build the default standalone runtime for `imp.mkWorkspaceFlakeOutputs`.

  The runtime is an attrset with:
  * `nixpkgs`: nixpkgs input used to import system package sets
  * `policy`: merged defaults for system matrix and language-specific settings
  * `adapters`: standalone output builders keyed by `project.kind`

  Consumers can override behavior by:
  * constructing a custom runtime and passing `runtime = ...`
  * overriding `runtime.adapters.<kind>` for specific project kinds
*/
{
  nixpkgs,
  policy ? { },
}:
let
  defaultSystems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];

  defaultPolicy = {
    systems = defaultSystems;
    rust = {
      defaultShellPackages = [
        "cargo-edit"
        "pkg-config"
        "openssl"
      ];
      shellPackageSets = {
        bevy = [
          "wayland"
          "libxkbcommon"
          "alsa-lib"
          "udev"
          "libx11"
          "libxcursor"
          "libxi"
          "libxrandr"
          "vulkan-loader"
          "vulkan-headers"
          "vulkan-tools"
          "vulkan-validation-layers"
        ];
      };
    };
    python = {
      interpreterAttr = "python3";
      uvPackageAttr = "uv";
      sharedVenvDir = ".venvs";
    };
    node = {
      interpreterAttr = "nodejs_22";
      defaultShellPackages = [ "nodePackages.pnpm" ];
    };
  };

  effectivePolicy = {
    systems = if builtins.hasAttr "systems" policy then policy.systems else defaultPolicy.systems;
    rust = defaultPolicy.rust // (policy.rust or { });
    python = defaultPolicy.python // (policy.python or { });
    node = defaultPolicy.node // (policy.node or { });
  };

  forAllSystems =
    systems: f:
    builtins.listToAttrs (
      builtins.map (system: {
        name = system;
        value = f system;
      }) systems
    );

  resolveNixpkgs =
    {
      runtime,
    }:
    if builtins.hasAttr "nixpkgs" runtime then runtime.nixpkgs else nixpkgs;

  resolvePolicy =
    {
      caller,
      runtime,
    }:
    let
      runtimePolicy =
        if !builtins.hasAttr "policy" runtime then
          effectivePolicy
        else if !builtins.isAttrs runtime.policy then
          throw "${caller}: runtime.policy must be an attrset"
        else
          runtime.policy;
    in
    {
      systems =
        if builtins.hasAttr "systems" runtimePolicy then runtimePolicy.systems else effectivePolicy.systems;
      rust = defaultPolicy.rust // (runtimePolicy.rust or { });
      python = defaultPolicy.python // (runtimePolicy.python or { });
      node = defaultPolicy.node // (runtimePolicy.node or { });
    };

  requireProjectPath =
    {
      caller,
      project,
    }:
    if builtins.hasAttr "path" project then
      project.path
    else
      throw "${caller}: standalone mode requires project.path (for example ./. in workspace flake)";

  resolvePkgsPath =
    {
      caller,
      pkgs,
      pathText,
      label,
    }:
    let
      segments = pkgs.lib.splitString "." pathText;
    in
    if segments == [ ] || builtins.any (segment: segment == "") segments then
      throw "${caller}: invalid pkgs path '${pathText}' for ${label}"
    else if !pkgs.lib.hasAttrByPath segments pkgs then
      throw "${caller}: pkgs path '${pathText}' not found for ${label}"
    else
      pkgs.lib.attrByPath segments null pkgs;

  getPolicyPackage =
    {
      caller,
      pkgs,
      attrName,
      label,
    }:
    if !builtins.hasAttr attrName pkgs then
      throw "${caller}: pkgs.${attrName} not found for ${label}"
    else
      pkgs.${attrName};

  resolveRustToolchain =
    {
      caller,
      pkgs,
    }:
    let
      rustToolchain = builtins.filter (pkg: pkg != null) [
        (if pkgs ? rustc then pkgs.rustc else null)
        (if pkgs ? cargo then pkgs.cargo else null)
        (if pkgs ? rustfmt then pkgs.rustfmt else null)
        (if pkgs ? clippy then pkgs.clippy else null)
      ];
    in
    if rustToolchain == [ ] then
      throw "${caller}: unable to resolve rust toolchain packages from nixpkgs"
    else
      rustToolchain;

  mkFormatter =
    {
      systems,
      nixpkgsInput,
    }:
    forAllSystems systems (
      system:
      let
        pkgs = import nixpkgsInput { inherit system; };
      in
      pkgs.nixfmt-rfc-style
    );

  rustAdapter =
    {
      caller,
      project,
      runtime,
      ...
    }:
    let
      projectPath = requireProjectPath { inherit caller project; };
      nixpkgsInput = resolveNixpkgs { inherit runtime; };
      resolvedPolicy = resolvePolicy { inherit caller runtime; };
      systems = resolvedPolicy.systems;
      rustPolicy = resolvedPolicy.rust;
    in
    {
      formatter = mkFormatter {
        inherit systems nixpkgsInput;
      };

      devShells = forAllSystems systems (
        system:
        let
          pkgs = import nixpkgsInput { inherit system; };
          defaultPaths = rustPolicy.defaultShellPackages or [ ];
          availableSets = rustPolicy.shellPackageSets or { };
          setNames = project.shellPackageSets or [ ];
          setPaths = builtins.concatLists (
            builtins.map (
              setName:
              if !builtins.hasAttr setName availableSets then
                throw "${caller}: unknown rust shell package set '${setName}' for project '${project.name}'"
              else
                availableSets.${setName}
            ) setNames
          );
          projectPaths = project.shellPackages or [ ];
          packagePaths = pkgs.lib.unique (defaultPaths ++ setPaths ++ projectPaths);
          extraPackages = builtins.map (
            pathText:
            resolvePkgsPath {
              inherit caller pkgs pathText;
              label = "rust workspace shell package";
            }
          ) packagePaths;
          toolchain = resolveRustToolchain { inherit caller pkgs; };
        in
        {
          default = pkgs.mkShell {
            packages = toolchain ++ extraPackages;
          };
        }
      );

      packages = { };

      checks = forAllSystems systems (
        system:
        let
          pkgs = import nixpkgsInput { inherit system; };
          toolchain = resolveRustToolchain { inherit caller pkgs; };
          nativeBuildInputs =
            toolchain
            ++ (builtins.filter (pkg: pkg != null) [
              (if pkgs ? pkg-config then pkgs.pkg-config else null)
              (if pkgs ? openssl then pkgs.openssl else null)
            ]);
        in
        {
          default = pkgs.runCommand "${project.name}-tests" { inherit nativeBuildInputs; } ''
            set -euo pipefail
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            cp -R ${projectPath} "$TMPDIR/project"
            chmod -R u+w "$TMPDIR/project"
            cd "$TMPDIR/project"
            cargo test --workspace --all-targets
            touch "$out"
          '';
        }
      );
    };

  nodeAdapter =
    {
      caller,
      project,
      runtime,
      ...
    }:
    let
      projectPath = requireProjectPath { inherit caller project; };
      nixpkgsInput = resolveNixpkgs { inherit runtime; };
      resolvedPolicy = resolvePolicy { inherit caller runtime; };
      systems = resolvedPolicy.systems;
      nodePolicy = resolvedPolicy.node;
      packageJson = builtins.fromJSON (builtins.readFile (projectPath + "/package.json"));
      version =
        if packageJson ? version && builtins.isString packageJson.version && packageJson.version != "" then
          packageJson.version
        else
          "0.1.0";
    in
    {
      formatter = mkFormatter {
        inherit systems nixpkgsInput;
      };

      devShells = forAllSystems systems (
        system:
        let
          pkgs = import nixpkgsInput { inherit system; };
          node = getPolicyPackage {
            inherit caller pkgs;
            attrName = nodePolicy.interpreterAttr;
            label = "nodejs interpreter";
          };
          defaultPaths = nodePolicy.defaultShellPackages or [ ];
          projectPaths = project.shellPackages or [ ];
          packagePaths = pkgs.lib.unique (defaultPaths ++ projectPaths);
          extraPackages = builtins.map (
            pathText:
            resolvePkgsPath {
              inherit caller pkgs pathText;
              label = "node workspace shell package";
            }
          ) packagePaths;
        in
        {
          default = pkgs.mkShell {
            packages = [ node ] ++ extraPackages;
          };
        }
      );

      packages = forAllSystems systems (
        system:
        let
          pkgs = import nixpkgsInput { inherit system; };
          node = getPolicyPackage {
            inherit caller pkgs;
            attrName = nodePolicy.interpreterAttr;
            label = "nodejs interpreter";
          };
          src = pkgs.lib.cleanSourceWith {
            src = projectPath;
            filter =
              path: type:
              let
                baseName = builtins.baseNameOf path;
              in
              pkgs.lib.cleanSourceFilter path type && baseName != "node_modules" && baseName != "dist";
          };
        in
        {
          default = pkgs.buildNpmPackage {
            pname = project.name;
            inherit version src;
            nodejs = node;
            npmDeps = pkgs.importNpmLock {
              npmRoot = src;
            };
            npmConfigHook = pkgs.importNpmLock.npmConfigHook;
            npmBuildScript = "build";
            doCheck = false;
            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
              cp -R dist node_modules package.json package-lock.json "$out/"
              runHook postInstall
            '';
          };
        }
      );

      checks = forAllSystems systems (
        system:
        let
          pkgs = import nixpkgsInput { inherit system; };
          node = getPolicyPackage {
            inherit caller pkgs;
            attrName = nodePolicy.interpreterAttr;
            label = "nodejs interpreter";
          };
          src = pkgs.lib.cleanSourceWith {
            src = projectPath;
            filter =
              path: type:
              let
                baseName = builtins.baseNameOf path;
              in
              pkgs.lib.cleanSourceFilter path type && baseName != "node_modules" && baseName != "dist";
          };
        in
        {
          default = pkgs.buildNpmPackage {
            pname = "${project.name}-tests";
            inherit version src;
            nodejs = node;
            npmDeps = pkgs.importNpmLock {
              npmRoot = src;
            };
            npmConfigHook = pkgs.importNpmLock.npmConfigHook;
            npmBuildScript = "build";
            doCheck = true;
            checkPhase = ''
              runHook preCheck
              npm test
              runHook postCheck
            '';
            installPhase = ''
              runHook preInstall
              touch "$out"
              runHook postInstall
            '';
          };
        }
      );
    };

  pythonAdapter =
    {
      caller,
      project,
      runtime,
      ...
    }:
    let
      projectPath = requireProjectPath { inherit caller project; };
      nixpkgsInput = resolveNixpkgs { inherit runtime; };
      resolvedPolicy = resolvePolicy { inherit caller runtime; };
      systems = resolvedPolicy.systems;
      pythonPolicy = resolvedPolicy.python;
      moduleName = builtins.replaceStrings [ "-" ] [ "_" ] project.name;
    in
    {
      formatter = mkFormatter {
        inherit systems nixpkgsInput;
      };

      devShells = forAllSystems systems (
        system:
        let
          pkgs = import nixpkgsInput { inherit system; };
          python = getPolicyPackage {
            inherit caller pkgs;
            attrName = pythonPolicy.interpreterAttr;
            label = "python interpreter";
          };
          uv = getPolicyPackage {
            inherit caller pkgs;
            attrName = pythonPolicy.uvPackageAttr;
            label = "uv";
          };
        in
        {
          default = pkgs.mkShell {
            packages = [
              python
              uv
            ];
            shellHook = ''
              export UV_PROJECT_ENVIRONMENT="''${UV_PROJECT_ENVIRONMENT:-$PWD/${pythonPolicy.sharedVenvDir}/${project.name}}"
              export UV_LINK_MODE=copy
            '';
          };
        }
      );

      packages = forAllSystems systems (
        system:
        let
          pkgs = import nixpkgsInput { inherit system; };
          python = getPolicyPackage {
            inherit caller pkgs;
            attrName = pythonPolicy.interpreterAttr;
            label = "python interpreter";
          };
          uv = getPolicyPackage {
            inherit caller pkgs;
            attrName = pythonPolicy.uvPackageAttr;
            label = "uv";
          };
        in
        {
          default = pkgs.writeShellApplication {
            name = project.name;
            runtimeInputs = [
              python
              uv
            ];
            text = ''
              set -euo pipefail
              cd ${projectPath}
              export PYTHONPATH="${projectPath}/src''${PYTHONPATH:+:''${PYTHONPATH}}"
              exec uv run --no-project --no-managed-python --python ${python}/bin/python3 python -m ${moduleName} "$@"
            '';
          };
        }
      );

      checks = forAllSystems systems (
        system:
        let
          pkgs = import nixpkgsInput { inherit system; };
          python = getPolicyPackage {
            inherit caller pkgs;
            attrName = pythonPolicy.interpreterAttr;
            label = "python interpreter";
          };
          uv = getPolicyPackage {
            inherit caller pkgs;
            attrName = pythonPolicy.uvPackageAttr;
            label = "uv";
          };
        in
        {
          default =
            pkgs.runCommand "${project.name}-tests"
              {
                nativeBuildInputs = [
                  python
                  uv
                ];
              }
              ''
                set -euo pipefail
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME"
                export UV_CACHE_DIR="$TMPDIR/uv-cache"
                cp -R ${projectPath} "$TMPDIR/project"
                chmod -R u+w "$TMPDIR/project"
                cd "$TMPDIR/project"
                export PYTHONPATH="$TMPDIR/project/src''${PYTHONPATH:+:''${PYTHONPATH}}"
                uv run --no-project --no-managed-python --python ${python}/bin/python3 python -m unittest discover -s tests -t .
                touch "$out"
              '';
        }
      );
    };
in
{
  inherit nixpkgs;
  policy = effectivePolicy;
  adapters = {
    "rust-workspace" = rustAdapter;
    "node-workspace" = nodeAdapter;
    "python-workspace" = pythonAdapter;
  };
}
