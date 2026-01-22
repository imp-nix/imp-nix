# Base shell aliases
{ ... }: {
  shellAliases = {
    ll = "ls -l";
    la = "ls -la";
  };
  initExtra = ''
    # Base shell init
    export EDITOR=vim
  '';
}
