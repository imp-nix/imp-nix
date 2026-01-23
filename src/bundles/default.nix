/**
  Bundle utilities for imp.

  Bundles are self-contained directories that contribute to flake outputs.
  This module provides utilities for collecting bundle-specific data like
  skills and configuration.
*/
{
  /**
    Scan bundle directories for skills/ subdirectories.

    Collects Claude Code skills from bundles. Each bundle can have a
    skills/ directory containing skill folders. Returns a mapping of
    skill names to their source paths.

    # Example

    ```nix
    imp.bundles.collectSkills [ ./bundles ]
    # => { test-skill = /path/to/bundles/my-bundle/skills/test-skill; }
    ```

    # Arguments

    bundlesParentPaths
    : List of bundles parent directories to scan for skills.
  */
  collectSkills = import ./collect-skills.nix;

  /**
    Scan bundle directories for config files.

    Collects bundle-local configuration from two locations:

    Inner config (inside bundle, owned by bundle/submodule):
    - `<bundle>/config.nix`
    - `<bundle>/config/default.nix`

    Outer config (sibling to bundle, owned by parent project):
    - `<bundle>.config.nix`

    Outer config is useful when bundles are git submodules - the parent
    project can override/extend the bundle's config without modifying
    the submodule. At evaluation time, outer config deep-merges over
    inner config (outer overrides inner).

    Config files can be static attrsets or functions receiving standard
    args like `{ pkgs, lib, ... }`.

    # Example

    ```nix
    imp.bundles.collectConfig [ ./bundles ]
    # => {
    #   "/path/to/bundles/lint" = {
    #     inner = {
    #       value = { enabled = true; };
    #       source = "/path/to/bundles/lint/config.nix";
    #     };
    #     outer = {
    #       value = { enabled = false; };
    #       source = "/path/to/bundles/lint.config.nix";
    #     };
    #   };
    # }
    ```

    # Arguments

    bundlesParentPaths
    : List of bundles parent directories to scan for config files.
  */
  collectConfig = import ./collect-config.nix;
}
