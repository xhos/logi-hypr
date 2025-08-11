{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.logi-hypr;

  logi-hypr = pkgs.rustPlatform.buildRustPackage {
    pname = "logi-hypr";
    version = "0.1.0";
    src = ./.;
    cargoLock.lockFile = ./Cargo.lock;

    nativeBuildInputs = [pkgs.pkg-config];
    buildInputs = [pkgs.systemd];
  };

  configFile = pkgs.writeText "logi-hypr.toml" ''
    [gesture]
    tap_timeout_ms = ${toString cfg.gesture.tapTimeoutMs}
    movement_threshold = ${toString cfg.gesture.movementThreshold}

    [gesture.commands]
    tap = "${cfg.gesture.commands.tap}"
    swipe_left = "${cfg.gesture.commands.swipeLeft}"
    swipe_right = "${cfg.gesture.commands.swipeRight}"
    swipe_up = "${cfg.gesture.commands.swipeUp}"
    swipe_down = "${cfg.gesture.commands.swipeDown}"

    [scroll]
    focus_poll_ms = ${toString cfg.scroll.focusPollMs}

    ${lib.concatMapStrings (rule: ''
        [[scroll.rules]]
        window_class_regex = "${rule.windowClassRegex}"
        scroll_right_commands = [${lib.concatMapStringsSep ", " (cmd: "\"${cmd}\"") rule.scrollRightCommands}]
        scroll_left_commands = [${lib.concatMapStringsSep ", " (cmd: "\"${cmd}\"") rule.scrollLeftCommands}]

      '')
      cfg.scroll.rules}
  '';
in {
  options.programs.logi-hypr = {
    enable = lib.mkEnableOption "logitech gesture handler";

    enableService = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "whether to enable the systemd user service";
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
        description = "movement threshold in pixels";
      };

      commands = {
        tap = lib.mkOption {
          type = lib.types.str;
          default = "hyprctl dispatch togglespecialworkspace";
        };

        swipeLeft = lib.mkOption {
          type = lib.types.str;
          default = "playerctl --player=spotify previous";
        };

        swipeRight = lib.mkOption {
          type = lib.types.str;
          default = "playerctl --player=spotify next";
        };

        swipeUp = lib.mkOption {
          type = lib.types.str;
          default = "hyprctl dispatch workspace m-1";
        };

        swipeDown = lib.mkOption {
          type = lib.types.str;
          default = "hyprctl dispatch workspace m+1";
        };
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
            };

            scrollLeftCommands = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
            };
          };
        });
        default = [
          {
            windowClassRegex = "Spotify";
            scrollRightCommands = ["wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"];
            scrollLeftCommands = ["wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"];
          }
          {
            windowClassRegex = "firefox|chrome|chromium|zen";
            scrollRightCommands = ["wtype -M ctrl -k Tab"];
            scrollLeftCommands = ["wtype -M ctrl -M shift -k Tab"];
          }
        ];
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [logi-hypr];

    systemd.user.services.logi-hypr = lib.mkIf cfg.enableService {
      description = "logitech gesture handler";
      wantedBy = ["graphical-session.target"];

      serviceConfig = {
        ExecStart = "${logi-hypr}/bin/logi-hypr --config ${configFile}";
        Restart = "on-failure";
        SupplementaryGroups = ["input"];
      };
    };

    users.groups.input = {};
  };
}
