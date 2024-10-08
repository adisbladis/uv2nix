{
  stdenv,
  lib,
  fetchurl,
  autoPatchelfHook,
}:

let
  srcs = lib.importJSON ./srcs.json;
  platform = stdenv.targetPlatform.config;

  sha256 = srcs.platforms.${platform} or (throw "Platform ${platform} not supported");

in

stdenv.mkDerivation (
  finalAttrs:
  let
    inherit (finalAttrs) version;
  in
  {
    pname = "uv-bin";
    inherit (srcs) version;

    src = fetchurl {
      url = "https://github.com/astral-sh/uv/releases/download/${version}/uv-${platform}.tar.gz";
      inherit sha256;
    };

    nativeBuildInputs = lib.optional stdenv.isLinux autoPatchelfHook;
    buildInputs = lib.optional stdenv.isLinux stdenv.cc.cc;

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      mkdir -p $out/bin
      mv uv* $out/bin
    '';

  }
)
