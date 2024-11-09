{ pkgs, lib }:

let
  inherit (lib) getExe;

  projectRootFile = "flake.lock";

  toml = pkgs.formats.toml { };

  treefmt = {
    formatter =
      lib.mapAttrs
        (_name: fmt: {
          inherit (fmt) command;
          excludes = fmt.excludes or [ ];
          includes = fmt.includes or [ ];
          options = fmt.options or [ ];
        })
        {

          deadnix = {
            command = getExe pkgs.deadnix;
            includes = [ "*.nix" ];
            options = [ "--edit" ];
          };

          nixfmt = {
            command = getExe pkgs.nixfmt-rfc-style;
            includes = [ "*.nix" ];
          };

          ruff-check = {
            command = getExe pkgs.ruff;
            includes = [
              "*.py"
              "*.pyi"
            ];
            options = [
              "check"
              "--fix"
            ];
          };

          ruff-format = {
            command = getExe pkgs.ruff;
            includes = [
              "*.py"
              "*.pyi"
            ];
            options = [ "format" ];
          };

          shfmt = {
            command = getExe pkgs.shfmt;
            includes = [
              "*.sh"
              "*.bash"
              "*.envrc"
              "*.envrc.*"
            ];
            options = [
              "-i"
              "2"
              "-s"
              "-w"
            ];
          };

          statix = {
            command =
              let
                configFile = (pkgs.formats.toml { }).generate "statix.toml" { disabled = [ ]; };

                # statix requires its configuration file to be named statix.toml exactly
                # See: https://github.com/nerdypepper/statix/pull/54
                configDir = pkgs.runCommandLocal "statix-config" { } ''
                  mkdir "$out"
                  cp ${configFile} "''${out}/statix.toml"
                '';
              in
              pkgs.writeShellScript "statix-fix" ''
                for file in "''$@"; do
                  ${lib.getExe pkgs.statix} fix --config '${toString configDir}/statix.toml' "$file"
                done
              '';
            includes = [ "*.nix" ];
          };

        };

    global.excludes = [
      "*.lock"
      ".gitignore"
    ];

  };

  configFile = toml.generate "treefmt.toml" treefmt;

in
pkgs.runCommand "treefmt-pyproject"
  {
    meta.mainProgram = "treefmt-pyproject";
  }
  ''
    mkdir -p $out/bin

    cat > $out/bin/$name << EOF
    #!${pkgs.runtimeShell}
    set -euo pipefail
    unset PRJ_ROOT
    exec ${lib.getExe pkgs.treefmt} \
      --config-file=${configFile} \
      --tree-root-file=${projectRootFile} \
      "$@"
    EOF
    chmod +x $out/bin/$name

    ln -s $out/bin/$name $out/bin/treefmt
  ''
