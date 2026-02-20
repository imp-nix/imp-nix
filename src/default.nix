/**
  Anchor ID: IMP_ANCHOR_ENTRYPOINT
  Primary imp entrypoint.

  Philosophy:
  * The filesystem is the source of truth.
  * Add/remove files to change behavior; avoid manual import wiring.
  * Keep module intent next to implementation via special attrs
    (`__inputs`, `__outputs`, `__exports`, `__host`).

  In flake evaluation, only git-visible files are scanned. New files should
  be tracked before expecting imp to discover them.

  Main surface area exported by imp:
  * Chainable import API (`filter`, `map`, `tree`, `configTree`, ...)
  * Collectors/builders for `__inputs`, `__outputs`, `__exports`, `__host`
  * Registry utilities (`registry`, `imp.imports` support)
  * Flake formatting helpers (`formatInputs`, `formatFlake`)
*/
import ./imp.nix
