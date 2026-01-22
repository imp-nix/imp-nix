# API Methods

<!-- Auto-generated - do not edit -->

## `imp.filter` {#imp.filter}

Filter paths by predicate. Multiple filters compose with AND.

### Example

```nix
imp.filter (lib.hasInfix "/services/") ./modules
imp.filterNot (lib.hasInfix "/deprecated/") ./modules
```

### Arguments

predicate
: Function that receives a path string and returns boolean.

## `imp.filterNot` {#imp.filterNot}

Exclude paths matching predicate. Opposite of filter.

### Example

```nix
imp.filterNot (lib.hasInfix "/deprecated/") ./modules
```

### Arguments

predicate
: Function that receives a path string and returns boolean.

## `imp.match` {#imp.match}

Filter paths by regex. Uses `builtins.match`.

### Example

```nix
imp.match ".*[/]services[/].*" ./nix
```

### Arguments

regex
: Regular expression string.

## `imp.matchNot` {#imp.matchNot}

Exclude paths matching regex. Opposite of match.

### Example

```nix
imp.matchNot ".*[/]test[/].*" ./src
```

### Arguments

regex
: Regular expression string.

## `imp.initFilter` {#imp.initFilter}

Replace the default filter. By default, imp finds `.nix` files
and excludes paths containing underscore prefixes.

### Example

```nix
# Import markdown files instead of nix files
imp.initFilter (lib.hasSuffix ".md") ./docs
```

### Arguments

predicate
: Function that receives a path string and returns boolean.

## `imp.map` {#imp.map}

Transform each matched path. Composes with multiple calls.

### Example

```nix
imp.map import ./packages
```

### Arguments

f
: Transformation function applied to each path or value.

## `imp.mapTree` {#imp.mapTree}

Transform values when building a tree with `.tree`. Composes with multiple calls.

### Example

```nix
(imp.withLib lib)
  .mapTree (drv: drv // { meta.priority = 5; })
  .tree ./packages
```

### Arguments

f
: Transformation function applied to each tree value.

## `imp.withLib` {#imp.withLib}

Provide nixpkgs `lib`. Required before using `.leaves`, `.files`, `.tree`, or `.configTree`.

### Example

```nix
imp.withLib pkgs.lib
imp.withLib inputs.nixpkgs.lib
```

### Arguments

lib
: The nixpkgs lib attribute set.

## `imp.addRoot` {#imp.addRoot}

Add additional roots to search.

### Example

```nix
(imp.withLib lib)
  .addRoot ./modules
  .addRoot ./vendor
  .leaves
```

### Arguments

root
: Root path to add to the search.

## `imp.addAPI` {#imp.addAPI}

Extend imp with custom methods. Methods receive `self` for chaining.

### Example

```nix
let
  myImp = imp.addAPI {
    services = self: self.filter (lib.hasInfix "/services/");
    packages = self: self.filter (lib.hasInfix "/packages/");
  };
in
myImp.services ./nix
```

### Arguments

api
: Attribute set of name = self: ... methods.

## `imp.pipeTo` {#imp.pipeTo}

Apply a function to the final file list.

### Example

```nix
(imp.withLib lib).pipeTo builtins.length ./modules
```

### Arguments

f
: Function to apply to the file list.

## `imp.leaves` {#imp.leaves}

Get the list of matched files. Requires `.withLib`.

### Example

```nix
(imp.withLib lib).leaves ./modules
```

## `imp.tree` {#imp.tree}

Build a nested attrset from directory structure. Requires `.withLib`.

Directory names become attribute names. Files are imported and their
values placed at the corresponding path.

### Example

```nix
(imp.withLib lib).tree ./outputs
# { packages.hello = <imported>; apps.run = <imported>; }
```

### Arguments

path
: Root directory to build tree from.

## `imp.treeWith` {#imp.treeWith}

Convenience function combining `.withLib`, `.mapTree`, and `.tree`.

### Example

```nix
# These are equivalent:
((imp.withLib lib).mapTree (f: f args)).tree ./outputs
imp.treeWith lib (f: f args) ./outputs
```

### Arguments

lib
: The nixpkgs lib attribute set.

f
: Transformation function for tree values.

path
: Root directory to build tree from.

## `imp.configTree` {#imp.configTree}

Build a module where directory structure maps to NixOS option paths.
Each file receives module args and returns config values.

### Example

