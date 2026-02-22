{
  lib,
  imp,
}:
let
  discoverSrc = import ../src/flake/discover-src.nix { inherit lib; };
  root = ./fixtures/flake/src-discover/workspaces;
  root2 = ./fixtures/flake/src-discover/more-workspaces;
in
{
  srcDiscover."test discovers default suffix roots from immediate children" = {
    expr = discoverSrc [ { inherit root; } ];
    expected = [
      (root + "/alpha/nix/outputs")
      (root + "/zeta/nix/outputs")
    ];
  };

  srcDiscover."test hidden children are skipped by default" = {
    expr =
      let
        discovered = discoverSrc [ { inherit root; } ];
      in
      lib.any (path: lib.hasInfix "/_hidden/" (toString path)) discovered;
    expected = false;
  };

  srcDiscover."test hidden children can be included" = {
    expr = discoverSrc [
      {
        inherit root;
        includeHidden = true;
      }
    ];
    expected = [
      (root + "/_hidden/nix/outputs")
      (root + "/alpha/nix/outputs")
      (root + "/zeta/nix/outputs")
    ];
  };

  srcDiscover."test custom suffix is supported" = {
    expr = discoverSrc [
      {
        root = root2;
        suffix = "custom/outputs";
      }
    ];
    expected = [ (root2 + "/omega/custom/outputs") ];
  };

  srcDiscover."test discovery preserves spec order" = {
    expr = discoverSrc [
      {
        root = root2;
        suffix = "custom/outputs";
      }
      { inherit root; }
    ];
    expected = [
      (root2 + "/omega/custom/outputs")
      (root + "/alpha/nix/outputs")
      (root + "/zeta/nix/outputs")
    ];
  };

  srcDiscover."test missing root is ignored" = {
    expr = discoverSrc [
      {
        root = root + "/missing";
      }
    ];
    expected = [ ];
  };

  srcDiscover."test non-directory root throws" = {
    expr = discoverSrc [
      {
        root = root + "/alpha/nix/outputs/perSystem/packages.nix";
      }
    ];
    expectedError.type = "ThrownError";
    expectedError.msg = ".*must be a directory.*";
  };
}
