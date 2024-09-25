{
  lib,
  pyproject-nix,
  pkgs,
  lock1,
  workspace,
  renderers,
  ...
}:

let
  inherit (lib) mapAttrs findFirst importTOML;

  projectDirs = {
    workspace = ./fixtures/workspace;
    kitchenSinkA = ./fixtures/kitchen-sink/a;
    kitchenSinkCEditable = ./fixtures/kitchen-sink/c-editable;
    kitchenSinkB = ./fixtures/kitchen-sink/b;
    withExtra = ./fixtures/with-extra;
    trivial = ./fixtures/trivial;
    multiChoicePackage = ./fixtures/multi-choice-package;
    workspaceFlat = ./fixtures/workspace-flat;
    optionalDeps = ./fixtures/optional-deps;
    noDeps = ./fixtures/no-deps;
    withToolUvDevDeps = ./fixtures/with-tool-uv-devdeps;
    withResolverOptions = ./fixtures/with-resolver-options;
    withSupportedEnvironments = ./fixtures/with-supported-environments;
    multiPythons = ./fixtures/multi-pythons;
    no-build-no-binary-packages = ./fixtures/no-build-no-binary-packages;
    no-build = ./fixtures/no-build;
    no-binary = ./fixtures/no-binary;
    no-binary-no-build = ./fixtures/no-binary-no-build;
  };

  projects = mapAttrs (
    _: dir: pyproject-nix.lib.project.loadUVPyproject { projectRoot = dir; }
  ) projectDirs;

  findFirstPkg = name: findFirst (package: package.name == name) (throw "Not found: ${name}");

  locks = mapAttrs (_: dir: importTOML (dir + "/uv.lock")) projectDirs;

in
{

  mkRenderIntermediate =
    let

      # Return a callPackage'd package.
      mkPackageTest =
        {
          projectName,
          workspaceRoot ? projectDirs.${projectName},
          python ? pkgs.python312,
          sourcePreference,
        }:
        let
          renderIntermediate = renderers.mkRenderIntermediate {
            inherit workspaceRoot;
            config = workspace.loadConfig [ projects.${projectName}.pyproject ];
          };

        in
        depName:
        let
          package = lock1.parsePackage (findFirstPkg depName locks.${projectName}.package);
        in
        (renderIntermediate package) {
          inherit (pkgs)
            fetchurl
            stdenv
            autoPatchelfHook
            pythonManylinuxPackages
            ;
          inherit python sourcePreference;
        };

    in
    {
      testNoBinaryPackagesPrefWheel = {
        expr =
          let
            mkTest = mkPackageTest {
              projectName = "no-build-no-binary-packages";
              sourcePreference = "wheel";
            };
          in
          {
            arpeggio = baseNameOf (mkTest "arpeggio").src.url;
            urllib3 = baseNameOf (mkTest "urllib3").src.url;
          };

        expected = {
          arpeggio = "Arpeggio-2.0.2-py2.py3-none-any.whl";
          urllib3 = "urllib3-2.2.2.tar.gz";
        };
      };

      testNoBinaryPackagesPrefSdist = {
        expr =
          let
            mkTest = mkPackageTest {
              projectName = "no-build-no-binary-packages";
              sourcePreference = "sdist";
            };
          in
          {
            arpeggio = baseNameOf (mkTest "arpeggio").src.url;
            urllib3 = baseNameOf (mkTest "urllib3").src.url;
          };

        expected = {
          arpeggio = "Arpeggio-2.0.2-py2.py3-none-any.whl";
          urllib3 = "urllib3-2.2.2.tar.gz";
        };
      };

      testNoBuildPrefWheel = {
        expr =
          baseNameOf
            (
              (mkPackageTest {
                projectName = "no-build";
                sourcePreference = "wheel";
              })
              "arpeggio"
            ).src.url;
        expected = "Arpeggio-2.0.2-py2.py3-none-any.whl";
      };

      testNoBuildPrefSdist = {
        expr =
          baseNameOf
            (
              (mkPackageTest {
                projectName = "no-build";
                sourcePreference = "sdist";
              })
              "arpeggio"
            ).src.url;
        expected = "Arpeggio-2.0.2-py2.py3-none-any.whl";
      };

      testNoBinaryPrefWheel = {
        expr =
          baseNameOf
            (
              (mkPackageTest {
                projectName = "no-binary";
                sourcePreference = "wheel";
              })
              "arpeggio"
            ).src.url;
        expected = "Arpeggio-2.0.2.tar.gz";
      };

      testNoBinaryPrefSdist = {
        expr =
          baseNameOf
            (
              (mkPackageTest {
                projectName = "no-binary";
                sourcePreference = "sdist";
              })
              "arpeggio"
            ).src.url;
        expected = "Arpeggio-2.0.2.tar.gz";
      };

      testNoBuildNoBinaryPrefWheel = {
        expr =
          baseNameOf
            (
              (mkPackageTest {
                projectName = "no-binary-no-build";
                sourcePreference = "wheel";
              })
              "arpeggio"
            ).src.url;
        expectedError.type = "ThrownError";
        expectedError.msg = "Package source for 'arpeggio' was derived as sdist, in tool.uv.no-binary is set to true";
      };

      testNoBuildNoBinaryPrefSdist = {
        expr =
          baseNameOf
            (
              (mkPackageTest {
                projectName = "no-binary-no-build";
                sourcePreference = "wheel";
              })
              "arpeggio"
            ).src.url;
        expectedError.type = "ThrownError";
        expectedError.msg = "Package source for 'arpeggio' was derived as sdist, in tool.uv.no-binary is set to true";
      };
    };

}
