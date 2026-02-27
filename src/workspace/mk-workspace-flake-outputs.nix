/**
  Build workspace flake outputs from project metadata.

  Modes:
  * delegation mode when `upstreamFlake` already exposes workspace outputs
  * standalone mode by dispatching to `runtime.adapters.<project.kind>`

  Standalone runtime resolution:
  * explicit `runtime` argument
  * `upstreamFlake.workspaceRuntime` fallback
*/
{
  project,
  upstreamFlake ? null,
  runtime ? null,
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

  ensureAttrset =
    {
      value,
      label,
    }:
    if !builtins.isAttrs value then throw "${caller}: ${label} must be an attrset" else value;

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
  resolvedRuntime = ensureAttrset {
    value = runtimeFromUpstream // runtimeArg;
    label = "runtime";
  };

  adapters =
    if builtins.hasAttr "adapters" resolvedRuntime then
      ensureAttrset {
        value = resolvedRuntime.adapters;
        label = "runtime.adapters";
      }
    else
      throw "${caller}: standalone mode requires runtime.adapters (or upstreamFlake.workspaceRuntime.adapters)";

  adapter =
    if builtins.hasAttr project.kind adapters then
      adapters.${project.kind}
    else
      let
        available = builtins.attrNames adapters;
        availableText = if available == [ ] then "<none>" else builtins.concatStringsSep ", " available;
      in
      throw "${caller}: no standalone adapter for project.kind '${project.kind}' (available: ${availableText})";

  rawStandaloneOutputs =
    if builtins.isFunction adapter then
      adapter {
        inherit
          caller
          project
          upstreamFlake
          ;
        runtime = resolvedRuntime;
      }
    else
      throw "${caller}: runtime.adapters.${project.kind} must be a function";

  standaloneOutputsAttrs = ensureAttrset {
    value = rawStandaloneOutputs;
    label = "standalone adapter result";
  };

  standaloneOutputs = {
    devShells = ensureAttrset {
      value = selectAttr {
        attrs = standaloneOutputsAttrs;
        name = "devShells";
        context = "standalone.devShells";
      };
      label = "standalone.devShells";
    };
    formatter = ensureAttrset {
      value = selectAttr {
        attrs = standaloneOutputsAttrs;
        name = "formatter";
        context = "standalone.formatter";
      };
      label = "standalone.formatter";
    };
    packages =
      if builtins.hasAttr "packages" standaloneOutputsAttrs then
        ensureAttrset {
          value = standaloneOutputsAttrs.packages;
          label = "standalone.packages";
        }
      else
        { };
    checks =
      if builtins.hasAttr "checks" standaloneOutputsAttrs then
        ensureAttrset {
          value = standaloneOutputsAttrs.checks;
          label = "standalone.checks";
        }
      else
        { };
  };
in
if hasDelegatedWorkspaceShell then delegatedOutputs else standaloneOutputs
