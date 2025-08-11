{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
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
      logi-hypr = pkgs.rustPlatform.buildRustPackage {
        pname = "logi-hypr";
        version = "0.1.0";
        src = self;
        cargoLock.lockFile = ./Cargo.lock;
        nativeBuildInputs = with pkgs; [pkg-config];
      };

      default = self.packages.${system}.logi-hypr;
    });

    nixosModules = {
      logi-hypr = {
        config,
        lib,
        pkgs,
        ...
      }: let
        cfg = config.programs.logi-hypr;
        package = self.packages.${pkgs.stdenv.hostPlatform.system}.logi-hypr;
      in {
        options.programs.logi-hypr = {
          enable = lib.mkEnableOption "logitech gesture support for Hyprland";

          package = lib.mkOption {
            type = lib.types.package;
            default = package;
            description = "logi-hypr package to use";
          };

          enableService = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "enable the logi-hypr systemd service";
          };

          gesture = {
            tapTimeoutMs = lib.mkOption {
              type = lib.types.int;
              default = 200;
              description = "tap timeout in milliseconds";
            };

            movementThreshold = lib.mkOption {
              type = lib.types.int;
              default = 100;
              description = "movement threshold for gestures";
            };

            commands = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = {};
              description = "gesture commands mapping";
            };
          };

          scroll = {
            focusPollMs = lib.mkOption {
              type = lib.types.int;
              default = 200;
              description = "focus polling interval in milliseconds";
            };

            rules = lib.mkOption {
              type = lib.types.listOf (lib.types.submodule {
                options = {
                  windowClassRegex = lib.mkOption {
                    type = lib.types.str;
                    description = "window class regex pattern";
                  };

                  scrollRightCommands = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [];
                    description = "commands for scroll right";
                  };

                  scrollLeftCommands = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [];
                    description = "commands for scroll left";
                  };
                };
              });
              default = [];
              description = "scroll rules configuration";
            };
          };
        };

        config = lib.mkIf cfg.enable {
          environment.systemPackages = [cfg.package];

          systemd.services.logi-hypr = lib.mkIf cfg.enableService {
            description = "logitech gesture daemon for Hyprland";
            wantedBy = ["multi-user.target"];

            serviceConfig = {
              Type = "simple";
              ExecStart = let
                args =
                  [
                    "${cfg.package}/bin/logi-hypr"
                    "--tap-timeout-ms"
                    (toString cfg.gesture.tapTimeoutMs)
                    "--movement-threshold"
                    (toString cfg.gesture.movementThreshold)
                    "--focus-poll-ms"
                    (toString cfg.scroll.focusPollMs)
                  ]
                  ++ lib.optionals (cfg.gesture.commands != {}) [
                    "--gesture-commands"
                    (builtins.toJSON {
                      tap = cfg.gesture.commands.tap or "";
                      swipe_left = cfg.gesture.commands.swipeLeft or "";
                      swipe_right = cfg.gesture.commands.swipeRight or "";
                      swipe_up = cfg.gesture.commands.swipeUp or "";
                      swipe_down = cfg.gesture.commands.swipeDown or "";
                    })
                  ]
                  ++ lib.optionals (cfg.scroll.rules != []) [
                    "--scroll-rules"
                    (builtins.toJSON (map (rule: {
                        window_class_regex = rule.windowClassRegex;
                        scroll_right_commands = rule.scrollRightCommands;
                        scroll_left_commands = rule.scrollLeftCommands;
                      })
                      cfg.scroll.rules))
                  ];
              in
                lib.escapeShellArgs args;

              Restart = "on-failure";
            };
          };
        };
      };

      default = self.nixosModules.logi-hypr;
    };

    devShells = forAllSystems (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      default = pkgs.mkShell {
        packages = with pkgs; [cargo rustc pkg-config];
      };
    });
  };
}
