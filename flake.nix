{
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
        enable = lib.mkEnableOption "Logitech gesture support for Hyprland";

        package = lib.mkOption {
          type = lib.types.package;
          default = defaultPackage;
          description = "Package for logi-hypr";
        };

        gesture = {
          tapTimeoutMs = lib.mkOption {
            type = lib.types.int;
            default = 200;
            description = "Timeout in milliseconds for tap gestures";
          };

          movementThreshold = lib.mkOption {
            type = lib.types.int;
            default = 100;
            description = "Movement threshold for swipe detection";
          };

          commands = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
            description = "Gesture command mappings";
            example = {
              tap = "hyprctl dispatch togglespecialworkspace";
              swipeLeft = "playerctl previous";
              swipeRight = "playerctl next";
              swipeUp = "hyprctl dispatch workspace m-1";
              swipeDown = "hyprctl dispatch workspace m+1";
            };
          };
        };

        scroll = {
          focusPollMs = lib.mkOption {
            type = lib.types.int;
            default = 200;
            description = "How often to poll for active window focus in milliseconds";
          };

          rules = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule {
              options = {
                windowClassRegex = lib.mkOption {
                  type = lib.types.str;
                  description = "Regex pattern to match window class";
                  example = "firefox|chrome";
                };
                scrollRightCommands = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                  description = "Commands to execute on scroll right";
                };
                scrollLeftCommands = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                  description = "Commands to execute on scroll left";
                };
              };
            });
            default = [];
            description = "Scroll behavior rules per window class";
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
              --focus-poll-ms ${toString cfg.scroll.focusPollMs} \
              ${lib.optionalString (cfg.gesture.commands != {}) ''
              --gesture-commands '${builtins.toJSON {
                tap = cfg.gesture.commands.tap or "";
                swipe_left = cfg.gesture.commands.swipeLeft or "";
                swipe_right = cfg.gesture.commands.swipeRight or "";
                swipe_up = cfg.gesture.commands.swipeUp or "";
                swipe_down = cfg.gesture.commands.swipeDown or "";
              }}' \
            ''} \
              ${lib.optionalString (cfg.scroll.rules != []) ''
              --scroll-rules '${builtins.toJSON (map (r: {
                  window_class_regex = r.windowClassRegex;
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
        enable = lib.mkEnableOption "Logitech gesture support for Hyprland";

        package = lib.mkOption {
          type = lib.types.package;
          default = defaultPackage;
          description = "Package for logi-hypr";
        };

        gesture = {
          tapTimeoutMs = lib.mkOption {
            type = lib.types.int;
            default = 200;
            description = "Timeout in milliseconds for tap gestures";
          };

          movementThreshold = lib.mkOption {
            type = lib.types.int;
            default = 100;
            description = "Movement threshold for swipe detection";
          };

          commands = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
            description = "Gesture command mappings";
            example = {
              tap = "hyprctl dispatch togglespecialworkspace";
              swipeLeft = "playerctl previous";
              swipeRight = "playerctl next";
              swipeUp = "hyprctl dispatch workspace m-1";
              swipeDown = "hyprctl dispatch workspace m+1";
            };
          };
        };

        scroll = {
          focusPollMs = lib.mkOption {
            type = lib.types.int;
            default = 200;
            description = "How often to poll for active window focus in milliseconds";
          };

          rules = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule {
              options = {
                windowClassRegex = lib.mkOption {
                  type = lib.types.str;
                  description = "Regex pattern to match window class";
                  example = "firefox|chrome";
                };
                scrollRightCommands = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                  description = "Commands to execute on scroll right";
                };
                scrollLeftCommands = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                  description = "Commands to execute on scroll left";
                };
              };
            });
            default = [];
            description = "Scroll behavior rules per window class";
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
              --focus-poll-ms ${toString cfg.scroll.focusPollMs} \
              ${lib.optionalString (cfg.gesture.commands != {}) ''
              --gesture-commands '${builtins.toJSON {
                tap = cfg.gesture.commands.tap or "";
                swipe_left = cfg.gesture.commands.swipeLeft or "";
                swipe_right = cfg.gesture.commands.swipeRight or "";
                swipe_up = cfg.gesture.commands.swipeUp or "";
                swipe_down = cfg.gesture.commands.swipeDown or "";
              }}' \
            ''} \
              ${lib.optionalString (cfg.scroll.rules != []) ''
              --scroll-rules '${builtins.toJSON (map (r: {
                  window_class_regex = r.windowClassRegex;
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
