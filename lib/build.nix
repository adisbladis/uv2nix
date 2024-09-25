{ lib, pyproject-nix, ... }:

let
  inherit (pyproject-nix.build.lib) isBootstrapPackage;
  inherit (lib)
    optionalAttrs
    concatMap
    mapAttrs
    listToAttrs
    nameValuePair
    ;

in

{

  # Builder implementation using nixpkgs buildPythonPackage
  buildPythonPackage =
    { defaultSourcePreference }:
    {
      # Build a local package
      local =
        { localProject, environ }:
        { buildPythonPackage, python }:
        buildPythonPackage (localProject.renderers.buildPythonPackage { inherit python environ; });

      # Build a remote (pypi/vcs) package
      remote =
        renderIntermediatePackage:
        {
          stdenv,
          python,
          fetchurl,
          autoPatchelfHook,
          pythonManylinuxPackages,
          pythonPackages,
          buildPythonPackage,
          wheelUnpackHook,
          pypaInstallHook,
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

          getDependencies = concatMap (
            dep:
            let
              pkg = pythonPackages.${dep.name};
            in
            [ pkg ] ++ concatMap (extra: pkg.optional-dependencies.${extra}) dep.extra
          );

        in
        buildPythonPackage (
          attrs
          // {
            dependencies = getDependencies package.dependencies;
            optional-dependencies = mapAttrs (_: getDependencies) package.optional-dependencies;
            passthru = {
              inherit format;
            };
          }
          // optionalAttrs (format == "pyproject") { pyproject = true; }
          // optionalAttrs (format != "pyproject") { inherit (attrs) format; }
          // optionalAttrs (format == "wheel") {
            nativeBuildInputs = attrs.nativeBuildInputs ++ [
              wheelUnpackHook
              pypaInstallHook
            ];
          }
        );
    };

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
              inherit format;
            };

            nativeBuildInputs =
              (attrs.nativeBuildInputs or [ ])
              ++ lib.optional (format == "pyproject") (
                if isBootstrapPackage attrs.pname then pyprojectBootstrapHook else pyprojectHook
              )
              ++ lib.optional (format == "wheel") pyprojectWheelHook;
          }
        );
    };

}
