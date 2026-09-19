# Raspberry Pi 4 Moonlight NixOS

A minimal, reproducible NixOS appliance that boots a Raspberry Pi 4 directly
into [Moonlight Qt](https://github.com/moonlight-stream/moonlight-qt). It uses
EGLFS and KMS/DRM directly from `tty1`; no desktop environment, display manager,
X server, Wayland compositor, or audio server is installed.

The project is hardware-oriented but does not require a Raspberry Pi to
evaluate. Its first real-device boot and streaming tests are still pending.

## Features

- Direct-to-TTY Moonlight session with automatic restart
- Raspberry Pi OS FFmpeg patches for hardware HEVC decoding through `rpivid`
- HDMI video fixed to 1080p60 by default and direct ALSA HDMI audio
- Keyboard, mouse, standard USB gamepads, and common controller protocols
- DualSense support over USB and Bluetooth
- Ethernet DHCP by default, with optional static addressing
- Headless Wi-Fi setup with iwd
- Key-only SSH administration
- Cached Raspberry Pi vendor kernel and matching firmware
- Pi-specific Wi-Fi/Bluetooth firmware without the generic firmware bundle
- Flashable compressed SD-card image

## Build the default image

The image is an AArch64 Linux derivation. Build it on an AArch64 Linux host or
through an AArch64 Linux remote builder. Accept the flake configuration so Nix
can use the `nixos-raspberrypi` binary cache for the vendor kernel and firmware:

```console
nix --accept-flake-config build .#packages.aarch64-linux.sdImage
```

The kernel and firmware come from the maintained
[`nixos-raspberrypi`](https://github.com/nvmd/nixos-raspberrypi) project. Keep
this flake's `nixpkgs` input pinned to that project's Nixpkgs revision; changing
it can invalidate the cached kernel. FFmpeg is the only upstream package this
project customizes; Moonlight is built against that patched FFmpeg.

The result is a compressed `.img.zst`. Decompress it and write the resulting
`.img` with Raspberry Pi Imager, Etcher, or `dd`. Flashing replaces the target
card's partition table and data.

The default image uses hostname and username `moonlight`, obtains its
Ethernet address through DHCP, and has no SSH authorized keys. SSH is running,
but remote login is intentionally impossible until a key is supplied through a
custom configuration.

## Use as a flake input

Add the project as an input:

```nix
inputs.rpi4-moonlight = {
  url = "github:BenjaminPrice/rpi4-moonlight-nixos";
};
```

Do not make this input's `nixpkgs` follow a different parent input. The pinned
revision is what allows the Raspberry Pi kernel to come from its binary cache.
The consuming flake must also accept or configure the cache shown in this
repository's `nixConfig` when it builds the image.

The constructor produces a complete Raspberry Pi NixOS system while allowing
ordinary NixOS modules to override the defaults:

```nix
nixosConfigurations.streambox =
  inputs.rpi4-moonlight.lib.mkRaspberryPiMoonlight {
    modules = [
      {
        rpi4Moonlight = {
          hostName = "streambox";
          user.name = "operator";
          ssh.authorizedKeys = [
            "ssh-ed25519 AAAA... replace-with-your-public-key"
          ];

          network = {
            ethernet = {
              address = "192.0.2.22/24";
              gateway = "192.0.2.1";
              nameservers = [ "1.1.1.1" ];
            };
            wifi.countryCode = "US";
          };
        };
      }
    ];
  };
```

`192.0.2.0/24` is a documentation-only network; replace every example value.
Alternatively, import `inputs.rpi4-moonlight.nixosModules.default` into an
existing AArch64 NixOS definition. The module includes the Pi 4 hardware,
bootloader, Bluetooth, display, and SD-image support.

## Configuration

| Option | Default | Purpose |
| --- | --- | --- |
| `rpi4Moonlight.hostName` | `moonlight` | Appliance hostname |
| `rpi4Moonlight.user.name` | `moonlight` | Moonlight and SSH account |
| `rpi4Moonlight.ssh.authorizedKeys` | `[]` | Accepted SSH public keys |
| `rpi4Moonlight.network.ethernet.address` | `null` | Static CIDR address; null uses DHCP |
| `rpi4Moonlight.network.ethernet.gateway` | `null` | Static default gateway |
| `rpi4Moonlight.network.ethernet.nameservers` | `[]` | Explicit DNS servers |
| `rpi4Moonlight.network.wifi.enable` | `true` | Enable iwd and Wi-Fi DHCP |
| `rpi4Moonlight.network.wifi.countryCode` | `null` | Wireless regulatory domain |
| `rpi4Moonlight.bluetooth.enable` | `true` | Bluetooth controller support |
| `rpi4Moonlight.display.mode` | `1920x1080@60` | Forced HDMI display mode |
| `rpi4Moonlight.display.audioDevice` | `sysdefault:CARD=vc4hdmi0` | ALSA output |

## Administration

Moonlight owns `tty1`. Inspect or restart it over SSH:

```console
sudo journalctl -u moonlight -b
sudo systemctl restart moonlight
```

Configure Wi-Fi without a local UI:

```console
sudo iwctl
station wlan0 scan
station wlan0 get-networks
station wlan0 connect SSID
```

Pair a Bluetooth controller with `sudo bluetoothctl`. The `input`, `video`,
`render`, and `audio` permissions required by gamepads, DRM, and ALSA are already
assigned to the Moonlight account.

## Hardware decoding checks

On the Pi, verify that the kernel exposes media/video devices and that the
custom FFmpeg contains the Raspberry Pi facilities:

```console
ls -l /dev/media* /dev/video*
ffmpeg -buildconf 2>&1 | grep -E 'enable-(sand|v4l2-request)'
ffmpeg -hwaccels | grep drm
```

An independent HEVC decode test can be run with:

```console
ffmpeg -hwaccel drm -vcodec hevc -i sample-hevc.mkv -f null -
```

Confirm Moonlight's selected decoder with `journalctl -u moonlight -b` while a
stream is active.

## Why a patched FFmpeg?

The Raspberry Pi 4 HEVC decoder uses the stateless V4L2 Request API and
Broadcom SAND pixel layouts. Generic nixpkgs FFmpeg supports V4L2 M2M but does
not currently contain the complete Pi HEVC path. This project applies Raspberry
Pi OS Trixie's latest FFmpeg patch set only to Moonlight's FFmpeg dependency;
it does not globally replace FFmpeg for a consuming system.

## License

The Nix configuration is available under the MIT License. Packaged software
retains its own upstream licenses.
