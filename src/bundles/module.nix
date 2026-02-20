/**
  Internal implementation for bundle utility helpers.
*/
{
  /**
    Scan bundle directories for config files.

    Collects bundle-local configuration from two locations:

    Inner config (inside bundle, owned by bundle/submodule):
    * `<bundle>/config.nix`
    * `<bundle>/config/default.nix`

    Outer config (sibling to bundle, owned by parent project):
    * `<bundle>.config.nix`

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
