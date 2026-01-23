# Flake-level output - an overlay
{
  __outputs.overlays.myOverlay = final: prev: {
    myTool = prev.hello;
  };
}
