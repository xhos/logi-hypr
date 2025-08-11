{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];
    forEach = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
  in {
    packages = forEach (pkgs: let
      inherit (pkgs) rustPlatform pkg-config;
    in {
      default = rustPlatform.buildRustPackage {
        pname = "logi-hypr";
        version = "0.1.0";
        src = self;
        cargoLock.lockFile = ./Cargo.lock;
        nativeBuildInputs = [pkg-config];
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

      execArgs = let
        base = [
          "${cfg.package}/bin/logi-hypr"
          "--tap-timeout-ms"
          (toString cfg.gesture.tapTimeoutMs)
          "--movement-threshold"
          (toString cfg.gesture.movementThreshold)
          "--focus-poll-ms"
          (toString cfg.scroll.focusPollMs)
        ];

        gestureJson = lib.optional (cfg.gesture.commands != {}) [
          "--gesture-commands"
          (builtins.toJSON {
            tap = cfg.gesture.commands.tap or "";
            swipe_left = cfg.gesture.commands.swipeLeft or "";
            swipe_right = cfg.gesture.commands.swipeRight or "";
            swipe_up = cfg.gesture.commands.swipeUp or "";
            swipe_down = cfg.gesture.commands.swipeDown or "";
          })
        ];

        scrollJson = lib.optional (cfg.scroll.rules != []) [
          "--scroll-rules"
          (builtins.toJSON (map (r: {
              window_class_regex = r.windowClassRegex;
              scroll_right_commands = r.scrollRightCommands;
              scroll_left_commands = r.scrollLeftCommands;
            })
            cfg.scroll.rules))
        ];
      in
        base ++ lib.concatLists gestureJson ++ lib.concatLists scrollJson ++ cfg.extraArgs;
    in {
      options.programs.logi-hypr = {
        enable = lib.mkEnableOption "Logitech gesture support for Hyprland (flags only)";

        package = lib.mkOption {
          type = lib.types.package;
          default = defaultPackage;
          description = "package for logi-hypr";
        };

        extraPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [];
          example = lib.literalExpression "[ pkgs.playerctl pkgs.hyprland pkgs.xdotool ]";
          description = "Extra packages added to PATH for commands invoked by logi-hypr.";
        };

        extraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Additional CLI flags to pass through verbatim.";
        };

        service.enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable the user-level systemd service.";
        };

        gesture = {
          tapTimeoutMs = lib.mkOption {
            type = lib.types.int;
            default = 200;
          };
          movementThreshold = lib.mkOption {
            type = lib.types.int;
            default = 100;
          };
          commands = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
            description = "Gesture command map: tap, swipeLeft, swipeRight, swipeUp, swipeDown.";
          };
        };

        scroll = {
          focusPollMs = lib.mkOption {
            type = lib.types.int;
            default = 200;
          };
          rules = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule {
              options = {
                windowClassRegex = lib.mkOption {type = lib.types.str;};
                scrollRightCommands = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                };
                scrollLeftCommands = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                };
              };
            });
            default = [];
          };
        };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [cfg.package];

        systemd.user.services.logi-hypr = lib.mkIf cfg.service.enable {
          description = "logi-hypr (gesture daemon for Hyprland)";
          wantedBy = ["graphical-session.target"];
          partOf = ["graphical-session.target"];

          path = cfg.extraPackages;

          serviceConfig = {
            Type = "simple";
            ExecStart = lib.escapeShellArgs execArgs;
            Restart = "on-failure";
          };
        };
      };
    };

    devShells = forEach (pkgs: {
      default = pkgs.mkShell {packages = with pkgs; [cargo rustc pkg-config];};
    });
  };
}
