{
  workspace,
  pkgs,
  lib,
  ...
}:

let
  inherit (lib) nameValuePair listToAttrs;
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
      testImplicitWorkspace = test ./fixtures/trivial [ "/" ];
      testWorkspace = test ./fixtures/workspace [
        "/packages/workspace-package"
        "/"
      ];
      testWorkspaceFlat = test ./fixtures/workspace-flat [
        "/packages/pkg-a"
        "/packages/pkg-b"
      ];
      testWorkspaceExcluded = test ./fixtures/workspace-with-excluded [ "/packages/included-package" ];
    };

  loadWorkspace.mkOverlay =
    let
      mkTest =
        workspaceRoot:
        { packages }:
        let
          ws = workspace.loadWorkspace { inherit workspaceRoot; };

          overlay = ws.mkOverlay { };

          python = pkgs.python312.override {
            self = python;
            packageOverrides = overlay;
          };

        in
        listToAttrs (map (name: nameValuePair name python.pkgs.${name}.version) packages);

    in
    {
      testTrivial = {
        expr = mkTest ./fixtures/trivial { packages = [ "arpeggio" ]; };
        expected = {
          arpeggio = "2.0.2";
        };
      };

      testWorkspace = {
        expr = mkTest ./fixtures/workspace { packages = [ "arpeggio" ]; };
        expected = {
          arpeggio = "2.0.2";
        };
      };

      testWorkspaceFlat = {
        expr = mkTest ./fixtures/workspace-flat { packages = [ "arpeggio" ]; };
        expected = {
          arpeggio = "2.0.2";
        };
      };
    };

}
