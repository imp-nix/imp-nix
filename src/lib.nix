/**
  Internal utilities for imp.
*/
rec {
  compose =
    g: f: x:
    g (f x);

  and =
    g: f: x:
    f x && g x;
  andNot = g: and (x: !(g x));

  matchesRegex = re: p: builtins.match re p != null;

  mapAttr =
    attrs: k: f:
    attrs // { ${k} = f attrs.${k}; };

  hasOutPath = and (x: x ? outPath) builtins.isAttrs;
  isRegistryNode = and (x: x ? __path) builtins.isAttrs;
  toPath = x: if isRegistryNode x then x.__path else x;
  isPathLike = x: builtins.isPath x || builtins.isString x || hasOutPath x || isRegistryNode x;
  isDirectory = and (x: builtins.readFileType (toPath x) == "directory") isPathLike;
  isimp = and (x: x ? __config.__functor) builtins.isAttrs;
  inModuleEval = and (x: x ? options) builtins.isAttrs;

  isCallable = x: builtins.isFunction x || (builtins.isAttrs x && x ? __functor);
  applyIfCallable = args: x: if isCallable x then x args else x;

  /**
    Safely extract a special attribute from a value.

    Catches evaluation errors with tryEval. Returns null on failure.
    Used by collectors to extract __outputs, __exports, __host, __inputs.
  */
  safeExtract =
    attrName: value:
    let
      hasIt = builtins.tryEval (
        builtins.isAttrs value && value ? ${attrName} && builtins.isAttrs value.${attrName}
      );
    in
    if hasIt.success && hasIt.value then
      let
        attr = value.${attrName};
        forced = builtins.tryEval (builtins.deepSeq (builtins.attrNames attr) attr);
      in
      if forced.success then forced.value else null
    else
      null;

  # Convenience aliases for common extractions
  extractOutputs = safeExtract "__outputs";
  extractExports = safeExtract "__exports";
  extractHost = safeExtract "__host";
  extractInputs = safeExtract "__inputs";

  /**
    Normalize a value/strategy wrapper to standard form.

    Handles both `{ value, strategy }` wrappers and plain values.
    Returns { value, strategy } where strategy may be null.
  */
  normalizeValueStrategy =
    entry:
    if builtins.isAttrs entry && entry ? value then
      {
        value = entry.value;
        strategy = entry.strategy or null;
      }
    else
      {
        value = entry;
        strategy = null;
      };

  /**
    Unwrap a { value, strategy } wrapper, optionally evaluating with args.

    If value is a function, calls it with the provided args.
    Returns the raw value (not a wrapper).
  */
  unwrapValue =
    args: v:
    let
      unwrapped = if builtins.isAttrs v && v ? value then v.value else v;
    in
    if builtins.isFunction unwrapped then unwrapped args else unwrapped;
}
