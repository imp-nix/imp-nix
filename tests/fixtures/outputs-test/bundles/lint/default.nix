# Lint bundle - contributes to multiple output types
{
  __outputs.perSystem.packages.lint = { pkgs, ... }:
    pkgs.writeShellScript "lint" "echo lint";

  __outputs.perSystem.devShells.default = {
    value = { pkgs, ... }: {
      nativeBuildInputs = [ pkgs.shellcheck ];
    };
    strategy = "merge";
  };
}
