# Config as function - receives args like pkgs
{ pkgs, ... }:
{
  shell = pkgs.bash;
  greeting = "hello from func config";
}