```nix
{ inputs, lib, ... }: {
  imports = [ ((inputs.imp.withLib lib).configTree ./config) ];
}
# File ./config/programs/git.nix sets config.programs.git
```

### Arguments

path
: Root directory containing config files.

## `imp.configTreeWith` {#imp.configTreeWith}

Like `.configTree` but passes extra arguments to each file.

### Example

```nix
(imp.withLib lib).configTreeWith { myArg = "value"; } ./config
```

### Arguments

extraArgs
: Additional arguments passed to each config file.

path
: Root directory containing config files.

## `imp.mergeConfigTrees` {#imp.mergeConfigTrees}

Merge multiple config trees into a single module.

### Example

```nix
# Later trees override earlier (default)
(imp.withLib lib).mergeConfigTrees [ ./base ./overrides ]

# With mkMerge semantics
(imp.withLib lib).mergeConfigTrees { strategy = "merge"; } [ ./base ./local ]
```

### Arguments

options (optional)
: Attribute set with `strategy` (`"override"` or `"merge"`) and `extraArgs`.

paths
: List of directories to merge.

## `imp.new` {#imp.new}

Returns a fresh imp instance with empty state, preserving custom API extensions.

### Example

```nix
let
  customImp = imp.addAPI { myMethod = self: self.filter predicate; };
  fresh = customImp.new;
in
fresh.myMethod ./src
```

## `imp.imports` {#imp.imports}

Build a modules list from mixed items. Handles paths, registry nodes, and modules.

For registry nodes or paths that import to attrsets with `__module`,
extracts just the `__module`. For functions that are "registry wrappers"
(take `inputs` arg and return attrsets with `__module`), wraps them to
extract `__module` from the result.

This allows registry modules to declare `__inputs` and `__overlays`
without polluting the module system.

### Example

```nix
modules = imp.imports [
  registry.hosts.server
  registry.modules.nixos.base
  ./local-module.nix
  inputs.home-manager.nixosModules.home-manager
  { services.openssh.enable = true; }
];
```

### Arguments

items
: List of paths, registry nodes, or module values.

## `imp.fragments` {#imp.fragments}

Collect fragments from a `.d` directory. Requires `.withLib`.

Follows the `.d` convention where fragments are sorted by filename
and composed together. Files are processed in order (00-base before 10-extra).

Returns an attrset with multiple access methods:

- `.list` - raw list of fragment contents
- `.asString` - fragments concatenated with newlines (for shell scripts)
- `.asList` - fragments flattened (for lists of packages)
- `.asAttrs` - fragments merged (for attrsets)

Note: For known flake output directories (packages.d, devShells.d, etc.),
tree.nix auto-merges fragments. Use `imp.fragments` for other `.d` dirs
like shellHook.d or shell-packages.d.

### Example

```nix
let
  imp = inputs.imp.withLib lib;

  # Shell scripts concatenated
  shellHookFragments = imp.fragments ./shellHook.d;

  # Package lists merged
  shellPkgFragments = imp.fragmentsWith { inherit pkgs self'; } ./shell-packages.d;
in
pkgs.mkShell {
  packages = shellPkgFragments.asList;
  shellHook = shellHookFragments.asString;
}
```

### Arguments

dir
: Directory ending in `.d` containing fragments (.nix or .sh files).

## `imp.fragmentsWith` {#imp.fragmentsWith}

Collect fragments with arguments passed to each .nix file.

Like `fragments`, but calls each .nix fragment as a function with the
provided arguments. Shell (.sh) files are still read as strings.

### Example

```nix
# Each file in shell-packages.d/ is called with { pkgs, self' }
# and should return a list like [ pkgs.ripgrep pkgs.fd ]
shellPkgs = (imp.withLib lib).fragmentsWith { inherit pkgs self'; } ./shell-packages.d;
packages = shellPkgs.asList;
```

### Arguments

args
: Attrset of arguments to pass to each fragment function.

dir
: Directory containing fragments.

## Registry

## `imp.buildRegistry` {#imp.buildRegistry}

Build registry from a directory. Each directory gets `__path` plus child entries.

### Arguments

- `root` (path): Root directory path to scan.

## `imp.flattenRegistry` {#imp.flattenRegistry}

Flatten registry to dot-notation paths.

```nix
flattenRegistry registry
# => { home.alice = <path>; modules.nixos.base = <path>; }
```

`registry`

: Function argument

## `imp.lookup` {#imp.lookup}

Lookup a dotted path in the registry.

