{ pkgs ? import <nixpkgs> {}
, nix ? pkgs.nix
}:

let
  inherit (pkgs) stdenv;
  inherit (pkgs.lib) concatStringsSep genList;

  channel = builtins.replaceStrings ["\n"] [""]
    "nixos-${builtins.readFile "${pkgs.path}/.version"}";

  nixVersion = (builtins.parseDrvName pkgs.nix.name).version;

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
      pkgs.coreutils pkgs.gnused
      # nix-channel/nix-build/nix-env needs SSL_CERT_FILE set to be able to
      # download from binary cache. we also set GIT_SSL_CAINFO.
      pkgs.cacert
      # TODO: write why we need it
      pkgs.bashInteractive
    ] ++ contents;
    # TODO: create manifest.nix
    #postBuild = ''
    #'';
  };

  shadowSetup = ''
    NIX_GROUP_NB=30

    export PATH=${pkgs.shadow}/bin:$PATH

    mkdir -p etc/pam.d
    if [[ ! -f etc/passwd ]]; then
      echo 'root:x:0:0::/root:/root/.nix-profile/bin/bash' > etc/passwd

      # Create NIX_GROUP_NB Nix build users
      for i in $(seq 1 $NIX_GROUP_NB); do echo "nixbld$i:x:$((30000 + $i)):30000:::" >> etc/passwd; done

      echo "root:!x:::::::" > etc/shadow
    fi
    if [[ ! -f etc/group ]]; then
      echo "root:x:0:" > etc/group

      # Create the nixbld group
      echo -n "nixbld:x:30000:nixbld1" >> etc/group
      for i in $(seq 2 $NIX_GROUP_NB); do echo -n ",nixbld$i" >> etc/group; done
      echo >> etc/group

      echo "root:x::" > etc/gshadow
    fi

    if [[ ! -f etc/pam.d/other ]]; then
      cat > etc/pam.d/other <<EOF
    account sufficient pam_unix.so
    auth sufficient pam_rootok.so
    password requisite pam_unix.so nullok sha512
    session required pam_unix.so
    EOF
    fi
    if [[ ! -f etc/login.defs ]]; then
      touch etc/login.defs
    fi
  '';


  buildImageWithNix = args@{ contents ? []
                           , extraCommands ? ""
                           , nix ? pkgs.nix
                           , config ? defaultConfig
                           , ...
                           }:
    let
      contentsEnv = mkNixEnv nix contents;
    in
    (pkgs.dockerTools.buildImageWithNixDb (args // {
      inherit config;
      contents = [contentsEnv];
      extraCommands = ''
        #!${stdenv.shell}
        chmod u+w etc

        ${shadowSetup}

        # TODO: why do we need this files explain in comments
        mkdir -p etc
        echo 'hosts: files dns myhostname mymachines' > etc/nsswitch.conf

        # Create temporary folder
        mkdir tmp
        chmod 1777 tmp

        # Subscribe to Nix channel
        mkdir -p root
        echo 'https://nixos.org/channels/${channel} nixpkgs' > root/.nix-channels

        # Create default profile for
        mkdir -p nix/var/nix/profiles/per-user/root
        ln -s ${contentsEnv} nix/var/nix/profiles/per-user/root/default-1-link
        ln -s default-1-link nix/var/nix/profiles/per-user/root/default
        # things installed with nix-env go to /nix/var/nix/profiles/per-user/root/default
        # we need to create ~/.nix-profile symlink manually
        ln -s /nix/var/nix/profiles/per-user/root/default root/.nix-profile

        mkdir -p nix/var/nix/gcroots
        # TODO: remove the profiles file created by buildImageWithNixDB (the link is wrong)
        ln -sf /nix/var/nix/profiles nix/var/nix/gcroots/profiles

        # Make the shell source nix.sh during login.
        nix_profile=root/.nix-profile/etc/profile.d/nix.sh
        echo "if [ -e $nix_profile ]; then . $nix_profile; fi" >> root/.bash_profile
      '' + extraCommands;
    }));

in
{
  inherit nixVerify
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
