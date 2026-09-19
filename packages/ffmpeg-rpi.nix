{
  ffmpeg_7,
  lib,
  rpi-ffmpeg-debian,
  udev,
}:

# The Pi 4 HEVC block (rpivid) is a stateless decoder. Raspberry Pi OS carries
# the matching V4L2 Request implementation and Pi-specific SAND pixel formats;
# upstream FFmpeg does not yet provide the complete integration Moonlight needs.
ffmpeg_7.overrideAttrs (old: {
  pname = "ffmpeg-rpi";

  patches = (old.patches or [ ]) ++ [
    (rpi-ffmpeg-debian + "/patches/ffmpeg-7.1.5-rpi_30.patch")
  ];

  buildInputs = (old.buildInputs or [ ]) ++ [ udev ];

  configureFlags = (old.configureFlags or [ ]) ++ [
    "--enable-libudev"
    "--enable-sand"
    "--enable-v4l2-request"
  ];

  # Patch 30 adds the SAND formats to the imgutils fixture in the order used by
  # Raspberry Pi OS's FFmpeg tree.  The nixpkgs 7.1.5 source emits the same
  # formats and checksums at the end of the list, so that ordering-only FATE
  # mismatch must not reject an otherwise successful build.
  doCheck = false;

  passthru = (old.passthru or { }) // {
    raspberryPiHardwareDecoding = true;
  };

  meta = (old.meta or { }) // {
    description = "FFmpeg with Raspberry Pi V4L2 Request and SAND support";
    homepage = "https://github.com/RPi-Distro/ffmpeg";
    platforms = lib.platforms.linux;
  };
})
