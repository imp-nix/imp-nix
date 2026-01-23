/**
  Documentation structure manifest.

  Defines how src/*.nix files are organized into generated docs.
  titleLevel sets the heading level for titles (default: 1).
  Sections are one level below title, files one level below sections.
*/
{
  files = {
    title = "File Reference";
    titleLevel = 1; # H1 for title, H2 for sections, H3 for files, shift by 3 for content

    sections = [
      {
        name = "Core";
        files = [
          "default.nix"
          "api.nix"
          {
            name = "lib.nix";
            fallback = "Internal utility functions for imp.";
          }
        ];
      }
      {
        name = "Import & Collection";
        files = [
          "collect/default.nix"
          "tree/default.nix"
          "tree/fragments.nix"
        ];
      }
      {
        name = "Config Trees";
        files = [
          "tree/config-tree.nix"
          "tree/merge-config-trees.nix"
        ];
      }
      {
        name = "Registry";
        files = [
          "registry.nix"
        ];
      }
      {
        name = "Export Sinks";
        files = [
          "collect/collect-exports.nix"
          "export-sinks.nix"
        ];
      }
      {
        name = "Output Collection";
        files = [
          "collect/collect-outputs.nix"
          "build-outputs.nix"
        ];
      }
      {
        name = "Host Configuration";
        files = [
          "collect/collect-hosts.nix"
          "build-hosts.nix"
        ];
      }
      {
        name = "Flake Integration";
        files = [
          {
            name = "flake/flake-module.nix";
            fallback = "flake-parts module, defines `imp.*` options.";
          }
          {
            name = "flake/options-schema.nix";
            fallback = "Shared options schema for imp.* options.";
          }
          {
            name = "collect/collect-inputs.nix";
            fallback = "`__inputs` collection from flake inputs.";
          }
          "flake/format-flake.nix"
        ];
      }
      {
        name = "Submodules";
        files = [
          {
            name = "formatter/default.nix";
            fallback = "Reusable treefmt configuration with opinionated defaults.";
          }
        ];
      }
    ];
  };

  methods = {
    title = "API Methods";
    titleLevel = 1; # H1 for title, H2 for section headings

    sections = [
      # No heading = top-level, inherits from title
      { file = "api.nix"; }
      {
        heading = "Registry";
        file = "registry.nix";
      }
      {
        heading = "Format Flake";
        file = "flake/format-flake.nix";
      }
      {
        heading = "Export Sinks";
        file = "default.nix";
        exports = [
          "collectExports"
          "buildExportSinks"
          "exportSinks"
        ];
      }
      {
        heading = "Output Collection";
        file = "default.nix";
        exports = [
          "collectOutputs"
          "buildOutputs"
        ];
      }
      {
        heading = "Host Configuration";
        file = "default.nix";
        exports = [
          "collectHosts"
          "buildHosts"
        ];
      }
      {
        heading = "Fragments";
        file = "tree/fragments.nix";
        exports = [
          "collectFragments"
          "collectFragmentsWith"
        ];
      }
      {
        heading = "Standalone Utilities";
        file = "default.nix";
        exports = [
          "collectInputs"
          "collectAndFormatFlake"
        ];
      }
    ];
  };
}
