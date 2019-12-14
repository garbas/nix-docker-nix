{ pkgs ? import <nixpkgs> {}
, nix ? pkgs.nix
}:

let
  inherit (pkgs) stdenv;
  inherit (pkgs.lib) concatStringsSep genList;

  channel = "nixos-${builtins.readFile "${pkgs.path}/.version"}";

  channelUrl = "https://github.com/NixOS/nixpkgs-channels/archive/${channel}.tar.gz";

  nixVersion = (builtins.parseDrvName pkgs.nix.name).version;

  nixpkgsChannel = pkgs.runCommand "nixpkgs-channel" {} ''
    mkdir -p $out/nixpkgs
    cp -R ${pkgs.path}/* $out/nixpkgs/
    cp -R ${pkgs.path}/.version $out/nixpkgs/
  '';

  nixVerify = stdenv.mkDerivation {
    name = "nix-verify";
    src = ./nix-verify.sh;
    buildCommand = ''
      mkdir -p $out/bin
      cp $src $out/bin/nix-verify
      sed -i \
        -e "s|/usr/bin/env bats|${pkgs.bats}/bin/bats|" \
        -e "s|grep|${pkgs.gnugrep}/bin/grep|" \
          $out/bin/nix-verify
      chmod +x $out/bin/nix-verify
    '';
  };

  # TODO: config could be using nixos modules
  defaultConfig = {
    Env = [
      "HOME=/root"
      # TODO: PATH should be calculated from contents
      "PATH=/root/.nix-profile/bin"
      "NIX_PAGER=cat"
      "NIX_PATH=nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixpkgs"
      "GIT_SSL_CAINFO=/root/.nix-profile/etc/ssl/certs/ca-bundle.crt"
      "SSL_CERT_FILE=/root/.nix-profile/etc/ssl/certs/ca-bundle.crt"
    ];
    Cmd = [ "bash" ];
    WorkingDir = "/root";
  };

  # TODO: maybe we should use busybox instead of coreutils
  mkNixEnv = nix: contents: pkgs.buildEnv {
    name = "user-environment";
    paths = [
      nix
      # nix-store uses cat program to display results as specified by
      # the image env variable NIX_PAGER.
      pkgs.coreutils
      # nix-channel/nix-build/nix-env needs SSL_CERT_FILE set to be able to
      # download from binary cache. we also set GIT_SSL_CAINFO.
      pkgs.cacert
      # TODO: write why we need it
      nixpkgsChannel
      # TODO: write why we need it
      pkgs.bashInteractive
    ] ++ contents;
    # TODO: create manifest.nix
    #postBuild = ''
    #'';
  };

  buildImageWithNix = args@{ contents ? []
                           , runAsRoot ? ""
                           , nix ? pkgs.nix
                           , config ? defaultConfig
                           , ...
                           }:
    let
      contentsEnv = mkNixEnv nix contents;
    in
    (pkgs.dockerTools.buildImageWithNixDb (args // {
      inherit config;
      runAsRoot = ''
        #!${stdenv.shell}
        ${pkgs.dockerTools.shadowSetup}

        # Create root user
        mkdir -p /etc
        echo 'root:x:0:0::/root:/root/.nix-profile/bin/bash' > /etc/passwd
        echo 'nixbld0:x:3000:1::/root:/root/.nix-profile/bin/bash' >> /etc/passwd
        echo 'nixbld1:x:3001:1::/root:/root/.nix-profile/bin/bash' >> /etc/passwd
        echo 'nixbld2:x:3002:1::/root:/root/.nix-profile/bin/bash' >> /etc/passwd
        echo 'nixbld3:x:3003:1::/root:/root/.nix-profile/bin/bash' >> /etc/passwd
        echo 'nixbld4:x:3004:1::/root:/root/.nix-profile/bin/bash' >> /etc/passwd
        echo 'nixbld5:x:3005:1::/root:/root/.nix-profile/bin/bash' >> /etc/passwd
        echo 'nixbld6:x:3006:1::/root:/root/.nix-profile/bin/bash' >> /etc/passwd
        echo 'nixbld7:x:3007:1::/root:/root/.nix-profile/bin/bash' >> /etc/passwd
        echo 'nixbld8:x:3008:1::/root:/root/.nix-profile/bin/bash' >> /etc/passwd
        echo 'nixbld9:x:3009:1::/root:/root/.nix-profile/bin/bash' >> /etc/passwd
        echo 'root:x:0:' > /etc/group
        echo 'nixbld:x:1:nixbld0,nixbld1,nixbld2,nixbld3,nixbld4,nixbld5,nixbld6,nixbld7,nixbld8,nixbld9' > /etc/group

        # TODO: why do we need this files explain in comments
        mkdir -p /etc
        echo 'hosts: files dns myhostname mymachines' > /etc/nsswitch.conf

        # Create temporary folder
        mkdir /tmp
        chmod 1777 /tmp

        # Subscribe to Nix channel
        mkdir -p /root
        echo 'https://nixos.org/channels/${channel} nixpkgs' > /root/.nix-channels

        # Create initial channel
        mkdir -p /nix/var/nix/profiles/per-user/root /root/.nix-defexpr
        ln -s ${nixpkgsChannel} /nix/var/nix/profiles/per-user/root/channels-1-link
        ln -s channels-1-link /nix/var/nix/profiles/per-user/root/channels
        ln -s /nix/var/nix/profiles/per-user/root/channels /root/.nix-defexpr/channels_root

        # Create default profile for
        mkdir -p /nix/var/nix/profiles
        ln -s ${contentsEnv} /nix/var/nix/profiles/per-user/root/default-1-link
        ln -s default-1-link /nix/var/nix/profiles/per-user/root/default
        # things installed with nix-env go to /nix/var/nix/profiles/per-user/root/default
        # we need to create ~/.nix-profile symlink manually
        ln -s /nix/var/nix/profiles/per-user/root/default /root/.nix-profile


        mkdir -p /nix/var/nix/gcroots
        ln -s /nix/var/nix/profiles /nix/var/nix/gcroots/profiles

        # Make the shell source nix.sh during login.
        nix_profile=/root/.nix-profile/etc/profile.d/nix.sh
        echo "if [ -e $nix_profile ]; then . $nix_profile; fi" >> /root/.bash_profile

      '' + runAsRoot;
    }));

in
{
  inherit nixVerify
          nixpkgsChannel
          mkNixEnv
          buildImageWithNix;
  docker = {
    noSandbox = buildImageWithNix {
      name = "nix";
      tag = nixVersion;
      contents = [
        # used for testing, for now
        nixVerify
        # temporary remove when done
        pkgs.tree
        pkgs.gnugrep
      ];
      extraCommands = ''
        mkdir -p /etc/nix
        echo "sandbox = false" > /etc/nix/nix.conf
      '';
    };
    # TODO: withSandbox = buildImageWithNixSandbox {
    #   name = "nix-sandbox";
    #   tag = nixVersion;
    # };
    # TODO: withDeamon = buildImageWithNixDaemon {
    #   name = "nix-daemon";
    #   tag = nixVersion;
    # };

  };
}
