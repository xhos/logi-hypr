# logi-hypr

I got myself an mx master 3s and didn't find any good ways to bind it's gestures and per app horizontal scrolling on nixos w/ hyprland, so here we are. the gesture button is hardcoded to the gesture button on my mouse (277). user has to be in the input group to use it.

## usage

add the flake to your inputs:

```nix
{
  inputs.logi-hypr.url = "github:xhos/logi-hypr";
}
```

### nixos

```nix
{inputs, ...}: {
  imports = [inputs.logi-hypr.nixosModules.default];

  programs.logi-hypr = {
    enable = true;

    gesture.commands = {
      tap = "hyprctl dispatch togglespecialworkspace";
      left = "playerctl --player=spotify previous";
      right = "playerctl --player=spotify next";
      up = "hyprctl dispatch workspace m-1";
      down = "hyprctl dispatch workspace m+1";
    };

    scroll.rules = [
      {
        window = "Spotify";
        scrollRightCommands = [
          "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"
        ];
        scrollLeftCommands = [
          "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ];
      }
      {
        window = "firefox|chrome|chromium|zen";
        scrollRightCommands = ["wtype -M ctrl -k Tab"];
        scrollLeftCommands = ["wtype -M ctrl -M shift -k Tab"];
      }
    ];
  };
}
```

### home manager

```nix
{inputs, ...}: {
  imports = [inputs.logi-hypr.homeManagerModules.default];

  programs.logi-hypr = {
    enable = true;

    gesture.commands = {
      tap = "hyprctl dispatch togglespecialworkspace";
      left = "playerctl --player=spotify previous";
      right = "playerctl --player=spotify next";
      up = "hyprctl dispatch workspace m-1";
      down = "hyprctl dispatch workspace m+1";
    };

    scroll.rules = [
      {
        window = "Spotify";
        scrollRightCommands = [
          "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"
        ];
        scrollLeftCommands = [
          "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ];
      }
      {
        window = "firefox|chrome|chromium|zen";
        scrollRightCommands = ["wtype -M ctrl -k Tab"];
        scrollLeftCommands = ["wtype -M ctrl -M shift -k Tab"];
      }
    ];
  };
}
```

## run

you can choose how to make it run in the background using your preferred method. for example you can add it to you exec-once in the hyprland config:

```nix
wayland.windowManager.hyprland.settings.exec-once = ["logi-hypr-run"];
```
