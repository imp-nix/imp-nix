/**
  Build workspace flake outputs from project metadata.

  Modes:
  * delegation mode when `upstreamFlake` already exposes workspace outputs
  * standalone mode when delegation target does not expose workspace outputs

  Standalone mode reads runtime inputs from:
  * explicit `runtime` argument
  * `upstreamFlake.workspaceRuntime` fallback
*/
{
  project,
  upstreamFlake ? null,
  runtime ? null,
  policy ? { },
}:
let
  caller = "imp.mkWorkspaceFlakeOutputs(${project.name})";

  selectAttr =
    {
      attrs,
      name,
      context,
    }:
    if !builtins.hasAttr name attrs then
      throw "${caller}.${context}: attribute '${name}' not found"
    else
      attrs.${name};

  normalizeDefaultPackage =
    defaultPackage:
    if defaultPackage == null then
      null
    else if builtins.isString defaultPackage then
      {
        crate = defaultPackage;
        profile = "release";
      }
    else if !builtins.isAttrs defaultPackage then
      throw "${caller}: defaultPackage must be null, string, or attrset"
    else if !builtins.hasAttr "crate" defaultPackage then
      throw "${caller}: defaultPackage.crate is required"
    else if !builtins.isString defaultPackage.crate || defaultPackage.crate == "" then
      throw "${caller}: defaultPackage.crate must be a non-empty string"
    else
      {
        crate = defaultPackage.crate;
        profile =
          if !builtins.hasAttr "profile" defaultPackage then
            "release"
          else if !builtins.isString defaultPackage.profile || defaultPackage.profile == "" then
            throw "${caller}: defaultPackage.profile must be a non-empty string"
          else
            defaultPackage.profile;
      };

  packageAttrName =
    if project.kind == "node-workspace" || project.kind == "python-workspace" then
      project.name
    else if project.kind == "rust-workspace" then
      let
        normalized = normalizeDefaultPackage (project.defaultPackage or null);
      in
      if normalized == null then null else "${normalized.crate}-${normalized.profile}"
    else
      throw "${caller}: unsupported project kind '${project.kind}'";

  checkAttrName =
    if project.kind == "node-workspace" || project.kind == "python-workspace" then
      "${project.name}-tests"
    else
      null;

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

  systems = effectivePolicy.systems;

  forAllSystems =
    f:
    builtins.listToAttrs (
      builtins.map (system: {
        name = system;
        value = f system;
      }) systems
    );

  hasDelegatedWorkspaceShell =
    if
      upstreamFlake == null
      || !builtins.isAttrs upstreamFlake
      || !builtins.hasAttr "devShells" upstreamFlake
    then
      false
    else
      let
        upstreamDevShells = upstreamFlake.devShells;
      in
      builtins.isAttrs upstreamDevShells
      && builtins.any (
        system:
        let
          shells = upstreamDevShells.${system} or null;
        in
        builtins.isAttrs shells && builtins.hasAttr project.workspace shells
      ) (builtins.attrNames upstreamDevShells);

  delegatedOutputs =
    let
      packageName = packageAttrName;
      checkName = checkAttrName;
      upstreamDevShells = selectAttr {
        attrs = upstreamFlake;
        name = "devShells";
        context = "devShells";
      };
      upstreamFormatter = selectAttr {
        attrs = upstreamFlake;
        name = "formatter";
        context = "formatter";
      };
      upstreamPackages =
        if packageName == null then
          null
        else
          selectAttr {
            attrs = upstreamFlake;
            name = "packages";
            context = "packages";
          };
      upstreamChecks =
        if checkName == null then
          null
        else
          selectAttr {
            attrs = upstreamFlake;
            name = "checks";
            context = "checks";
          };
    in
    {
      devShells = builtins.mapAttrs (system: shells: {
        default = selectAttr {
          attrs = shells;
          name = project.workspace;
          context = "devShells.${system}";
        };
      }) upstreamDevShells;

      formatter = upstreamFormatter;

      packages =
        if packageName == null then
          { }
        else
          builtins.mapAttrs (system: packages: {
            default = selectAttr {
              attrs = packages;
              name = packageName;
              context = "packages.${system}";
            };
          }) upstreamPackages;

      checks =
        if checkName == null then
          { }
        else
          builtins.mapAttrs (system: checks: {
            default = selectAttr {
              attrs = checks;
              name = checkName;
              context = "checks.${system}";
            };
          }) upstreamChecks;
    };

  runtimeFromUpstream =
    if
      upstreamFlake != null
      && builtins.isAttrs upstreamFlake
      && builtins.hasAttr "workspaceRuntime" upstreamFlake
    then
      upstreamFlake.workspaceRuntime
    else
      { };

  runtimeArg = if runtime == null then { } else runtime;
  resolvedRuntime = runtimeFromUpstream // runtimeArg;

  nixpkgsInput =
    if builtins.hasAttr "nixpkgs" resolvedRuntime then
      resolvedRuntime.nixpkgs
    else
      throw "${caller}: standalone mode requires runtime.nixpkgs (or upstreamFlake.workspaceRuntime.nixpkgs)";

  projectPath =
    if builtins.hasAttr "path" project then
      project.path
    else
      throw "${caller}: standalone mode requires project.path (for example ./. in workspace flake)";

  resolvePkgsPath =
    {
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
      pkgs,
      attrName,
      label,
    }:
    if !builtins.hasAttr attrName pkgs then
      throw "${caller}: pkgs.${attrName} not found for ${label}"
    else
      pkgs.${attrName};

  standaloneFormatter = forAllSystems (
    system:
    let
      pkgs = import nixpkgsInput { inherit system; };
    in
    pkgs.nixfmt-rfc-style
  );

  standaloneRustOutputs = {
    formatter = standaloneFormatter;

    devShells = forAllSystems (
      system:
      let
        pkgs = import nixpkgsInput { inherit system; };
        defaultPaths = effectivePolicy.rust.defaultShellPackages or [ ];
        availableSets = effectivePolicy.rust.shellPackageSets or { };
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
            inherit pkgs pathText;
            label = "rust workspace shell package";
          }
        ) packagePaths;
        rustToolchain = builtins.filter (pkg: pkg != null) [
          (if pkgs ? rustc then pkgs.rustc else null)
          (if pkgs ? cargo then pkgs.cargo else null)
          (if pkgs ? rustfmt then pkgs.rustfmt else null)
          (if pkgs ? clippy then pkgs.clippy else null)
        ];
        toolchain =
          if rustToolchain == [ ] then
            throw "${caller}: unable to resolve rust toolchain packages from nixpkgs"
          else
            rustToolchain;
      in
      {
        default = pkgs.mkShell {
          packages = toolchain ++ extraPackages;
        };
      }
    );

    packages = { };

    checks = forAllSystems (
      system:
      let
        pkgs = import nixpkgsInput { inherit system; };
        rustToolchain = builtins.filter (pkg: pkg != null) [
          (if pkgs ? rustc then pkgs.rustc else null)
          (if pkgs ? cargo then pkgs.cargo else null)
          (if pkgs ? rustfmt then pkgs.rustfmt else null)
          (if pkgs ? clippy then pkgs.clippy else null)
        ];
        toolchain =
          if rustToolchain == [ ] then
            throw "${caller}: unable to resolve rust toolchain packages from nixpkgs"
          else
            rustToolchain;
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

  standaloneNodeOutputs = {
    formatter = standaloneFormatter;

    devShells = forAllSystems (
      system:
      let
        pkgs = import nixpkgsInput { inherit system; };
        node = getPolicyPackage {
          inherit pkgs;
          attrName = effectivePolicy.node.interpreterAttr;
          label = "nodejs interpreter";
        };
        defaultPaths = effectivePolicy.node.defaultShellPackages or [ ];
        projectPaths = project.shellPackages or [ ];
        packagePaths = pkgs.lib.unique (defaultPaths ++ projectPaths);
        extraPackages = builtins.map (
          pathText:
          resolvePkgsPath {
            inherit pkgs pathText;
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

    packages = forAllSystems (
      system:
      let
        pkgs = import nixpkgsInput { inherit system; };
        node = getPolicyPackage {
          inherit pkgs;
          attrName = effectivePolicy.node.interpreterAttr;
          label = "nodejs interpreter";
        };
        packageJson = builtins.fromJSON (builtins.readFile (projectPath + "/package.json"));
        version =
          if packageJson ? version && builtins.isString packageJson.version && packageJson.version != "" then
            packageJson.version
          else
            "0.1.0";
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

    checks = forAllSystems (
      system:
      let
        pkgs = import nixpkgsInput { inherit system; };
        node = getPolicyPackage {
          inherit pkgs;
          attrName = effectivePolicy.node.interpreterAttr;
          label = "nodejs interpreter";
        };
        packageJson = builtins.fromJSON (builtins.readFile (projectPath + "/package.json"));
        version =
          if packageJson ? version && builtins.isString packageJson.version && packageJson.version != "" then
            packageJson.version
          else
            "0.1.0";
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

  standalonePythonOutputs = {
    formatter = standaloneFormatter;

    devShells = forAllSystems (
      system:
      let
        pkgs = import nixpkgsInput { inherit system; };
        python = getPolicyPackage {
          inherit pkgs;
          attrName = effectivePolicy.python.interpreterAttr;
          label = "python interpreter";
        };
        uv = getPolicyPackage {
          inherit pkgs;
          attrName = effectivePolicy.python.uvPackageAttr;
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
            export UV_PROJECT_ENVIRONMENT="''${UV_PROJECT_ENVIRONMENT:-$PWD/${effectivePolicy.python.sharedVenvDir}/${project.name}}"
            export UV_LINK_MODE=copy
          '';
        };
      }
    );

    packages = forAllSystems (
      system:
      let
        pkgs = import nixpkgsInput { inherit system; };
        python = getPolicyPackage {
          inherit pkgs;
          attrName = effectivePolicy.python.interpreterAttr;
          label = "python interpreter";
        };
        uv = getPolicyPackage {
          inherit pkgs;
          attrName = effectivePolicy.python.uvPackageAttr;
          label = "uv";
        };
        moduleName = builtins.replaceStrings [ "-" ] [ "_" ] project.name;
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

    checks = forAllSystems (
      system:
      let
        pkgs = import nixpkgsInput { inherit system; };
        python = getPolicyPackage {
          inherit pkgs;
          attrName = effectivePolicy.python.interpreterAttr;
          label = "python interpreter";
        };
        uv = getPolicyPackage {
          inherit pkgs;
          attrName = effectivePolicy.python.uvPackageAttr;
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

  standaloneOutputs =
    if project.kind == "rust-workspace" then
      standaloneRustOutputs
    else if project.kind == "node-workspace" then
      standaloneNodeOutputs
    else if project.kind == "python-workspace" then
      standalonePythonOutputs
    else
      throw "${caller}: unsupported project kind '${project.kind}'";
in
if hasDelegatedWorkspaceShell then delegatedOutputs else standaloneOutputs
