{ pkgs ? import <nixpkgs> {}
}:
let
  mkConfig = config:
    import ./config.nix {
      inherit pkgs;
      configuration = _: config;
    };
in
  pkgs.writeText "config-all.json"
    (builtins.toJSON
      {
        empty = mkConfig {};
        all = mkConfig {
          User = "app";
          Memory = 123;
          MemorySwap = 1234;
          CpuShares = 2;
          ExposedPorts = [ "8080" "53/udp" "2356/tcp" ];
          Env = { "PATH" = "/bin:/usr/bin"; };
          Entrypoint = [ "/bin/entrypoint.sh" ];
          Cmd = [ "/bin/bash" ];
          Healthcheck = {
            Test = [ "test" ];
            Interval = 123;
            Timeout = 123;
            Retries = 123;
          };
          Volumes = [ "/app" "/etc/secrets" ];
          WorkingDir = "/app";
        };
      })
