# Highlightjs updater expression
# This is used to build our custom highlight.js module
let
  flake = builtins.getFlake (builtins.toString ../../.);

  pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};

  src = pkgs.fetchFromGitHub {
    owner = "highlightjs";
    repo = "highlight.js";
    rev = "10.7.3";
    hash = "sha256-6IW8WFlWdb0txEQxYvrLcAxMx/F5qGpxwUbWpTloFaY=";
  };

  npmlock2nix = pkgs.callPackage (pkgs.fetchFromGitHub {
    owner = "nix-community";
    repo = "npmlock2nix";
    rev = "9197bbf397d76059a76310523d45df10d2e4ca81";
    sha256 = "sha256-sJM82Sj8yfQYs9axEmGZ9Evzdv/kDcI9sddqJ45frrU=";
  }) { };

in
npmlock2nix.v2.build {
  inherit src;
  inherit (pkgs) nodejs;
  nativeBuildInputs = [ pkgs.git ];
  installPhase = ''
    cp -r build $out
  '';
  buildCommands = [
    "git init"
    "git config user.email \"you@example.com\""
    "git config user.name \"Your Name\""
    "git add $(ls | grep -v node_modules | grep -v extra)"
    "git commit -m 'Dummy commit'"
    "node tools/build.js"
  ];
}
