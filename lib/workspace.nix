{
  lib,
  pyproject-nix,
  lock1,
  ...
}:

let
  inherit (lib)
    importTOML
    splitString
    length
    elemAt
    filter
    attrsToList
    match
    replaceStrings
    concatMap
    optional
    any
    fix
    groupBy
    mapAttrs
    optionalAttrs
    head
    attrNames
    all
    unique
    foldl'
    isPath
    isAttrs
    attrValues
    assertMsg
    nameValuePair
    ;
  inherit (builtins) readDir;
  inherit (pyproject-nix.lib.project) loadUVPyproject; # Note: Maybe we want a loader that will just "remap-all-the-things" into standard attributes?
  inherit (pyproject-nix.lib) pep440 pep508;
  inherit (pyproject-nix.lib) pypa;

  # Match str against a glob pattern
  globMatches =
    let
      mkRe = replaceStrings [ "*" ] [ ".*" ]; # Make regex from glob pattern
    in
    glob:
    let
      re = mkRe glob;
    in
    s: match re s != null;

  splitPath = splitString "/";

in

fix (self: {
  /*
    Load a workspace from a workspace root.

    Returns an attribute set where you can call:
    mkOverlay { sourcePreference = "wheel"; } # wheel or sdist

    to create a Nixpkgs Python packageOverrides overlay
  */
  loadWorkspace =
    {
      # Workspace root as a path
      workspaceRoot,
      # Config overrides for settings automatically inferred by loadConfig
      config ? { },
    }:
    assert isPath workspaceRoot;
    assert isAttrs config;
    let
      pyproject = importTOML (workspaceRoot + "/pyproject.toml");
      uvLock = lock1.parseLock (importTOML (workspaceRoot + "/uv.lock"));

      members = self.discoverWorkspace { inherit workspaceRoot pyproject; };

      # Map package names to pyproject.nix projects
      workspaceProjects =
        mapAttrs
          (
            _: project:
            assert length project == 1;
            head project
          )
          (
            groupBy (project: pypa.normalizePackageName project.pyproject.project.name) (
              map (
                relPath:
                loadUVPyproject { projectRoot = workspaceRoot + "${relPath}"; }
                # We've already loaded this file for workspace discovery, just bung it in.
                // optionalAttrs (relPath == "/") { inherit pyproject; }
              ) members
            )
          );

      # Bootstrap resolver from top-level workspace projects
      topLevelDependencies = map pep508.parseString (attrNames workspaceProjects);

      config' =
        # Load supported tool.uv settings
        (self.loadConfig (
          # Extract pyproject.toml from loaded projects
          (map (project: project.pyproject) (attrValues workspaceProjects))
          # If workspace root is a virtual root it wasn't discovered as a member directory
          # but config should also be loaded from a virtual root
          ++ optional (!(pyproject ? project)) pyproject
        ))
        //
          # Merge with overriden config
          config;

    in
    assert assertMsg (
      !(config'.no-binary && config'.no-build)
    ) "Both tool.uv.no-build and tool.uv.no-binary are set to true, making the workspace unbuildable";
    {
      /*
        Workspace config as loaded by loadConfig
        .
      */
      config = config';

      /*
        Generate a Nixpkgs Python overlay from uv workspace.

        See https://nixos.org/manual/nixpkgs/stable/#overriding-python-packages
      */
      mkOverlay =
        {
          # Whether to prefer sources from either:
          # - wheel
          # - sdist
          #
          # See FAQ for more information.
          sourcePreference ?
            if config'.no-binary then
              "sdist"
            else if config'.no-build then
              "wheel"
            else
              throw "No sourcePreference was passed, and could not be automatically inferred from workspace config",
          # PEP-508 environment customisations.
          # Example: { platform_release = "5.10.65"; }
          environ ? { },
        }:
        final: prev:
        let
          inherit (final) callPackage;

          # Note: Using Python from final here causes infinite recursion.
          # There is no correct way to override the python interpreter from within the set anyway,
          # so all facts that we get from the interpreter derivation are still the same.
          environ' = pep508.setEnviron (pep508.mkEnviron prev.python) environ;
          pythonVersion = environ'.python_full_version.value;

          mkPackage = lock1.mkPackage {
            projects = workspaceProjects;
            environ = environ';
            config = config';
            inherit workspaceRoot sourcePreference pyproject;
          };

          resolved = lock1.resolveDependencies {
            # Note: Attrset in the shape of pep621.parseDependencies
            dependencies = {
              dependencies = topLevelDependencies;
              extras = { };
              build-systems = [ ];
            };
            lock = uvLock;
            environ = environ';
          };

        in
        # Assert that requires-python from uv.lock is compatible with this interpreter
        assert all (spec: pep440.comparators.${spec.op} pythonVersion spec.version) uvLock.requires-python;
        mapAttrs (_: pkg: callPackage (mkPackage pkg) { }) resolved;

      /*
        Generate a Nixpkgs Python overlay installing workspace packages in editable mode
        .
      */
      mkEditableOverlay =
        let
          workspaceProjects' = attrNames workspaceProjects;
          localProjects = map (package: package.name) (filter lock1.isLocalPackage uvLock.package);
          allLocal = unique (workspaceProjects' ++ localProjects);
        in
        {
          # Editable root as a string.
          root ? (toString workspaceRoot),
          # Workspace members to make editable as a list of strings. Defaults to all local projects.
          members ? allLocal,
        }:
        assert assertMsg (!lib.hasPrefix builtins.storeDir root) ''
          Editable root was passed as a Nix store path.
          ${
            lib.optionalString (toString workspaceRoot) == root
            && lib.inPureEvalMode ''
              This is most likely because you are using Flakes, and are automatically inferring the editable root from workspaceRoot.
              Flakes are copied to the Nix store on evaluation. This can temporarily be worked around using --impure.
            ''
          }

          Pass editable root either as a string pointing to an absolute path non-store path, or use environment variables for relative paths.
        '';
        _final: prev:
        let
          # Filter any local packages that might be deactivated by markers or other filtration mechanisms.
          activeMembers = filter (name: !prev ? name) members;
        in
        lib.listToAttrs (
          map (name: nameValuePair name (prev.${name}.override { editableRoot = root; })) activeMembers
        );

      inherit topLevelDependencies;
    };

  /*
    Load supported configuration from workspace

    Supports:
    - tool.uv.no-binary
    - tool.uv.no-build
    - tool.uv.no-binary-packages
    - tool.uv.no-build-packages
  */
  loadConfig =
    # List of imported (lib.importTOML) pyproject.toml files from workspace from which to load config
    pyprojects:
    let
      no-build' = foldl' (
        acc: pyproject:
        (
          if pyproject ? tool.uv.no-build then
            (
              if acc != null && pyproject.tool.uv.no-build != acc then
                (throw "Got conflicting values for tool.uv.no-build")
              else
                pyproject.tool.uv.no-build
            )
          else
            acc
        )
      ) null pyprojects;

      no-binary' = foldl' (
        acc: pyproject:
        (
          if pyproject ? tool.uv.no-binary then
            (
              if acc != null && pyproject.tool.uv.no-binary != acc then
                (throw "Got conflicting values for tool.uv.no-binary")
              else
                pyproject.tool.uv.no-binary
            )
          else
            acc
        )
      ) null pyprojects;
    in
    {
      no-build = if no-build' != null then no-build' else false;
      no-binary = if no-binary' != null then no-binary' else false;
      no-binary-package = unique (
        concatMap (pyproject: pyproject.tool.uv.no-binary-package or [ ]) pyprojects
      );
      no-build-package = unique (
        concatMap (pyproject: pyproject.tool.uv.no-build-package or [ ]) pyprojects
      );
    };

  /*
    Discover workspace member directories from a workspace root.
    Returns a list of strings relative to the workspace root.
  */
  discoverWorkspace =
    {
      # Workspace root directory
      workspaceRoot,
      # Workspace top-level pyproject.toml
      pyproject ? importTOML (workspaceRoot + "/pyproject.toml"),
    }:
    let
      workspace' = pyproject.tool.uv.workspace or { };
      excluded = map (g: globMatches "/${g}") (workspace'.exclude or [ ]);
      globs = map splitPath (workspace'.members or [ ]);

    in
    # Get a list of workspace member directories
    filter (x: length excluded == 0 || any (e: !e x) excluded) (
      concatMap (
        glob:
        let
          max = (length glob) - 1;
          recurse =
            rel: i:
            let
              dir = workspaceRoot + "/${rel}";
              dirs = map (e: e.name) (filter (e: e.value == "directory") (attrsToList (readDir dir)));
              matches = filter (globMatches (elemAt glob i)) dirs;
            in
            if i == max then
              map (child: rel + "/${child}") matches
            else
              concatMap (child: recurse (rel + "/${child}") (i + 1)) matches;
        in
        recurse "" 0
      ) globs
    )
    # If the package is a virtual root we don't add the workspace root to project discovery
    ++ optional (pyproject ? project) "/";

})
