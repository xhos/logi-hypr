{
  description = "logitech gesture support for hyprland";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];
    forEach = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
  in {
    packages = forEach (pkgs: {
      default = pkgs.rustPlatform.buildRustPackage {
        pname = "logi-hypr";
        version = "0.1.0";
        src = self;
        cargoLock.lockFile = ./Cargo.lock;
        nativeBuildInputs = with pkgs; [pkg-config];
      };
    });

    nixosModules.default = {
      config,
      lib,
      pkgs,
      ...
    }: let
      cfg = config.programs.logi-hypr;
      defaultPackage = self.packages.${pkgs.system}.default;
    in {
      options.programs.logi-hypr = {
        enable = lib.mkEnableOption "logitech gesture support for hyprland";

        package = lib.mkOption {
          type = lib.types.package;
          default = defaultPackage;
          description = "package for logi-hypr";
        };

        gesture = {
          tapTimeoutMs = lib.mkOption {
            type = lib.types.int;
            default = 200;
            description = "gesture is a tap if button held for less (ms)";
          };

          movementThreshold = lib.mkOption {
            type = lib.types.int;
            default = 100;
            description = "movement threshold for gesture detection (px)";
          };

          commands = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
            description = "Gesture command mappings";
            example = {
              tap = "hyprctl dispatch togglespecialworkspace";
              left = "playerctl previous";
              right = "playerctl next";
              up = "hyprctl dispatch workspace m-1";
              down = "hyprctl dispatch workspace m+1";
            };
          };
        };

        scroll = {
          poll = lib.mkOption {
            type = lib.types.int;
            default = 200;
            description = "how often to poll for active window focus (ms)";
          };

          rules = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule {
              options = {
                window = lib.mkOption {
                  type = lib.types.str;
                  description = "regex pattern to match window class";
                  example = "firefox|chrome";
                };
                scrollRightCommands = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                  description = "commands to execute on scroll right";
                };
                scrollLeftCommands = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                  description = "commands to execute on scroll left";
                };
              };
            });
            default = [];
            description = "scroll behavior rules per window class";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [
          cfg.package
          (pkgs.writeShellScriptBin "logi-hypr-run" ''
            exec ${cfg.package}/bin/logi-hypr \
              --tap-timeout-ms ${toString cfg.gesture.tapTimeoutMs} \
              --movement-threshold ${toString cfg.gesture.movementThreshold} \
              --focus-poll-ms ${toString cfg.scroll.poll} \
              ${lib.optionalString (cfg.gesture.commands != {}) ''
              --gesture-commands '${builtins.toJSON {
                tap = cfg.gesture.commands.tap or "";
                left = cfg.gesture.commands.left or "";
                right = cfg.gesture.commands.right or "";
                up = cfg.gesture.commands.up or "";
                down = cfg.gesture.commands.down or "";
              }}' \
            ''} \
              ${lib.optionalString (cfg.scroll.rules != []) ''
              --scroll-rules '${builtins.toJSON (map (r: {
                  window_class_regex = r.window;
                  scroll_right_commands = r.scrollRightCommands;
                  scroll_left_commands = r.scrollLeftCommands;
                })
                cfg.scroll.rules)}' \
            ''} \
              "$@"
          '')
        ];
      };
    };

    homeManagerModules.default = {
      config,
      lib,
      pkgs,
      ...
    }: let
      cfg = config.programs.logi-hypr;
      defaultPackage = self.packages.${pkgs.system}.default;
    in {
      options.programs.logi-hypr = {
        enable = lib.mkEnableOption "logitech gesture support for hyprland";

        package = lib.mkOption {
          type = lib.types.package;
          default = defaultPackage;
          description = "package for logi-hypr";
        };

        gesture = {
          tapTimeoutMs = lib.mkOption {
            type = lib.types.int;
            default = 200;
            description = "gesture is a tap if button held for less (ms)";
          };

          movementThreshold = lib.mkOption {
            type = lib.types.int;
            default = 100;
            description = "movement threshold for gesture detection (px)";
          };

          commands = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
            description = "gesture command mappings";
            example = {
              tap = "hyprctl dispatch togglespecialworkspace";
              left = "playerctl previous";
              right = "playerctl next";
              up = "hyprctl dispatch workspace m-1";
              down = "hyprctl dispatch workspace m+1";
            };
          };
        };

        scroll = {
          poll = lib.mkOption {
            type = lib.types.int;
            default = 200;
            description = "how often to poll for active window focus (ms)";
          };

          rules = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule {
              options = {
                window = lib.mkOption {
                  type = lib.types.str;
                  description = "regex pattern to match window class";
                  example = "firefox|chrome";
                };
                scrollRightCommands = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                  description = "commands to execute on scroll right";
                };
                scrollLeftCommands = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                  description = "commands to execute on scroll left";
                };
              };
            });
            default = [];
            description = "scroll behavior rules per window class";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        home.packages = [
          cfg.package
          (pkgs.writeShellScriptBin "logi-hypr-run" ''
            exec ${cfg.package}/bin/logi-hypr \
              --tap-timeout-ms ${toString cfg.gesture.tapTimeoutMs} \
              --movement-threshold ${toString cfg.gesture.movementThreshold} \
              --focus-poll-ms ${toString cfg.scroll.poll} \
              ${lib.optionalString (cfg.gesture.commands != {}) ''
              --gesture-commands '${builtins.toJSON {
                tap = cfg.gesture.commands.tap or "";
                left = cfg.gesture.commands.left or "";
                right = cfg.gesture.commands.right or "";
                up = cfg.gesture.commands.up or "";
                down = cfg.gesture.commands.down or "";
              }}' \
            ''} \
              ${lib.optionalString (cfg.scroll.rules != []) ''
              --scroll-rules '${builtins.toJSON (map (r: {
                  window_class_regex = r.window;
                  scroll_right_commands = r.scrollRightCommands;
                  scroll_left_commands = r.scrollLeftCommands;
                })
                cfg.scroll.rules)}' \
            ''} \
              "$@"
          '')
        ];
      };
    };

    devShells = forEach (pkgs: {
      default = pkgs.mkShell {
        packages = with pkgs; [cargo rustc pkg-config];
      };
    });
  };
}
