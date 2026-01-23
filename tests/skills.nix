{
  lib,
  imp,
}:
let
  collectSkills = import ../src/bundles/collect-skills.nix;
in
{
  # collectSkills receives parent directories containing bundles, not individual bundles
  skills."test collectSkills returns skill paths from bundles parent dir" = {
    expr =
      let
        result = collectSkills [ ./fixtures/bundles/skills ];
      in
      builtins.attrNames result;
    expected = [
      "another-skill"
      "test-skill"
      "third-skill"
    ];
  };

  skills."test collectSkills ignores bundles without skills directory" = {
    expr =
      let
        # bundle-no-skills has no skills/ subdirectory
        result = collectSkills [ ./fixtures/bundles/skills ];
      in
      # Should not include anything from bundle-no-skills
      !(result ? "nonexistent-skill");
    expected = true;
  };

  skills."test collectSkills returns correct paths" = {
    expr =
      let
        result = collectSkills [ ./fixtures/bundles/skills ];
        testSkillPath = result.test-skill;
      in
      lib.hasSuffix "test-skill" (toString testSkillPath);
    expected = true;
  };

  skills."test collectSkills is available on imp.bundles" = {
    expr = imp.bundles ? collectSkills;
    expected = true;
  };

  skills."test collectSkills handles empty bundles directory" = {
    expr = collectSkills [ ./fixtures/hello ];
    expected = { };
  };
}
