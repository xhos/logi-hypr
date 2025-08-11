{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = f:
      builtins.listToAttrs (map (system: {
          name = system;
          value = f system;
        })
        systems);
  in {
    packages = forAllSystems (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      default = pkgs.rustPlatform.buildRustPackage {
        pname = "logi-gesture";
        version = "0.1.0";
        src = self;
        cargoLock.lockFile = ./Cargo.lock;
        nativeBuildInputs = [pkgs.pkg-config];
      };
    });

    devShells = forAllSystems (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      default = pkgs.mkShell {
        packages = with pkgs; [cargo rustc pkg-config];
      };
    });

    nixosModules.default = {
      lib,
      pkgs,
      config,
      ...
    }: let
      logiGesturePkg = self.packages.${pkgs.system}.default;
    in
      (import ./module.nix) {
        inherit lib pkgs config;
        logiGesturePkg = logiGesturePkg;
      };

    overlays.default = final: prev: {
      logi-gesture = self.packages.${final.system}.default;
    };
  };
}
