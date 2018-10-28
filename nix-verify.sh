#!/usr/bin/env bats

cd $BATS_TMPDIR

@test "Initially nothing should be garbage collected" {
  STORE1=`ls -la /nix/store | wc -l`
  nix-collect-garbage -d
  STORE2=`ls -la /nix/store | wc -l`
  [ "$STORE1" == "$STORE2" ]
}

@test "Install hello using nix-env" {
  nix-env -iA nixpkgs.hello
  [ "`hello`" == "Hello, world!" ]
}

@test "Install hello using nix build" {
  STORE1=`ls -la /nix/store | wc -l`
  nix build nixpkgs.hello
  STORE2=`ls -la /nix/store | wc -l`
  [ "`./result/bin/hello`" == "Hello, world!" ]
  [ "$STORE1" == "$STORE2" ]
}

@test "Can we update the channel?" {
  nix-channel --update
}

@test "Install hello using nix-env after channel update" {
  nix-env -iA nixpkgs.hello
  [ "`hello`" == "Hello, world!" ]
}

@test "Install hello using nix build after channel update" {
  STORE1=`ls -la /nix/store | wc -l`
  nix build nixpkgs.hello
  STORE2=`ls -la /nix/store | wc -l`
  [ "`./result/bin/hello`" == "Hello, world!" ]
  [ "$STORE1" == "$STORE2" ]
}

@test "Verify hello installation using nix-build" {
  nix-build '<nixpkgs>' -A hello --check
  [ "`./result/bin/hello`" == "Hello, world!" ]
}

@test "Test sandbox is disabled" {
  cat >tmp.nix <<'EOL'
let
  pkgs = import <nixpkgs> {};
in pkgs.runCommand "sandbox-test" { buildInputs = [ pkgs.curl ]; } ''
  export SSL_CERT_FILE="\${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
  curl https://cache.nixos.org/nix-cache-info > $out
''
EOL
  nix build -f tmp.nix
  [ "`cat result | grep StoreDir`" == "StoreDir: /nix/store" ]
}