```nix
lookup "home.alice" registry  # => <path>
```

`path`

: Function argument

`registry`

: Function argument

## `imp.makeResolver` {#imp.makeResolver}

Create resolver function: name -> path.

```nix
resolve = makeResolver registry;
resolve "home.alice"  # => <path>
```

`registry`

: Function argument

## Format Flake

## `imp.formatValue` {#imp.formatValue}

Format a value as Nix source code.

### Arguments

depth
: Indentation depth level.

value
: Value to format (string, bool, int, null, list, or attrset).

## `imp.formatInput` {#imp.formatInput}

Format a single input definition (at depth 1).

### Arguments

name
: Input name.

def
: Input definition attrset.

## `imp.formatInputs` {#imp.formatInputs}

Format multiple inputs as a block.

### Example

```nix
formatInputs { treefmt-nix = { url = "github:numtide/treefmt-nix"; }; }
# => "treefmt-nix.url = \"github:numtide/treefmt-nix\";"
```

### Arguments

inputs
: Attrset of input definitions.

## `imp.formatFlake` {#imp.formatFlake}

Generate complete flake.nix content.

### Example

```nix
formatFlake {
  description = "My flake";
  coreInputs = { nixpkgs.url = "github:nixos/nixpkgs"; };
  collectedInputs = { treefmt-nix.url = "github:numtide/treefmt-nix"; };
}
```

### Arguments

description
: Flake description string (optional).

coreInputs
: Core flake inputs attrset (optional).

collectedInputs
: Collected inputs from \_\_inputs declarations (optional).

outputsFile
: Path to outputs file (default: "./nix/flake").

header
: Header comment for generated file (optional).

## Export Sinks

## `imp.collectExports` {#imp.collectExports}

Scan directories for `__exports` declarations and collect them.

Recursively scans .nix files for `__exports` attribute declarations
and collects them, tracking source paths. Returns an attrset mapping
sink keys to lists of export records.

Only attrsets with `__exports` are collected. For functions that need
to declare exports, use the `__functor` pattern:

```nix
{
  __exports."nixos.role.desktop" = {
    value = { services.pipewire.enable = true; };
    strategy = "merge";
  };
  __functor = _: { inputs, ... }: { __module = ...; };
}
```

### Example

```nix
imp.collectExports ./registry
# => {
#   "nixos.role.desktop" = [
#     {
#       source = "/path/to/audio.nix";
#       value = { services.pipewire.enable = true; };
#       strategy = "merge";
#     }
#   ];
# }
```

### Arguments

pathOrPaths
: Directory/file path, or list of paths, to scan for \_\_exports declarations.

## `imp.buildExportSinks` {#imp.buildExportSinks}

Build export sinks from collected exports.

Takes collected exports and merges them according to their strategies,
producing a nested attrset of sinks. Each sink contains merged values
and metadata about contributors.

### Example

```nix
buildExportSinks {
  lib = nixpkgs.lib;
  collected = imp.collectExports ./registry;
  sinkDefaults = {
    "nixos.*" = "merge";
    "hm.*" = "merge";
  };
}
# => {
#   nixos.role.desktop = {
#     __module = { ... };
#     __meta = { contributors = [...]; strategy = "merge"; };
#   };
# }
```

### Arguments

lib
: nixpkgs lib for merge operations.

collected
: Output from collectExports.

sinkDefaults
: Optional attrset mapping glob patterns to default strategies.

enableDebug
: Include \_\_meta with contributor info (default: true).

## Output Collection

## `imp.collectOutputs` {#imp.collectOutputs}

Scan directories for `__outputs` declarations and collect them.

Enables self-contained bundles to contribute to multiple flake output types.
perSystem outputs receive { pkgs, lib, system, ... } at evaluation time.

### Example

```nix
imp.collectOutputs ./bundles
# => {
#   "perSystem.packages.lint" = [
#     { source = "/lint/default.nix"; value = <function>; strategy = null; }
#   ];
#   "perSystem.devShells.default" = [
#     { source = "/shell.nix"; value = <function>; strategy = "merge"; }
#   ];
# }
```

### Arguments

pathOrPaths
: Directory/file path, or list of paths, to scan for \_\_outputs declarations.

## `imp.buildOutputs` {#imp.buildOutputs}

Build flake outputs from collected \_\_outputs declarations.

Separates perSystem outputs from flake-level outputs and merges
contributions according to their strategies.

