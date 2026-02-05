# Ghostty terminal configuration
{ pkgs, ... }:
{
  lavi.ghostty.enable = true;

  programs.ghostty = {
    enable = true;

    settings = {
      command = "nu";
      font-family = "Pragmasevka Nerd Font";
      theme = "lavi";

      window-padding-x = 10;
      window-padding-y = 8;
      window-padding-balance = true;
      window-vsync = false;
      window-inherit-font-size = false;
      gtk-titlebar = false;

      shell-integration-features = "cursor,sudo,no-title";

      gtk-single-instance = false;
      linux-cgroup = "never";
      linux-cgroup-memory-limit = 1000000000;

      macos-non-native-fullscreen = true;
      macos-option-as-alt = false;

      keybind = [
        # fix alt+key
        "alt+one=text:\\u{001B}1"
        "alt+two=text:\\u{001B}2"
        "alt+three=text:\\u{001B}3"
        "alt+four=text:\\u{001B}4"
        "alt+five=text:\\u{001B}5"
        "alt+six=text:\\u{001B}6"
        "alt+seven=text:\\u{001B}7"
        "alt+eight=text:\\u{001B}8"
        "alt+nine=text:\\u{001B}9"
        "alt+zero=text:\\u{001B}0"
        "alt+a=text:\\u{001B}a"
        "alt+b=text:\\u{001B}b"
        "alt+c=text:\\u{001B}c"
        "alt+d=text:\\u{001B}d"
        "alt+e=text:\\u{001B}e"
        "alt+f=text:\\u{001B}f"
        "alt+g=text:\\u{001B}g"
        "alt+h=text:\\u{001B}h"
        "alt+i=text:\\u{001B}i"
        "alt+j=text:\\u{001B}j"
        "alt+k=text:\\u{001B}k"
        "alt+l=text:\\u{001B}l"
        "alt+m=text:\\u{001B}m"
        "alt+n=text:\\u{001B}n"
        "alt+o=text:\\u{001B}o"
        "alt+p=text:\\u{001B}p"
        "alt+q=text:\\u{001B}q"
        "alt+r=text:\\u{001B}r"
        "alt+s=text:\\u{001B}s"
        "alt+t=text:\\u{001B}t"
        "alt+u=text:\\u{001B}u"
        "alt+v=text:\\u{001B}v"
        "alt+w=text:\\u{001B}w"
        "alt+x=text:\\u{001B}x"
        "alt+y=text:\\u{001B}y"
        "alt+z=text:\\u{001B}z"
        "alt+backslash=text:\\u{001B}\\\\"
        "alt+slash=text:\\u{001B}/"
        "alt+left_bracket=text:\\u{001B}["
        "alt+right_bracket=text:\\u{001B}]"

        # fix alt+shift+key
        "alt+shift+a=text:\\u{001B}A"
        "alt+shift+b=text:\\u{001B}B"
        "alt+shift+c=text:\\u{001B}C"
        "alt+shift+d=text:\\u{001B}D"
        "alt+shift+e=text:\\u{001B}E"
        "alt+shift+f=text:\\u{001B}F"
        "alt+shift+g=text:\\u{001B}G"
        "alt+shift+h=text:\\u{001B}H"
        "alt+shift+i=text:\\u{001B}I"
        "alt+shift+j=text:\\u{001B}J"
        "alt+shift+k=text:\\u{001B}K"
        "alt+shift+l=text:\\u{001B}L"
        "alt+shift+m=text:\\u{001B}M"
        "alt+shift+n=text:\\u{001B}N"
        "alt+shift+o=text:\\u{001B}O"
        "alt+shift+p=text:\\u{001B}P"
        "alt+shift+q=text:\\u{001B}Q"
        "alt+shift+r=text:\\u{001B}R"
        "alt+shift+s=text:\\u{001B}S"
        "alt+shift+t=text:\\u{001B}T"
        "alt+shift+u=text:\\u{001B}U"
        "alt+shift+v=text:\\u{001B}V"
        "alt+shift+w=text:\\u{001B}W"
        "alt+shift+x=text:\\u{001B}X"
        "alt+shift+y=text:\\u{001B}Y"
        "alt+shift+z=text:\\u{001B}Z"
        "alt+shift+left_bracket=text:\\u{001B}["
        "alt+shift+right_bracket=text:\\u{001B}]"

        # fix ctrl+key
        "ctrl+a=text:\\u{0001}"
        "ctrl+b=text:\\u{0002}"
        "ctrl+c=text:\\u{0003}"
        "ctrl+d=text:\\u{0004}"
        "ctrl+e=text:\\u{0005}"
        "ctrl+f=text:\\u{0006}"
        "ctrl+g=text:\\u{0007}"
        "ctrl+h=text:\\u{0008}"
        "ctrl+i=text:\\u{0009}"
        "ctrl+j=text:\\u{000A}"
        "ctrl+k=text:\\u{000B}"
        "ctrl+l=text:\\u{000C}"
        "ctrl+m=text:\\u{000D}"
        "ctrl+n=text:\\u{000E}"
        "ctrl+o=text:\\u{000F}"
        "ctrl+p=text:\\u{0010}"
        "ctrl+q=text:\\u{0011}"
        "ctrl+r=text:\\u{0012}"
        "ctrl+s=text:\\u{0013}"
        "ctrl+t=text:\\u{0014}"
        "ctrl+u=text:\\u{0015}"
        "ctrl+v=text:\\u{0016}"
        "ctrl+w=text:\\u{0017}"
        "ctrl+x=text:\\u{0018}"
        "ctrl+y=text:\\u{0019}"
        "ctrl+z=text:\\u{001A}"

        # custom bindings
        "ctrl+shift+e=unbind"
        "alt+shift+n=new_window"
        "ctrl+plus=increase_font_size:1"
        "ctrl+minus=decrease_font_size:1"
        "ctrl+zero=reset_font_size"
        "ctrl+shift+r=reload_config"

        "alt+c=copy_to_clipboard"
        "alt+v=paste_from_clipboard"

        "ctrl+alt+shift+i=inspector:toggle"

        "ctrl+shift+q=text:\\u{FF01}"
        "ctrl+alt+shift+n=text:\\u{FF02}"
        "ctrl+alt+q=text:\\u{FF03}"
        "ctrl+alt+shift+q=text:\\u{FF04}"
        "ctrl+backslash=text:\\u{00F0}"
        "ctrl+shift+backslash=text:\\u{00F1}"
        "alt+shift+backslash=text:\\u{00F2}"
        "ctrl+alt+shift+backslash=text:\\u{00FF}"
        "ctrl+grave_accent=text:\\u{00F3}"
        "ctrl+shift+w=text:\\u{00F4}"
        "ctrl+shift+f=text:\\u{00F5}"
        "ctrl+shift+t=text:\\u{00F6}"
        "ctrl+shift+a=text:\\u{00F7}"
        "ctrl+apostrophe=text:\\u{00F8}"
        "ctrl+shift+p=csi:11;2~"
        "ctrl+shift+n=csi:12;2~"
        "ctrl+shift+period=text:\\u{00FA}"
        "ctrl+period=text:\\u{00FB}"
        "ctrl+shift+o=text:\\u{00FC}"
        "ctrl+shift+i=text:\\u{00FD}"
        "ctrl+slash=text:\\u{00D4}"
        "ctrl+alt+slash=text:\\u{00D5}"
        "ctrl+shift+slash=text:\\u{00D6}"
        "alt+shift+slash=text:\\u{00D7}"
        "ctrl+alt+shift+slash=text:\\u{00D8}"
        "alt+space=text:\\u{00D9}"
        "ctrl+alt+shift+s=text:\\u{00DA}"
        "alt+shift+comma=text:\\u{00db}"
        "ctrl+alt+a=text:\\u{00dc}"
        "alt+shift+plus=text:\\u{00dd}"
        "alt+shift+-=text:\\u{00de}"
        "ctrl+alt+shift+plus=text:\\u{00df}"
        "ctrl+alt+shift+-=text:\\u{00e0}"
        "ctrl+tab=text:\\u{00e1}"

        "ctrl+enter=csi:24~"
        "alt+enter=csi:25~"
        "alt+shift+tab=csi:23;5~"
        "ctrl+comma=csi:21;5~"
        "ctrl+alt+shift+j=csi:20;5~"
        "ctrl+alt+shift+k=csi:19;5~"
        "ctrl+alt+shift+u=csi:24;2~"

        "ctrl+alt+shift+h=text:\\u{00a4}"
        "ctrl+alt+shift+j=text:\\u{00a5}"
        "ctrl+alt+shift+k=text:\\u{00a6}"
        "ctrl+alt+shift+l=text:\\u{00a7}"
        "ctrl+alt+apostrophe=text:\\u{00a8}"
        "ctrl+alt+semicolon=text:\\u{00a9}"
        "ctrl+alt+shift+apostrophe=text:\\u{00b0}"
        "ctrl+alt+shift+semicolon=text:\\u{00b1}"
        "ctrl+alt+enter=text:\\u{00b2}"
        "ctrl+alt+one=text:\\u{00c1}"
        "ctrl+alt+two=text:\\u{00c2}"
        "ctrl+alt+three=text:\\u{00c3}"
        "ctrl+alt+four=text:\\u{00c4}"
        "ctrl+alt+five=text:\\u{00c5}"
        "ctrl+alt+six=text:\\u{00c6}"
        "ctrl+alt+seven=text:\\u{00c7}"
        "ctrl+alt+eight=text:\\u{00c8}"
        "ctrl+alt+nine=text:\\u{00c9}"
        "ctrl+shift+h=text:\\u{00d0}"
        "ctrl+shift+j=text:\\u{00d1}"
        "ctrl+shift+k=text:\\u{00d2}"
        "ctrl+shift+l=text:\\u{00d3}"
        "shift+enter=text:\\n"
      ];
    };
  };
}
