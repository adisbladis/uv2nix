{ workspace, ... }:

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

}
