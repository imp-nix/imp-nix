{
  lib,
  imp,
}:
let
  it = imp;
  lit = it.withLib lib;
in
{
  leaves."test fails if no lib has been set" = {
    expr = it.leaves ./fixtures;
    expectedError.type = "ThrownError";
  };

  leaves."test succeeds when lib has been set" = {
    expr = (it.withLib lib).leaves ./fixtures/hello;
    expected = [ ];
  };

  leaves."test only returns nix non-ignored files" = {
    expr = lit.leaves ./fixtures/a;
    expected = [
      ./fixtures/a/a_b.nix
      ./fixtures/a/b/b_a.nix
      ./fixtures/a/b/m.nix
    ];
  };

  leaves."test loads from hidden directory but excludes sub-hidden" = {
    expr = lit.leaves ./fixtures/a/b/_c;
    expected = [ ./fixtures/a/b/_c/d/e.nix ];
  };

  filter."test returns empty if no nix files with true predicate" = {
    expr = (lit.filter (_: false)).leaves ./fixtures;
    expected = [ ];
  };

  filter."test only returns nix files with true predicate" = {
    expr = (lit.filter (lib.hasSuffix "m.nix")).leaves ./fixtures;
    expected = [ ./fixtures/a/b/m.nix ];
  };

  filter."test multiple `filter`s compose" = {
    expr = ((lit.filter (lib.hasInfix "b/")).filter (lib.hasInfix "_")).leaves ./fixtures;
    expected = [ ./fixtures/a/b/b_a.nix ];
  };

  match."test returns empty if no files match regex" = {
    expr = (lit.match "badregex").leaves ./fixtures;
    expected = [ ];
  };

  match."test returns files matching regex" = {
    expr = (lit.match ".*/[^/]+_[^/]+\.nix").leaves ./fixtures;
    expected = [
      ./fixtures/a/a_b.nix
      ./fixtures/a/b/b_a.nix
    ];
  };

  matchNot."test returns files not matching regex" = {
    expr = (lit.matchNot ".*/[^/]+_[^/]+\.nix").leaves ./fixtures/a/b;
    expected = [
      ./fixtures/a/b/m.nix
    ];
  };

  match."test `match` composes with `filter`" = {
    expr = ((lit.match ".*a_b.nix").filter (lib.hasInfix "/a/")).leaves ./fixtures;
    expected = [ ./fixtures/a/a_b.nix ];
  };

  match."test multiple `match`s compose" = {
    expr = ((lit.match ".*/[^/]+_[^/]+\.nix").match ".*b\.nix").leaves ./fixtures;
    expected = [ ./fixtures/a/a_b.nix ];
  };

  map."test transforms each matching file with function" = {
    expr = (lit.map import).leaves ./fixtures/x;
    expected = [ "z" ];
  };

  map."test `map` composes with `filter`" = {
    expr = ((lit.filter (lib.hasInfix "/x")).map import).leaves ./fixtures;
    expected = [ "z" ];
  };

  map."test multiple `map`s compose" = {
    expr = ((lit.map import).map builtins.stringLength).leaves ./fixtures/x;
    expected = [ 1 ];
  };

  addRoot."test `addRoot` prepends a path to filter" = {
    expr = (lit.addRoot ./fixtures/x).files;
    expected = [ ./fixtures/x/y.nix ];
  };

  addRoot."test `addRoot` can be called multiple times" = {
    expr = ((lit.addRoot ./fixtures/x).addRoot ./fixtures/a/b).files;
    expected = [
      ./fixtures/x/y.nix
      ./fixtures/a/b/b_a.nix
      ./fixtures/a/b/m.nix
    ];
  };

  addRoot."test `addRoot` identity" = {
    expr = ((lit.addRoot ./fixtures/x).addRoot ./fixtures/a/b).files;
    expected = lit.leaves [
      ./fixtures/x
      ./fixtures/a/b
    ];
  };

  new."test `new` returns a clear state" = {
    expr = lib.pipe lit [
      (i: i.addRoot ./fixtures/x)
      (i: i.addRoot ./fixtures/a/b)
      (i: i.new)
      (i: i.addRoot ./fixtures/modules/hello-world)
      (i: i.withLib lib)
      (i: i.files)
    ];
    expected = [ ./fixtures/modules/hello-world/mod.nix ];
  };

  initFilter."test can change the initial filter to look for other file types" = {
    expr = (lit.initFilter (p: lib.hasSuffix ".txt" p)).leaves [ ./fixtures/a ];
    expected = [ ./fixtures/a/a.txt ];
  };

  initFilter."test initf does filter non-paths" = {
    expr =
      let
        mod = (it.initFilter (x: !(x ? config.boom))) [
          {
            options.hello = lib.mkOption {
              default = "world";
              type = lib.types.str;
            };
          }
          {
            config.boom = "boom";
          }
        ];
        res = lib.modules.evalModules { modules = [ mod ]; };
      in
      res.config.hello;
    expected = "world";
  };

  addAPI."test extends the API available on an imp object" = {
    expr =
      let
        extended = lit.addAPI { helloOption = self: self.addRoot ./fixtures/modules/hello-option; };
      in
      extended.helloOption.files;
    expected = [ ./fixtures/modules/hello-option/mod.nix ];
  };

  addAPI."test preserves previous API extensions on an imp object" = {
    expr =
      let
        first = lit.addAPI { helloOption = self: self.addRoot ./fixtures/modules/hello-option; };
        second = first.addAPI { helloWorld = self: self.addRoot ./fixtures/modules/hello-world; };
        extended = second.addAPI { res = self: self.helloOption.files; };
      in
      extended.res;
    expected = [ ./fixtures/modules/hello-option/mod.nix ];
  };

  addAPI."test API extensions are late bound" = {
    expr =
      let
        first = lit.addAPI { res = self: self.late; };
        extended = first.addAPI { late = _self: "hello"; };
      in
      extended.res;
    expected = "hello";
  };

  pipeTo."test pipes list into a function" = {
    expr = (lit.map lib.pathType).pipeTo (lib.length) ./fixtures/x;
    expected = 1;
  };
}
