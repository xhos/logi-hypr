{
  description = "Logi-gesture: Logitech device gesture support for Hyprland";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

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
    # Package outputs
    packages = forAllSystems (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      logi-gesture = pkgs.rustPlatform.buildRustPackage {
        pname = "logi-gesture";
        version = "0.1.0";
        src = self;
        cargoLock.lockFile = ./Cargo.lock;
        nativeBuildInputs = with pkgs; [pkg-config];

        meta = with pkgs.lib; {
          description = "Logitech device gesture support for Hyprland";
          homepage = "https://github.com/xhos/logi-hypr";
          license = licenses.mit; # or whatever license you use
          platforms = platforms.linux;
        };
      };

      default = self.packages.${system}.logi-gesture;
    });

    # NixOS Module
    nixosModules = {
      logi-hypr = {
        config,
        lib,
        pkgs,
        ...
      }: let
        cfg = config.programs.logi-hypr;
        packageName = "logi-gesture";
        package = self.packages.${pkgs.stdenv.hostPlatform.system}.${packageName};
      in {
        options.programs.logi-hypr = {
          enable = lib.mkEnableOption "Logitech gesture support for Hyprland";

          package = lib.mkOption {
            type = lib.types.package;
            default = package;
            description = "The logi-gesture package to use";
          };

          enableService = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable the logi-gesture systemd service";
          };

          gesture = lib.mkOption {
            type = lib.types.submodule {
              options = {
                tapTimeoutMs = lib.mkOption {
                  type = lib.types.int;
                  default = 200;
                  description = "Tap timeout in milliseconds";
                };

                movementThreshold = lib.mkOption {
                  type = lib.types.int;
                  default = 100;
                  description = "Movement threshold for gestures";
                };

                commands = lib.mkOption {
                  type = lib.types.attrsOf lib.types.str;
                  default = {};
                  description = "Gesture commands mapping";
                  example = {
                    tap = "hyprctl dispatch togglespecialworkspace";
                    swipeLeft = "playerctl --player=spotify previous";
                    swipeRight = "playerctl --player=spotify next";
                  };
                };
              };
            };
            default = {};
            description = "Gesture configuration";
          };

          scroll = lib.mkOption {
            type = lib.types.submodule {
              options = {
                focusPollMs = lib.mkOption {
                  type = lib.types.int;
                  default = 200;
                  description = "Focus polling interval in milliseconds";
                };

                rules = lib.mkOption {
                  type = lib.types.listOf (lib.types.submodule {
                    options = {
                      windowClassRegex = lib.mkOption {
                        type = lib.types.str;
                        description = "Window class regex pattern";
                      };

                      scrollRightCommands = lib.mkOption {
                        type = lib.types.listOf lib.types.str;
                        default = [];
                        description = "Commands for scroll right";
                      };

                      scrollLeftCommands = lib.mkOption {
                        type = lib.types.listOf lib.types.str;
                        default = [];
                        description = "Commands for scroll left";
                      };
                    };
                  });
                  default = [];
                  description = "Scroll rules configuration";
                };
              };
            };
            default = {};
            description = "Scroll configuration";
          };
        };

        config = lib.mkIf cfg.enable {
          # Install the package
          environment.systemPackages = [cfg.package];

          # Generate config file
          environment.etc."logi-gesture/config.toml" = {
            text = ''
              [gesture]
              tap_timeout_ms = ${toString cfg.gesture.tapTimeoutMs}
              movement_threshold = ${toString cfg.gesture.movementThreshold}

              ${lib.optionalString (cfg.gesture.commands != {}) ''
                [gesture.commands]
                ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: ''${name} = "${value}"'') cfg.gesture.commands)}
              ''}

              [scroll]
              focus_poll_ms = ${toString cfg.scroll.focusPollMs}

              ${lib.concatStringsSep "\n" (lib.imap0 (i: rule: ''
                  [[scroll.rules]]
                  window_class_regex = "${rule.windowClassRegex}"
                  scroll_right_commands = [${lib.concatMapStringsSep ", " (cmd: ''"${cmd}"'') rule.scrollRightCommands}]
                  scroll_left_commands = [${lib.concatMapStringsSep ", " (cmd: ''"${cmd}"'') rule.scrollLeftCommands}]
                '')
                cfg.scroll.rules)}
            '';
          };

          # Systemd service
          systemd.services.logi-gesture = lib.mkIf cfg.enableService {
            description = "Logitech gesture daemon for Hyprland";
            wantedBy = ["graphical-session.target"];
            partOf = ["graphical-session.target"];
            after = ["graphical-session.target"];

            serviceConfig = {
              Type = "simple";
              ExecStart = "${cfg.package}/bin/logi-gesture --config /etc/logi-gesture/config.toml";
              Restart = "on-failure";
              RestartSec = "5s";

              # Security hardening
              DynamicUser = true;
              SupplementaryGroups = ["input"];
              DeviceAllow = ["/dev/input/event* rw"];
              DevicePolicy = "closed";

              # Capabilities needed for input devices
              CapabilityBoundingSet = ["CAP_DAC_OVERRIDE"];
              AmbientCapabilities = ["CAP_DAC_OVERRIDE"];

              # Additional hardening
              NoNewPrivileges = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              ProtectKernelTunables = true;
              ProtectKernelModules = true;
              ProtectControlGroups = true;
            };

            environment = {
              DISPLAY = ":0";
              WAYLAND_DISPLAY = "wayland-0";
            };
          };

          # Udev rules for device access
          services.udev.extraRules = ''
            # Logitech devices
            SUBSYSTEM=="input", ATTRS{idVendor}=="046d", MODE="0664", GROUP="input"
            SUBSYSTEM=="hidraw", ATTRS{idVendor}=="046d", MODE="0664", GROUP="input"
          '';

          # Ensure input group exists
          users.groups.input = {};
        };
      };

      default = self.nixosModules.logi-hypr;
    };

    # Development shell
    devShells = forAllSystems (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      default = pkgs.mkShell {
        packages = with pkgs; [
          cargo
          rustc
          pkg-config
          clippy
          rustfmt
        ];
      };
    });

    # Overlay for easy integration
    overlays.default = final: prev: {
      logi-gesture = self.packages.${final.system}.logi-gesture;
    };
  };
}
