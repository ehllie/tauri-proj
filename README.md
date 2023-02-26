# Building tauri with nix

I wanted to explore how best to build tauri apps using nix. Initially I trying to replicate [the nixpkgs PR by dit7ya](https://github.com/NixOS/nixpkgs/pull/187547), but I ran into some issues with the approach they took. Instead of building the node and rust packages separately with `buildNpmPackage` and `buildRustPackage`, I opted to setup both npm and cargo dependencies in one derivation, and hand over the build to the `cargo tauri build` command.

Some things are darwin specific in this derivation, but it should not be that dificcult to make it crosss platform by using `lib.optionals stdenv.isDarwin` in a couple places.
