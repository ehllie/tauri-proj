{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      toml = builtins.fromTOML (builtins.readFile ./src-tauri/Cargo.toml);
      json = builtins.fromJSON (builtins.readFile "${self}/package.json");

      name = toml.package.name;
      fe-name = json.name;
    in
    {
      overlays.default = final: prev:
        let
          inherit (final)
            darwin
            buildNpmPackage
            lib
            stdenv
            cargo-tauri
            writeShellScriptBin
            rustPlatform;
          inherit (darwin.apple_sdk.frameworks)
            Carbon
            CoreServices
            Security
            WebKit
            AppKit;

          frontend = buildNpmPackage {
            pname = fe-name;
            src = self;
            inherit (json) version;
            npmDepsHash = "sha256-me2Fsvafir/e/k8nbxDdy4lLuvnTT7m8k+GVs3p12MY=";
            postInstall = ''
              cp -r .svelte-kit $out/lib/node_modules/${fe-name}/build/
            '';
          };

          tauri-pkg = rustPlatform.buildRustPackage {
            pname = name;
            src = ./src-tauri;
            inherit (toml.package) version;
            cargoLock.lockFile = ./src-tauri/Cargo.lock;

            postPatch = ''
              substituteInPlace tauri.conf.json --replace \
                '"distDir": "../build"' '"distDir": "${frontend}/lib/node_modules/${fe-name}/build"'
            '';

            nativeBuildInputs = [
              cargo-tauri
              (writeShellScriptBin "npm" "true")
            ];

            buildInputs = lib.optionals stdenv.isDarwin [
              Carbon
              CoreServices
              Security
              WebKit
              AppKit
            ];

            buildPhase = ''
              # function npm { true; }
              # cargo tauri info
              cargo tauri build -vb app
            '';

            installPhase = ''
              mkdir -p $out/Applications
              cp -r target/release/bundle/macos/*.app $out/Applications/
            '';

            passthru = rec {
              shell = prev.mkShell {
                name = "${fe-name}-devShell";
                inputsFrom = [ tauri-pkg ];
                packages = with prev; [
                  cargo-tauri
                  rust-analyzer
                  clippy
                  rustfmt
                ];
                shellHook = ''
                  export PATH=$PWD/target/debug:$PATH
                '';
              };
              cache = shell;
            };
          };
        in
        { ${name} = tauri-pkg; }
      ;
    } //

    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ self.overlays.default ];
        };
        package = pkgs.${name};
      in
      {
        packages = {
          default = package;
          ${name} = package;
          cache = package.passthru.cache;
        };
        devShells.default = package.passthru.shell;
      }));
}
