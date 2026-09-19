{
  description = "Minimal NixOS Moonlight appliance for Raspberry Pi 4";

  nixConfig = {
    extra-substituters = [ "https://nixos-raspberrypi.cachix.org" ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  inputs = {
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";

    # Keep Nixpkgs aligned with nixos-raspberrypi so its vendor kernel and
    # firmware match the published binary cache.
    nixpkgs.follows = "nixos-raspberrypi/nixpkgs";

    # Raspberry Pi OS carries the V4L2 Request and Broadcom SAND support
    # required by the Pi 4's rpivid HEVC decoder. Pin the exact Debian source
    # package rather than the RPi-Distro Git branch, which currently lags it.
    rpi-ffmpeg-debian = {
      url = "https://archive.raspberrypi.com/debian/pool/main/f/ffmpeg/ffmpeg_7.1.5-0+deb13u1+rpt2.debian.tar.xz";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixos-raspberrypi,
      rpi-ffmpeg-debian,
      ...
    }:
    let
      applianceModule = {
        imports = [
          nixos-raspberrypi.nixosModules.raspberry-pi-4.base
          nixos-raspberrypi.nixosModules.raspberry-pi-4.display-vc4
          nixos-raspberrypi.nixosModules.raspberry-pi-4.bluetooth
          nixos-raspberrypi.nixosModules.sd-image
          ./modules/appliance.nix
        ];

        _module.args = {
          inherit nixos-raspberrypi rpi-ffmpeg-debian;
        };
      };

      mkRaspberryPiMoonlight =
        {
          modules ? [ ],
          specialArgs ? { },
        }:
        nixos-raspberrypi.lib.nixosSystem {
          inherit nixpkgs;
          system = "aarch64-linux";
          inherit specialArgs;
          modules = [ applianceModule ] ++ modules;
        };

      defaultSystem = mkRaspberryPiMoonlight { };
    in
    {
      lib = { inherit mkRaspberryPiMoonlight; };

      nixosModules.default = applianceModule;
      nixosModules.rpi4-moonlight = applianceModule;

      # The default image uses DHCP and generic account settings. Use the module
      # or constructor above to add SSH keys and site-specific configuration.
      nixosConfigurations.default = defaultSystem;

      packages.aarch64-linux = {
        default = defaultSystem.config.system.build.sdImage;
        sdImage = defaultSystem.config.system.build.sdImage;
      };

      checks.aarch64-linux.default = defaultSystem.config.system.build.toplevel;

      formatter = nixpkgs.lib.genAttrs [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ] (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };
}
