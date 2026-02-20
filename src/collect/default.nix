/**
  Entry point for imp file collection and filtering.

  Responsibilities:
  * Recursive file discovery from paths
  * Filter composition and application
  * Path normalization (absolute to relative)
  * Root-relative filtering across multiple roots for stable predicates

  Runtime modes:
  * Module mode (`pipef = null`): returns `{ imports = [ ... ]; }`
  * Data mode (`pipef != null`): pipes collected leaves to the requested
    consumer (for example `.leaves`, `.files`, `.pipeTo`)

  Note for flakes: newly created files are not visible to evaluation until
  they are git-visible. If a file is unexpectedly missing from imp results,
  check git status first.
*/
import ./perform.nix
