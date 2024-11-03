{
  workspace,
  pkgs,
  lib,
  pyproject-nix,
  ...
}:

let
  inherit (lib) nameValuePair listToAttrs;
  inherit (import ./testutil.nix { inherit lib; }) capitalise;

  # Test fixture workspaces
  workspaces = {
    trivial = ./fixtures/trivial;
    workspace = ./fixtures/workspace;
    workspaceFlat = ./fixtures/workspace-flat;
    no-build-no-binary-packages = ./fixtures/no-build-no-binary-packages;
    no-build = ./fixtures/no-build;
    no-binary = ./fixtures/no-binary;
    no-binary-no-build = ./fixtures/no-binary-no-build;
  };

in
{
  discoverWorkspace =
    let
      test = workspaceRoot: expected: {
        expr = workspace.discoverWorkspace { inherit workspaceRoot; };
        inherit expected;
      };
    in
    {
      testImplicitWorkspace = test workspaces.trivial [ "/" ];
      testWorkspace = test workspaces.workspace [
        "/packages/workspace-package"
        "/"
      ];
      testWorkspaceFlat = test workspaces.workspaceFlat [
        "/packages/pkg-a"
        "/packages/pkg-b"
      ];
      testWorkspaceExcluded = test ./fixtures/workspace-with-excluded [ "/packages/included-package" ];
    };

  loadConfig = lib.mapAttrs' (
    name': root:
    let
      name = "test${capitalise name'}";
      members = workspace.discoverWorkspace { workspaceRoot = root; };
      pyprojects = map (_m: lib.importTOML (root + "/pyproject.toml")) members;
      config = workspace.loadConfig pyprojects;
    in
    nameValuePair name {
      expr = config;
      expected = lib.importJSON ./expected/workspace.loadConfig.${name}.json;
    }
  ) workspaces;

  loadWorkspace.mkPyprojectOverlay =
    let
      mkTest =
        workspaceRoot:
        { packages }:
        let
          ws = workspace.loadWorkspace { inherit workspaceRoot; };

          overlay = ws.mkPyprojectOverlay { sourcePreference = "wheel"; };

          pythonSet =
            (pkgs.callPackage pyproject-nix.build.packages {
              python = pkgs.python312;
            }).overrideScope
              overlay;
        in
        listToAttrs (map (name: nameValuePair name pythonSet.${name}.version) packages);

    in
    {
      testTrivial = {
        expr = mkTest ./fixtures/trivial { packages = [ "arpeggio" ]; };
        expected = {
          arpeggio = "2.0.2";
        };
      };

      testKitchenSink = {
        expr = mkTest ./fixtures/kitchen-sink/a { packages = [ "pip" ]; };
        expected = {
          pip = "20.3.1";
        };
      };

      testWorkspace = {
        expr = mkTest ./fixtures/workspace {
          packages = [
            "arpeggio"
            "workspace-package"
          ];
        };
        expected = {
          arpeggio = "2.0.2";
          workspace-package = "0.1.0";
        };
      };

      testWorkspaceFlat = {
        expr = mkTest ./fixtures/workspace-flat {
          packages = [
            "pkg-a"
            "pkg-b"
          ];
        };
        expected = {
          pkg-a = "0.1.0";
          pkg-b = "0.1.0";
        };
      };
    };

}
