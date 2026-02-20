/**
  Anchor ID: IMP_ANCHOR_BUNDLES_ENTRY
  Entry point for imp bundle utilities.

  Bundles are self-contained directories that contribute to flake outputs.
  Bundle helpers focus on configuration discovery and override layering.

  Config layering model:
  * Inner config lives in the bundle itself (`config.nix` or `config/default.nix`)
  * Outer config is a sibling override (`<bundle>.config.nix`)
  * Outer config deep-merges over inner config at evaluation time
*/
import ./module.nix
