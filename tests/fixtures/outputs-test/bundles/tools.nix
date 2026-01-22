# Tools bundle - contributes packages and merges into devShell
{
  __outputs.perSystem.packages.tools = { pkgs, ... }:
    pkgs.writeShellScript "tools" "echo tools";

  __outputs.perSystem.devShells.default = {
    value = { pkgs, ... }: {
      nativeBuildInputs = [ pkgs.jq ];
    };
    strategy = "merge";
  };
}
