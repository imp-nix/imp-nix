/**
  Anchor ID: IMP_ANCHOR_FLAKE_FORMAT
  Formats flake inputs and generates flake.nix content.
  Standalone implementation - no nixpkgs dependency, only builtins.

  # Example

  ```nix
  formatInputs { treefmt-nix = { url = "..."; }; }
  # => "treefmt-nix = {\n  url = \"...\";\n};\n"

  formatFlake {
    description = "My flake";
    coreInputs = { nixpkgs.url = "..."; };
    collectedInputs = { treefmt-nix.url = "..."; };
    outputsFile = "./nix/flake";
  }
  # => full flake.nix content as string
  ```
*/
let
  # Escape a string for Nix source code
  escapeString =
    s:
    builtins.replaceStrings
      [
        "\\"
        "\""
        "\n"
        "\t"
      ]
      [
        "\\\\"
        "\\\""
        "\\n"
        "\\t"
      ]
      s;

  # Quote a string for Nix source code
  quote = s: ''"${escapeString s}"'';

  # Check if a string is a valid Nix identifier
  isValidIdent = s: builtins.match "[a-zA-Z_][a-zA-Z0-9_'-]*" s != null;

  # Format an attribute name (quote if necessary)
  formatAttrName = name: if isValidIdent name then name else quote name;

  /**
    Format a value as Nix source code.

    # Arguments

    depth
    : Indentation depth level.

    value
    : Value to format (string, bool, int, null, list, or attrset).
  */
  formatValue =
    depth: value:
    let
      spaces = builtins.concatStringsSep "" (builtins.genList (_: "  ") depth);
      innerSpaces = builtins.concatStringsSep "" (builtins.genList (_: "  ") (depth + 1));
    in
    if builtins.isString value then
      quote value
    else if builtins.isBool value then
      if value then "true" else "false"
    else if builtins.isInt value then
      toString value
    else if builtins.isNull value then
      "null"
    else if builtins.isList value then
      let
        items = map (formatValue (depth + 1)) value;
      in
      if value == [ ] then
        "[ ]"
      else
        "[\n${innerSpaces}${builtins.concatStringsSep "\n${innerSpaces}" items}\n${spaces}]"
    else if builtins.isAttrs value then
      let
        names = builtins.attrNames value;
        formatAttr = name: "${formatAttrName name} = ${formatValue (depth + 1) value.${name}};";
        attrs = map formatAttr names;
      in
      if names == [ ] then
        "{ }"
      else
        "{\n${innerSpaces}${builtins.concatStringsSep "\n${innerSpaces}" attrs}\n${spaces}}"
    else
      throw "formatValue: unsupported type: ${builtins.typeOf value}";

  # Check if an input override is just `{ follows = "..."; }`
  isFollowsOnly = v: builtins.isAttrs v && builtins.attrNames v == [ "follows" ];

  # Format input overrides (the `inputs` attr of a flake input)
  # Uses shorthand: `inputs.nixpkgs.follows = "nixpkgs";`
  formatInputOverrides =
    depth: name: overrides:
    let
      overrideNames = builtins.sort builtins.lessThan (builtins.attrNames overrides);
      formatOverride =
        oName:
        let
          v = overrides.${oName};
        in
        if isFollowsOnly v then
          "${formatAttrName name}.inputs.${formatAttrName oName}.follows = ${quote v.follows};"
        else
          "${formatAttrName name}.inputs.${formatAttrName oName} = ${formatValue depth v};";
    in
    map formatOverride overrideNames;

  /**
    Format a single input definition at a given depth.

    # Arguments

    depth
    : Indentation depth level.

    name
    : Input name.

    def
    : Input definition attrset.
  */
  formatInputAt =
    depth: name: def:
    let
      names = builtins.attrNames def;
      hasUrl = def ? url;
      hasInputs = def ? inputs && builtins.isAttrs def.inputs;
      otherAttrs = builtins.removeAttrs def [
        "url"
        "inputs"
      ];
      hasOther = otherAttrs != { };

      # Simple case: just `{ url = "..."; }`
      isSimple = names == [ "url" ];

      # Can use shorthand: url + optional inputs with follows
      canUseShorthand = hasUrl && !hasOther;

      indent = builtins.concatStringsSep "" (builtins.genList (_: "  ") depth);

      # Build shorthand lines
      urlLine = "${formatAttrName name}.url = ${quote def.url};";
      inputLines = if hasInputs then formatInputOverrides depth name def.inputs else [ ];
      shorthandLines = [ urlLine ] ++ inputLines;

      # Longform fallback
      formatted = formatValue depth def;
      longform = "${formatAttrName name} = ${formatted};";
    in
    if isSimple then
      urlLine
    else if canUseShorthand then
      builtins.concatStringsSep "\n${indent}" shorthandLines
    else
      longform;

  /**
    Format a single input definition (at depth 1).

    # Arguments

    name
    : Input name.

    def
    : Input definition attrset.
  */
  formatInput = formatInputAt 1;

  # Format multiple inputs as a block at a given depth
  formatInputsAt =
    depth: inputs:
    let
      names = builtins.sort builtins.lessThan (builtins.attrNames inputs);
      indent = builtins.concatStringsSep "" (builtins.genList (_: "  ") depth);
      lines = map (name: formatInputAt depth name inputs.${name}) names;
    in
    builtins.concatStringsSep "\n${indent}" lines;

  /**
    Format multiple inputs as a block.

    # Example

    ```nix
    formatInputs { treefmt-nix = { url = "github:numtide/treefmt-nix"; }; }
    # => "treefmt-nix.url = \"github:numtide/treefmt-nix\";"
    ```

    # Arguments

    inputs
    : Attrset of input definitions.
  */
  formatInputs =
    inputs:
    let
      names = builtins.sort builtins.lessThan (builtins.attrNames inputs);
      lines = map (name: formatInputAt 1 name inputs.${name}) names;
    in
    builtins.concatStringsSep "\n    " lines;

  /**
    Generate complete flake.nix content.

    # Example

    ```nix
    formatFlake {
      description = "My flake";
      coreInputs = { nixpkgs.url = "github:nixos/nixpkgs"; };
      collectedInputs = { treefmt-nix.url = "github:numtide/treefmt-nix"; };
    }
    ```

    # Arguments

    description
    : Flake description string (optional).

    coreInputs
    : Core flake inputs attrset (optional).

    collectedInputs
    : Collected inputs from __inputs declarations (optional).

    outputsFile
    : Path to outputs file (default: "./nix/flake").

    header
    : Header comment for generated file (optional).
  */
  formatFlake =
    {
      description ? "",
      coreInputs ? { },
      collectedInputs ? { },
      outputsFile ? "./nix/flake",
      header ? "/**\n  Auto-generated by imp - DO NOT EDIT\n  Regenerate with: nix run .#imp-flake\n*/",
      submodules ? true,
    }:
    let
      hasDescription = description != "";
      descLine = if hasDescription then "description = ${quote description};" else "";

      # Format core inputs section
      coreNames = builtins.attrNames coreInputs;
      hasCoreInputs = coreNames != [ ];

      # Format collected inputs section
      collectedNames = builtins.attrNames collectedInputs;
      hasCollectedInputs = collectedNames != [ ];

      # Build inputs block with sections
      submodulesSection = if submodules then "    self.submodules = true;" else "";

      coreSection = if hasCoreInputs then "    # Core inputs\n    ${formatInputsAt 2 coreInputs}" else "";

      collectedSection =
        if hasCollectedInputs then
          "    # Collected from __inputs\n    ${formatInputsAt 2 collectedInputs}"
        else
          "";

      inputsSections = builtins.filter (x: x != "") [
        submodulesSection
        coreSection
        collectedSection
      ];

      inputsBlock =
        if inputsSections == [ ] then
          "  inputs = { };"
        else
          "  inputs = {\n${builtins.concatStringsSep "\n\n" inputsSections}\n  };";
    in
    builtins.concatStringsSep "\n" (
      builtins.filter (x: x != "") [
        header
        "{"
        (if hasDescription then "  ${descLine}" else "")
        ""
        inputsBlock
        ""
        "  outputs = inputs: import ${outputsFile} inputs;"
        "}"
      ]
    )
    + "\n";

in
{
  inherit
    formatValue
    formatInput
    formatInputs
    formatFlake
    ;
}
