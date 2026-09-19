{
  config,
  lib,
  pkgs,
  rpi-ffmpeg-debian,
  ...
}:

let
  cfg = config.rpi4Moonlight;
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optional
    optionals
    types
    ;

  rpiFfmpeg = pkgs.callPackage ../packages/ffmpeg-rpi.nix {
    inherit rpi-ffmpeg-debian;
  };
  moonlight = pkgs.moonlight-qt.override { ffmpeg = rpiFfmpeg; };
in
{
  options.rpi4Moonlight = {
    enable = mkEnableOption "the Raspberry Pi 4 Moonlight appliance" // {
      default = true;
    };

    hostName = mkOption {
      type = types.str;
      default = "moonlight";
      description = "Hostname assigned to the appliance.";
    };

    user = {
      name = mkOption {
        type = types.str;
        default = "moonlight";
        description = "Local account that owns the Moonlight session.";
      };

      uid = mkOption {
        type = types.int;
        default = 1000;
        description = "UID of the Moonlight account.";
      };
    };

    ssh = {
      enable = mkEnableOption "key-only SSH administration" // {
        default = true;
      };

      authorizedKeys = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          SSH public keys accepted by the Moonlight account. Password login is
          always disabled; an empty list leaves SSH running but inaccessible.
        '';
      };
    };

    network = {
      ethernet = {
        matchName = mkOption {
          type = types.str;
          default = "en* eth*";
          description = "systemd-networkd interface-name match for Ethernet.";
        };

        address = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "192.0.2.22/24";
          description = "Static Ethernet address in CIDR notation; null enables DHCP.";
        };

        gateway = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "192.0.2.1";
          description = "Optional default gateway used with a static address.";
        };

        nameservers = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "1.1.1.1" ];
          description = "Optional DNS servers; DHCP-provided DNS is used when empty.";
        };
      };

      wifi = {
        enable = mkEnableOption "headless Wi-Fi configuration through iwd" // {
          default = true;
        };

        countryCode = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "US";
          description = "Optional ISO 3166-1 alpha-2 wireless regulatory domain.";
        };
      };

      mdns = mkEnableOption "mDNS discovery with Avahi" // {
        default = true;
      };
    };

    bluetooth.enable = mkEnableOption "Bluetooth controller support" // {
      default = true;
    };

    display = {
      connector = mkOption {
        type = types.str;
        default = "HDMI-A-1";
        description = "Kernel DRM connector used for Moonlight output.";
      };

      mode = mkOption {
        type = types.str;
        default = "1920x1080@60";
        description = "Display mode forced on the local HDMI output.";
      };

      audioDevice = mkOption {
        type = types.str;
        default = "sysdefault:CARD=vc4hdmi0";
        description = "ALSA device used for HDMI audio.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.network.ethernet.address != null || cfg.network.ethernet.gateway == null;
          message = "rpi4Moonlight.network.ethernet.gateway requires a static address";
        }
      ];

      warnings = optional (cfg.ssh.enable && cfg.ssh.authorizedKeys == [ ]) ''
        rpi4Moonlight.ssh is enabled without authorizedKeys; remote logins will
        be rejected until at least one public key is configured.
      '';

      networking.hostName = cfg.hostName;
      networking.useDHCP = false;
      networking.useNetworkd = true;
      networking.firewall.enable = true;

      system.stateVersion = "26.05";

      # The vendor kernel, firmware and U-Boot setup come from nixos-hardware.
      # Qt draws through EGLFS and SDL presents frames directly through KMS/DRM;
      # no X server, Wayland compositor or display manager is installed.
      hardware.raspberry-pi."4".fkms-3d = {
        enable = true;
        cma = 512;
      };
      hardware.graphics.enable = true;
      hardware.enableRedistributableFirmware = true;

      boot.kernelParams = [
        "video=${cfg.display.connector}:${cfg.display.mode}"
        "quiet"
        "loglevel=3"
        "vt.global_cursor_default=0"
      ]
      ++ optional (
        cfg.network.wifi.countryCode != null
      ) "cfg80211.ieee80211_regdom=${cfg.network.wifi.countryCode}";
      boot.consoleLogLevel = 3;

      boot.kernelModules = [
        "hid-nintendo"
        "hid-playstation"
        "hid-sony"
        "uhid"
        "usbhid"
        "xpad"
      ];
      services.udev.packages = [ pkgs.game-devices-udev-rules ];

      hardware.bluetooth = {
        enable = cfg.bluetooth.enable;
        powerOnBoot = cfg.bluetooth.enable;
        settings = {
          General = {
            ControllerMode = "dual";
            FastConnectable = true;
          };
          Policy.AutoEnable = true;
        };
      };

      systemd.network = {
        enable = true;
        networks."10-wired" = {
          matchConfig.Name = cfg.network.ethernet.matchName;
          address = optional (cfg.network.ethernet.address != null) cfg.network.ethernet.address;
          routes = optional (cfg.network.ethernet.gateway != null) {
            Gateway = cfg.network.ethernet.gateway;
          };
          networkConfig = {
            DHCP = if cfg.network.ethernet.address == null then "yes" else "no";
            MulticastDNS = cfg.network.mdns;
          }
          // lib.optionalAttrs (cfg.network.ethernet.nameservers != [ ]) {
            DNS = cfg.network.ethernet.nameservers;
          };
        };
      };

      networking.nameservers = cfg.network.ethernet.nameservers;
      networking.wireless.iwd = {
        enable = cfg.network.wifi.enable;
        settings.General.EnableNetworkConfiguration = false;
      };

      services.resolved.enable = true;
      services.avahi = {
        enable = cfg.network.mdns;
        nssmdns4 = cfg.network.mdns;
        publish = {
          enable = cfg.network.mdns;
          addresses = cfg.network.mdns;
        };
      };

      users.mutableUsers = false;
      # The default image deliberately has no embedded credential. This
      # acknowledges NixOS's lockout assertion without enabling password login.
      # Configure at least one SSH public key for remote administration.
      users.allowNoPasswordLogin = cfg.ssh.authorizedKeys == [ ];
      users.users.${cfg.user.name} = {
        isNormalUser = true;
        inherit (cfg.user) uid;
        home = "/home/${cfg.user.name}";
        createHome = true;
        hashedPassword = "!";
        extraGroups = [
          "audio"
          "input"
          "render"
          "video"
          "wheel"
        ];
        openssh.authorizedKeys.keys = cfg.ssh.authorizedKeys;
      };
      security.sudo.wheelNeedsPassword = false;

      services.openssh = {
        enable = cfg.ssh.enable;
        openFirewall = cfg.ssh.enable;
        settings = {
          KbdInteractiveAuthentication = false;
          PasswordAuthentication = false;
          PermitRootLogin = "no";
        };
      };

      services.xserver.enable = false;
      services.pulseaudio.enable = false;
      fonts.packages = [ pkgs.dejavu_fonts ];

      systemd.services.moonlight = {
        description = "Moonlight streaming appliance";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network.target"
          "systemd-user-sessions.service"
        ]
        ++ optional cfg.bluetooth.enable "bluetooth.target";
        conflicts = [ "getty@tty1.service" ];
        environment = {
          AUDIODEV = cfg.display.audioDevice;
          DRM_FORCE_DIRECT = "1";
          QT_QPA_PLATFORM = "eglfs";
          QT_QPA_EGLFS_ALWAYS_SET_MODE = "1";
          SDL_AUDIODRIVER = "alsa";
          SDL_VIDEODRIVER = "kmsdrm";
        };
        serviceConfig = {
          ExecStart = lib.getExe moonlight;
          PAMName = "login";
          Restart = "always";
          RestartSec = 2;
          StandardInput = "tty-force";
          StandardOutput = "journal";
          StandardError = "journal";
          SupplementaryGroups = [
            "audio"
            "input"
            "render"
            "video"
          ];
          TTYPath = "/dev/tty1";
          TTYReset = true;
          TTYVHangup = true;
          TTYVTDisallocate = true;
          User = cfg.user.name;
          WorkingDirectory = config.users.users.${cfg.user.name}.home;
        };
      };

      environment.systemPackages = [
        pkgs.libdrm
        moonlight
        rpiFfmpeg
      ]
      ++ optionals cfg.bluetooth.enable [ pkgs.bluez ]
      ++ optionals cfg.network.wifi.enable [ pkgs.iwd ];

      documentation = {
        enable = false;
        info.enable = false;
        man.enable = false;
        nixos.enable = false;
      };
      programs.command-not-found.enable = false;
      nix.gc.automatic = true;
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
    }

    (mkIf cfg.network.wifi.enable {
      systemd.network.networks."20-wireless" = {
        matchConfig.Name = "wl*";
        networkConfig = {
          DHCP = "yes";
          MulticastDNS = cfg.network.mdns;
        };
        linkConfig.RequiredForOnline = false;
      };
    })
  ]);
}
