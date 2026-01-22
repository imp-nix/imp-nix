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
}