### Example

```nix
buildOutputs {
  lib = nixpkgs.lib;
  collected = imp.collectOutputs ./bundles;
}
# => {
#   perSystem = { "packages.lint" = <function>; "devShells.default" = <merged-function>; };
#   flake = { "overlays.myOverlay" = <value>; };
# }
```

### Arguments

lib
: nixpkgs lib for merge operations.

collected
: Output from collectOutputs.

## Host Configuration

## `imp.collectHosts` {#imp.collectHosts}

Scan directories for `__host` declarations and collect them.

Recursively scans .nix files for `__host` attribute declarations
and collects host configuration metadata.

### Example

```nix
imp.collectHosts ./registry/hosts
# => {
#   desktop = {
#     __host = { system = "x86_64-linux"; stateVersion = "24.11"; ... };
#     __source = "/path/to/desktop/default.nix";
#     config = ./config;
#   };
# }
```

### Arguments

pathOrPaths
: Directory/file path, or list of paths, to scan for \_\_host declarations.

## `imp.buildHosts` {#imp.buildHosts}

Build nixosConfigurations from collected host declarations.

Takes host declarations and generates nixosConfigurations attrset.

### Example

```nix
buildHosts {
  lib = nixpkgs.lib;
  imp = impWithLib;
  hosts = imp.collectHosts ./hosts;
  flakeArgs = { self, inputs, registry, exports, ... };
}
# => { desktop = <nixosConfiguration>; vm = <nixosConfiguration>; }
```

### Arguments

lib
: nixpkgs lib (must have nixosSystem).

imp
: Bound imp instance with lib.

hosts
: Output from collectHosts.

flakeArgs
: Standard flake args { self, inputs, registry, exports, ... }.

hostDefaults
: Default values for host config (optional).

## Fragments

## `imp.collectFragments` {#imp.collectFragments}

Collect fragments from a .d directory.

### Arguments

- `dir` (path): Directory ending in .d containing fragments

### Returns

Attrset with:

- `list`: List of fragment contents in sorted order
- `asString`: Fragments concatenated with newlines
- `asList`: Fragments flattened (for lists of lists)
- `asAttrs`: Fragments merged (for attrsets)

Returns empty results if directory doesn't exist.

## `imp.collectFragmentsWith` {#imp.collectFragmentsWith}

Collect fragments with arguments passed to each .nix file.

### Arguments

- `args` (attrset): Arguments to pass to each fragment function
- `dir` (path): Directory containing fragments

### Returns

Same as collectFragments but each .nix fragment is called with args.

## Standalone Utilities

## `imp.collectInputs` {#imp.collectInputs}

Scan directories for `__inputs` declarations and collect them.

Recursively scans .nix files for `__inputs` attribute declarations
and merges them into a single attrset. Detects conflicts when the
same input name has different definitions in different files.

Only attrsets with `__inputs` are collected. For files that need to
be functions (e.g., to receive `inputs` at runtime), use the `__functor`
pattern so `__inputs` is accessible without calling the function:

```nix
{
  __inputs.foo.url = "github:foo/bar";
  __functor = _: { inputs, ... }: inputs.foo.lib.something;
}
```

Accepts either a single path or a list of paths. When given multiple
paths, all are scanned and merged with conflict detection.

### Example

```nix
# Single path
imp.collectInputs ./outputs
# => { treefmt-nix = { url = "github:numtide/treefmt-nix"; }; }

# Multiple paths
imp.collectInputs [ ./outputs ./registry ]
# => { treefmt-nix = { ... }; nur = { ... }; }
```

### Arguments

pathOrPaths
: Directory/file path, or list of paths, to scan for \_\_inputs declarations.

## `imp.collectAndFormatFlake` {#imp.collectAndFormatFlake}

Convenience function combining collectInputs and formatFlake.

Scans a directory for `__inputs` declarations and generates
complete flake.nix content in one step.

### Example

```nix
imp.collectAndFormatFlake {
  src = ./outputs;
  coreInputs = { nixpkgs.url = "github:nixos/nixpkgs"; };
  description = "My flake";
}
# => "{ description = \"My flake\"; inputs = { ... }; ... }"
```

### Arguments

src
: Directory to scan for \_\_inputs declarations.

coreInputs
: Core flake inputs attrset (optional).

description
: Flake description string (optional).

outputsFile
: Path to outputs file (default: "./nix/flake").

header
: Header comment for generated file (optional).
