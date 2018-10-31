# Implementing https://github.com/moby/moby/blob/master/image/spec/v1.2.md in
# NixOS modules

{ pkgs ? import <nixpkgs> {}
, configuration
}:

let

  baseModule = { config, lib, ... }:
    with lib;
    { options =
        let
          healthcheck = {
            Test = mkOption {
              type = types.nullOr (types.listOf types.string);
              default = null;
              description = ''
                The test to perform to check that the container is healthy. The
                options are:

                - [] : inherit healthcheck from base image
                - ["NONE"] : disable healthcheck
                - ["CMD", arg1, arg2, ...] : exec arguments directly
                - ["CMD-SHELL", command] : run command with system's default shell

                The test command should exit with a status of 0 if the container
                is healthy, or with 1 if it is unhealthy.
              '';
            };
            Interval = mkOption {
              type = types.nullOr (types.int);
              default = null;
              description = ''
                Number of nanoseconds to wait between probe attempts.
              '';
            };
            Timeout = mkOption {
              type = types.nullOr (types.int);
              default = null;
              description = ''
                Number of nanoseconds to wait before considering the check to
                have hung.
              '';
            };
            Retries = mkOption {
              type = types.nullOr (types.int);
              default = null;
              description = ''
                The number of consecutive failures needed to consider a
                container as unhealthy.
              '';
            };
          };
        in
        { User = mkOption {
            type = types.nullOr types.string;
            default = null;
            description = ''
              The username or UID which the process in the container should run
              as. This acts as a default value to use when the value is not
              specified when creating a container.

              All of the following are valid:

                  user
                  uid
                  user:group
                  uid:gid
                  uid:group
                  user:gid

              If group/gid is not specified, the default group and supplementary
              groups of the given user/uid in /etc/passwd from the container are
              applied.
            '';
          };
          Memory = mkOption {
            type = types.nullOr types.int;
            default = null;
            description = ''
              Memory limit (in bytes). This acts as a default value to use when
              the value is not specified when creating a container.
            '';
          };
          MemorySwap = mkOption {
            type = types.nullOr types.int;
            default = null;
            description = ''
              Total memory usage (memory + swap); set to -1 to disable swap.
              This acts as a default value to use when the value is not
              specified when creating a container.
            '';
          };
          CpuShares = mkOption {
            type = types.nullOr types.int;
            default = null;
            description = ''
              CPU shares (relative weight vs. other containers). This acts as a
              default value to use when the value is not specified when creating
              a container.
            '';
          };
          ExposedPorts = mkOption {
            type = types.nullOr (types.listOf types.string);
            default = null;
            description = ''
              A list of ports to expose from a container running this image.
              Here is an example:

              [ "8080" "53/udp" "2356/tcp" ]

              Its keys can be in the format of:

                  "<port>/tcp" "<port>/udp" "<port>"

              with the default protocol being "tcp" if not specified. These
              values act as defaults and are merged with any specified when
              creating a container.
            '';
          };
          Env = mkOption {
            type = types.nullOr (types.attrsOf types.str);
            default = null;
            description = ''
              Entries are in the format of VARNAME="var value". These values act
              as defaults and are merged with any specified when creating a
              container.
            '';
          };
          Entrypoint = mkOption {
            type = types.nullOr (types.listOf types.string);
            default = null;
            description = ''
              A list of arguments to use as the command to execute when the
              container starts. This value acts as a default and is replaced by
              an entrypoint specified when creating a container.
            '';
          };
          Cmd = mkOption {
            type = types.nullOr (types.listOf types.string);
            default = null;
            description = ''
              Default arguments to the entry point of the container. These
              values act as defaults and are replaced with any specified when
              creating a container. If an Entrypoint value is not specified,
              then the first entry of the Cmd array should be interpreted as the
              executable to run.
            '';
          };
          Healthcheck = mkOption {
            type = types.nullOr (types.submodule healthcheck);
            default = null;
            description = ''
              A test to perform to determine whether the container is healthy.

              Here is an example:

              {
                "Test": [
                    "CMD-SHELL",
                    "/usr/bin/check-health localhost"
                ],
                "Interval": 30000000000,
                "Timeout": 10000000000,
                "Retries": 3
              }

              The object has the following fields.
            '';
          };
          Volumes = mkOption {
            type = types.nullOr (types.listOf types.string);
            default = null;
            description = ''
              A list of directories which should be created as data volumes in a
              container running this image.

              Here is an example:

              [
                  "/var/my-app-data/"
                  "/etc/some-config.d/"
              ]
            '';
          };
          WorkingDir = mkOption {
            type = types.nullOr (types.string);
            default = null;
            description = ''
              Sets the current working directory of the entry point process in
              the container. This value acts as a default and is replaced by a
              working directory specified when creating a container.
            '';
          };
        };
    };

  eval = pkgs.lib.evalModules { modules = [ baseModule configuration ]; };

in
  builtins.mapAttrs
    (n: v: if n == "ExposedPorts" || n == "Volumes"
             then builtins.listToAttrs (builtins.map (x: { name = x; value = {}; }) v)
           else if n == "Env"
             then pkgs.lib.mapAttrsToList (n: v: "${n}=${v}") v
           else v)
    (pkgs.lib.filterAttrs
      (n: v: n != "_module" &&  # remove internal representation
             v != null        # remove unassigned values
      ) eval.config)
