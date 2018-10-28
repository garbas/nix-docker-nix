{ nix ? builtins.fetchGit ./../nix
, channel ? "nixos-18.09"
, nixpkgs ? builtins.fetchGit { url = https://github.com/NixOS/nixpkgs-channels.git; ref = channel; }
, officialRelease ? false
, systems ? [ "x86_64-linux" "i686-linux" "x86_64-darwin" "aarch64-linux" ]
}:

let
  pkgs = import nixpkgs { system = builtins.currentSystem or "x86_64-linux"; };
  jobs = import ./../nix/release.nix { inherit nix nixpkgs officialRelease systems; };

  inherit (pkgs) stdenv;
  inherit (pkgs.lib) concatStringsSep genList;

  channelUrl = "https://github.com/NixOS/nixpkgs-channels/archive/${channel}.tar.gz";
  passwd = ''
    root:x:0:0::/root:/run/current-system/sw/bin/bash
    ${concatStringsSep "\n" (genList (i: "nixbld${toString (i+1)}:x:${toString (i+30001)}:30000::/var/empty:/run/current-system/sw/bin/nologin") 32)}
  '';

  group = ''
    root:x:0:
    nogroup:x:65534:
    nixbld:x:30000:${concatStringsSep "," (genList (i: "nixbld${toString (i+1)}") 32)}
  '';

  nsswitch = ''
    hosts: files dns myhostname mymachines
  '';

  nix-verify = stdenv.mkDerivation {
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

  nixpkgsChannel = pkgs.runCommand "nixpkgs-channel" {} ''
    mkdir -p $out/nixpkgs
    cp -R ${nixpkgs}/* $out/nixpkgs/
    cp -R ${nixpkgs}/.version $out/nixpkgs/
  '';


  defaultConfig ={
    Env = [
      "HOME=/root"
      # TODO: PATH should be calculated from contents
      "PATH=/root/.nix-profile/bin"
      "NIX_PAGER=cat"
      "NIX_PATH=nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixpkgs"
      "GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    ];
  };

  mkContentsEnv = nix: contents: pkgs.buildEnv {
    name = "user-environment";
    paths = [
      nix
      # nix-store uses cat program to display results as specified by
      # the image env variable NIX_PAGER.
      pkgs.coreutils
      pkgs.cacert
      nixpkgsChannel
      pkgs.bashInteractive # TODO: maybe busybox
    ] ++ contents;
  };
  buildImageWithNix = args@{ contents ? []
                           , runAsRoot ? ""
                           , nix ? pkgs.nix
                           , config ? defaultConfig
                           , ...
                           }:
    let
      contentsEnv = mkContentsEnv nix contents;
    in
    (pkgs.dockerTools.buildImageWithNixDb (args // {
      inherit config;
      runAsRoot = ''
        #!${stdenv.shell}
        ${pkgs.dockerTools.shadowSetup}

        mkdir -p /etc
        # TODO: why do we need this files explain in comments
        echo '${passwd}' > /etc/passwd
        echo '${group}' > /etc/group
        echo '${nsswitch}' > /etc/nsswitch.conf

        mkdir /tmp
        chmod 1777 /tmp

        export HOME=/root
        mkdir -p /root/.nix-defexpr
        ${contentsEnv}/bin/nix-channel --add https://nixos.org/channels/${channel} nixpkgs

        # this is needed to make nix-channel work
        ln -s ${nixpkgsChannel} /nix/var/nix/profiles/per-user/root/channels-1-link
        ln -s channels-1-link /nix/var/nix/profiles/per-user/root/channels
        ln -s /nix/var/nix/profiles/per-user/root/channels /root/.nix-defexpr/channels_root

        # things installed with nix-env go to /nix/var/nix/profiles/default
        # we need to create ~/.nix-profile symlink manually
        ln -s /nix/var/nix/profiles/default /root/.nix-profile

        # TODO: add description
        mkdir -p /nix/var/nix/profiles
        ln -s ${contentsEnv} /nix/var/nix/profiles/default-1-link
        ln -s default-1-link /nix/var/nix/profiles/default

        mkdir -p /nix/var/nix/gcroots
        ln -s /nix/var/nix/profiles /nix/var/nix/gcroots/profiles

        # Make the shell source nix.sh during login.
        nix_profile=$HOME/.nix-profile/etc/profile.d/nix.sh
        echo "if [ -e $nix_profile ]; then . $nix_profile; fi" >> "$HOME/.bash_profile"
      '' + runAsRoot;
    }));

  nix_version = (builtins.parseDrvName pkgs.nix.name).version;

in
{
  docker = {
    noSandbox = buildImageWithNix {
      name = "nix";
      tag = "${nix_version}-no-sandbox";
      contents = [
        # used for testing, for now
        nix-verify
        # temporary remove when done
        pkgs.tree
        pkgs.gnugrep
      ];
    };
  };
}
