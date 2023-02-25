{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      json = builtins.fromJSON (builtins.readFile "${self}/package.json");

      name = json.name;
    in
    {
      overlays.default = final: prev:
        let
          inherit (final)
            darwin
            buildNpmPackage
            lib
            stdenv
            rustPlatform;
          inherit (darwin.apple_sdk.frameworks)
            Carbon
            CoreServices
            Security
            WebKit
            AppKit;

          frontend = buildNpmPackage {
            pname = name;
            src = self;
            inherit (json) version;
            npmDepsHash = "sha256-me2Fsvafir/e/k8nbxDdy4lLuvnTT7m8k+GVs3p12MY=";
            postInstall = ''
              cp -r .svelte-kit $out/lib/node_modules/${name}/build/
            '';
          };

          toml = builtins.fromTOML (builtins.readFile ./src-tauri/Cargo.toml);

          tauri-pkg = rustPlatform.buildRustPackage {
            pname = toml.package.name;
            src = ./src-tauri;
            inherit (toml.package) version;
            cargoLock.lockFile = ./src-tauri/Cargo.lock;

            postPatch = ''
              substituteInPlace tauri.conf.json --replace \
                '"distDir": "../build"' '"distDir": "${frontend}/lib/node_modules/${name}/build"'
            '';

            buildInputs = lib.optionals stdenv.isDarwin [
              Carbon
              CoreServices
              Security
              WebKit
              AppKit
            ];
          };
        in
        {
          ${name} = tauri-pkg;
          cache = prev.mkShell {
            name = "${name}-devShell";
            inputsFrom = [ tauri-pkg ];
            packages = with prev; [
              rust-analyzer
              clippy
              rustfmt
            ];
            shellHook = ''
              export PATH=$PWD/target/debug:$PATH
            '';
          };
        }
      ;
    } //

    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };
        inherit (pkgs) cache;
        package = pkgs.${name};
      in
      {
        packages = {
          inherit cache;
          default = package;
          ${name} = package;
        };
        devShells.default = cache;
      }));
}
