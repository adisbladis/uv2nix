_: {
  # Used to find the project root
  projectRootFile = "flake.lock";

  # Nix
  programs.deadnix.enable = true;
  programs.statix.enable = true;
  programs.nixfmt.enable = true;
}
