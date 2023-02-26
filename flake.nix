{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      json = builtins.fromJSON (builtins.readFile "${self}/package.json");
      pname = json.name;
      version = json.version;
    in
    {
      overlays.default = final: prev:
        let
          inherit (final)
            darwin
            fetchNpmDeps
            lib
            rustPlatform
            stdenv;

          package = stdenv.mkDerivation {
            inherit pname version;
            src = self;

            nativeBuildInputs = lib.attrValues {
              inherit (final.npmHooks)
                npmConfigHook;
              inherit (rustPlatform)
                cargoSetupHook;
              inherit (final)
                cargo-tauri
                cargo
                libiconv
                nodejs
                rustc;
              inherit (darwin.apple_sdk.frameworks)
                AppKit
                Carbon
                CoreServices
                Security
                WebKit;
            };

            npmDeps = fetchNpmDeps {
              src = self;
              inherit (package) name;
              hash = "sha256-me2Fsvafir/e/k8nbxDdy4lLuvnTT7m8k+GVs3p12MY=";
            };

            cargoDeps = rustPlatform.importCargoLock {
              lockFile = ./src-tauri/Cargo.lock;
            };

            postPatch = ''
              # cargoSetupHook expects a Cargo.lock in the base directory
              ln src-tauri/Cargo.lock Cargo.lock
            '';

            buildPhase = ''
              # passing `-b app` so that the bundler doesn't try to create a dmg
              # needs to be changed for linux builds
              cargo tauri build -vb app
            '';

            installPhase = ''
              # darwin specific install logic
              mkdir -p $out/Applications
              cp -r src-tauri/target/release/bundle/macos/*.app \
                $out/Applications/
            '';

            # convinience passthru for hacking on the project with devShells
            passthru = rec {
              shell = prev.mkShell {
                name = "${pname}-devShell";
                inputsFrom = [ package ];
                packages = lib.attrValues {
                  inherit (final)
                    rust-analyzer
                    clippy
                    rustfmt;
                };
                shellHook = ''
                  export PATH=$PWD/target/debug:$PATH
                '';
              };
              cache = shell;
            };
          };
        in
        { ${pname} = package; };
    } //

    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };
        package = pkgs.${pname};
      in
      {
        packages = {
          default = package;
          ${pname} = package;
          cache = package.passthru.cache;
        };
        devShells.default = package.passthru.shell;
      }));
}
