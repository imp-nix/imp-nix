# Extended shell aliases - adds more
{ ... }: {
  shellAliases = {
    g = "git";
    ga = "git add";
  };
  initExtra = ''
    # Dev shell init
    export VISUAL=nvim
  '';
}
