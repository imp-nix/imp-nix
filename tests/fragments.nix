{
  lib,
  imp,
}:
let
  fragmentsLib = import ../src/tree/fragments.nix { inherit lib; };
in
{
  fragments."test asString concatenates shell scripts" = {
    expr = (fragmentsLib.collectFragments ./fixtures/collect/fragments/strings.d).asString;
    expected = "echo \"first\"\n\necho \"second\"\n";
  };

  fragments."test asList flattens list fragments" = {
    expr = (fragmentsLib.collectFragments ./fixtures/collect/fragments/lists.d).asList;
    expected = [
      "git"
      "vim"
      "htop"
      "tmux"
    ];
  };

  fragments."test asAttrs merges attrset fragments" = {
    expr = (fragmentsLib.collectFragments ./fixtures/collect/fragments/attrs.d).asAttrs;
    expected = {
      FOO = "bar";
      BAZ = "qux";
    };
  };

  fragments."test asString throws on mixed types" = {
    expr = (fragmentsLib.collectFragments ./fixtures/collect/fragments/mixed.d).asString;
    expectedError.type = "ThrownError";
    expectedError.msg = ".*asString requires all fragments to be strings.*";
  };

  fragments."test asList throws on non-list types" = {
    expr = (fragmentsLib.collectFragments ./fixtures/collect/fragments/attrs.d).asList;
    expectedError.type = "ThrownError";
    expectedError.msg = ".*asList requires all fragments to be lists.*";
  };

  fragments."test asAttrs throws on non-attr types" = {
    expr = (fragmentsLib.collectFragments ./fixtures/collect/fragments/strings.d).asAttrs;
    expectedError.type = "ThrownError";
    expectedError.msg = ".*asAttrs requires all fragments to be attrsets.*";
  };

  fragments."test list returns raw fragments regardless of type" = {
    expr = builtins.length (fragmentsLib.collectFragments ./fixtures/collect/fragments/mixed.d).list;
    expected = 2;
  };
}
