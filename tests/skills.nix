{
  lib,
  imp,
}:
let
  collectSkills = import ../src/collect-skills.nix;
in
{
  # collectSkills receives parent directories containing bundles, not individual bundles
  skills."test collectSkills returns skill paths from bundles parent dir" = {
    expr =
      let
        result = collectSkills [ ./fixtures/skills-test ];
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
        result = collectSkills [ ./fixtures/skills-test ];
      in
      # Should not include anything from bundle-no-skills
      !(result ? "nonexistent-skill");
    expected = true;
  };

  skills."test collectSkills returns correct paths" = {
    expr =
      let
        result = collectSkills [ ./fixtures/skills-test ];
        testSkillPath = result.test-skill;
      in
      lib.hasSuffix "test-skill" (toString testSkillPath);
    expected = true;
  };

  skills."test collectSkills is available on imp object" = {
    expr = imp ? collectSkills;
    expected = true;
  };

  skills."test collectSkills handles empty bundles directory" = {
    expr = collectSkills [ ./fixtures/hello ];
    expected = { };
  };
}
