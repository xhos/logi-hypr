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
    buildInputs = with pkgs; [wayland wayland-protocols libxkbcommon];
  };

  configFile = pkgs.writeText "logi-hypr.toml" ''
    [gesture]
    threshold = ${toString cfg.threshold}

    [gesture.commands]
    tap = "${cfg.commands.tap}"
    up = "${cfg.commands.up}"
    down = "${cfg.commands.down}"
    left = "${cfg.commands.left}"
    right = "${cfg.commands.right}"

    [scroll]
    default_action = "native"

    [scroll.applications]
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (app: action: "${app} = \"${action}\"") cfg.scrollApps)}
  '';
in {
  options.programs.logi-hypr = {
    enable = lib.mkEnableOption "logitech gesture handler";

    threshold = lib.mkOption {
      type = lib.types.float;
      default = 50.0;
      description = "movement threshold for gestures";
    };

    commands = {
      tap = lib.mkOption {
        type = lib.types.str;
        default = "hyprctl dispatch exec wofi";
        description = "command for tap gesture";
      };

      up = lib.mkOption {
        type = lib.types.str;
        default = "hyprctl dispatch workspace +1";
        description = "command for up gesture";
      };

      down = lib.mkOption {
        type = lib.types.str;
        default = "hyprctl dispatch workspace -1";
        description = "command for down gesture";
      };

      left = lib.mkOption {
        type = lib.types.str;
        default = "hyprctl dispatch movetoworkspace -1";
        description = "command for left gesture";
      };

      right = lib.mkOption {
        type = lib.types.str;
        default = "hyprctl dispatch movetoworkspace +1";
        description = "command for right gesture";
      };
    };

    scrollApps = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        spotify = "volume";
        gimp = "zoom";
      };
      description = "per-app scroll behaviors";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [logi-hypr];

    systemd.user.services.logi-hypr = {
      description = "logitech gesture handler";
      wantedBy = ["graphical-session.target"];

      serviceConfig = {
        ExecStart = "${logi-hypr}/bin/logi-hypr --config ${configFile}";
        Restart = "on-failure";
      };
    };

    users.groups.input = {};
  };
}
