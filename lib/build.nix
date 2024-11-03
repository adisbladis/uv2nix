{ lib, pyproject-nix, ... }:

let
  inherit (pyproject-nix.build.lib) isBootstrapPackage;
  inherit (lib)
    mapAttrs
    listToAttrs
    nameValuePair
    ;

in

{

  /*
    Builder implementation using pyproject.nix build
    .
  */
  pyprojectBuild =
    let
      inherit (pyproject-nix.build.lib) renderers;
      mkSpec = dependencies: listToAttrs (map (dep: nameValuePair dep.name dep.extra) dependencies);

    in
    { defaultSourcePreference }:
    {
      # Build a local package
      local =
        { localProject, environ }:
        {
          stdenv,
          python,
          pyprojectHook,
          resolveBuildSystem,
          pythonPkgsBuildHost,
          # Editable root as a string
          editableRoot ? null,
        }:
        stdenv.mkDerivation (
          if editableRoot == null then
            renderers.mkDerivation
              {
                project = localProject;
                inherit environ;
              }
              {
                inherit pyprojectHook resolveBuildSystem;
              }
          else
            renderers.mkDerivationEditable
              {
                project = localProject;
                inherit environ;
                root = editableRoot;
              }
              {
                inherit
                  python
                  pyprojectHook
                  pythonPkgsBuildHost
                  resolveBuildSystem
                  ;

              }
        );

      # Build a remote (pypi/vcs) package
      remote =
        renderIntermediatePackage:
        {
          stdenv,
          python,
          fetchurl,
          autoPatchelfHook,
          pythonManylinuxPackages,
          pyprojectHook,
          pyprojectBootstrapHook,
          pyprojectWheelHook,
          unzip,
          sourcePreference ? defaultSourcePreference,
        }:
        let
          # Render common builder attributes
          attrs = renderIntermediatePackage {
            inherit
              stdenv
              python
              sourcePreference
              fetchurl
              autoPatchelfHook
              pythonManylinuxPackages
              ;
          };
          inherit (attrs.passthru) package format;

        in
        stdenv.mkDerivation (
          attrs
          // {
            passthru = {
              dependencies = mkSpec package.dependencies;
              optional-dependencies = mapAttrs (_: mkSpec) package.optional-dependencies;
              dependency-groups = mapAttrs (_: mkSpec) package.dev-dependencies;
              inherit format;
            };

            nativeBuildInputs =
              (attrs.nativeBuildInputs or [ ])
              ++ lib.optional (lib.hasSuffix ".zip" (attrs.src.passthru.url or "")) [ unzip ]
              ++ lib.optional (format == "pyproject") (
                if isBootstrapPackage attrs.pname then pyprojectBootstrapHook else pyprojectHook
              )
              ++ lib.optional (format == "wheel") pyprojectWheelHook;
          }
        );
    };

}
