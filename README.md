**English** | [Polski](README.pl.md)

# banana-a20: LeMaker Banana Pro on current Linux

Projects that bring the **LeMaker Banana Pro** (and the original Banana Pi, both with the Allwinner A20) back to life on a current system: Armbian with Debian 13 and the mainline kernel.

LeMaker made the Banana Pro, its LCD panels and add-on boards around 2014-2015. The company is gone, and its software (the `script.bin` files, the touch driver, the GPIO libraries) only worked with the old sunxi 3.4 kernel. This repository collects everything needed to use the boards and panels today.

| Project | What it is | Status |
|---|---|---|
| [LeMaker LCD panels](#lemaker-lcd-panels) | the 5" and 7" touch panels on the mainline kernel, ready images | done, merged into official Armbian |
| [Arkada20](arkada20/README.md) | retro game console: the board boots straight into RetroArch, like Lakka | v1.0, tested with the 7" panel |
| [GPIO](gpio/README.md) | pinout, WiringBP (C, `gpio readall`) and LMK.GPIO (Python, RPi.GPIO API) fixed for the current kernel, lg (lgpio/rgpio) instead of pigpio, examples | done, tested on the board |

Ready images are on the [Releases](https://github.com/cyryllo/banana-a20/releases) page: `v0.x-...` for the LCD images, `arkada20-...` for the game console.

## LeMaker LCD panels

LeMaker made three touch panels for the Banana Pi/Pro: 3.5" (320x240), 5" (800x480) and 7" (1024x600), connected with a flat cable, touch included.

| Panel | Display | Touch |
|---|---|---|
| 7" LVDS 1024x600 | ✅ works, also together with HDMI | ✅ works |
| 5" RGB 800x480 | ✅ works, also together with HDMI | driver checked, full test pending (the test panel has a cracked touch glass) |
| 3.5" RGB 320x240 | not tested (no hardware) | same controller as 7" |

Everything also works on the original Banana Pi (non-"Pro").

### What was done

On the mainline kernel the panels stayed black: the kernel does not read `script.bin`. The panel settings from the old LeMaker `fex` files were rewritten as Device Tree overlays, and along the way three problems were solved:

- **touch did not start:** the first I2C transfer to the touch controller after power-on always fails; a small kernel patch makes the driver retry once, so touch works right after boot,
- **the LCD flickered with an HDMI monitor connected:** LCD and HDMI share one clock; the panel clocks were chosen so that both can run from it at the same time,
- **the 7" panel needs LVDS mode,** which the kernel only enables for a panel described as `panel-lvds`.

The work is now part of **official Armbian** (all three changes merged in November 2026):

- [armbian/build#11293](https://github.com/armbian/build/pull/11293): touch driver `edt-ft5x06` enabled in the kernel,
- [armbian/build#11294](https://github.com/armbian/build/pull/11294): the touch retry patch,
- [armbian/build#11296](https://github.com/armbian/build/pull/11296): overlays `lemaker-lcd5`, `lemaker-lcd7` and `lemaker-lcd7-hdmi`.

Technical details (how it works, timings, manual installation, changing an overlay): [overlays/README.md](overlays/README.md).

### Quick start

1. Download an image from [Releases](https://github.com/cyryllo/banana-a20/releases) (latest LCD release `v0.6`):
   - **`..._xfce_desktop.img.xz`**: XFCE desktop, 7" panel enabled,
   - **`..._minimal.img.xz`**: no desktop, LCD disabled (HDMI only), a base for your own setup.
2. Write it to an SD card with [USBImager](https://gitlab.com/bztsrc/usbimager) or balenaEtcher.
3. Connect the panel, insert the card, power on. The LCD shows a picture once the kernel starts (the first boot messages are on HDMI only).

Official Armbian images and kernels built from the merged changes work the same way. The official kernel package available in November 2026 (`linux-image-current-sunxi` 26.8.3) does not contain them yet, see [Problems](#problems) about kernel updates.

### Choosing the panel

The panel is chosen by the `overlays=` line in `/boot/armbianEnv.txt` (`sudo nano /boot/armbianEnv.txt`, then `sudo reboot`):

```
overlays=lemaker-lcd7
```

| Value | Panel |
|---|---|
| `lemaker-lcd5` | 5" RGB, also together with HDMI |
| `lemaker-lcd7` | 7" LVDS without HDMI (64 Hz) |
| `lemaker-lcd7-hdmi` | 7" LVDS for use with HDMI (about 50 Hz) |

Use only one `lemaker-lcd...` value at a time. Other overlays can stay on the same line, separated by spaces. To turn the LCD off, remove the `lemaker-lcd...` value. `sudo armbian-config` can switch overlays too.

`/boot` is on the Linux (ext4) partition, so it cannot be edited from Windows: boot once with an HDMI monitor or log in over SSH to switch the panel.

### LCD and HDMI at the same time

- **7":** use `overlays=lemaker-lcd7-hdmi`. The 5" (`lemaker-lcd5`) works with HDMI as it is.
- HDMI must run at **1920x1080 or 1280x720**: add `extraargs=video=HDMI-A-1:1920x1080@60` to `/boot/armbianEnv.txt`, and on the desktop pick one of these two modes for HDMI too.
- Without this, the LCD works but flickers when the HDMI monitor is connected.

### Screen settings

**Brightness** (0 = off, 255 = maximum, 200 after the first boot):

```bash
cat /sys/class/backlight/*/brightness                 # current value
echo 120 | sudo tee /sys/class/backlight/*/brightness  # set it
```

The last value is restored at the next boot. On the XFCE desktop the brightness slider of the power manager works too.

**Turning HDMI off** (LCD only): `sudo armbian-add-overlay overlays/bananapro-disable-hdmi.dts` from a copy of this repository, then reboot. It adds `user_overlays=bananapro-disable-hdmi`, remove that line to turn HDMI back on.

### Problems

| Symptom | What to do |
|---|---|
| LCD flickers only with HDMI connected | see [LCD and HDMI at the same time](#lcd-and-hdmi-at-the-same-time) |
| touch or the panel stopped after `apt upgrade` | the official kernel package does not have the LeMaker support yet; keep the kernel of the image: `sudo apt-mark hold linux-image-current-sunxi linux-dtb-current-sunxi` (undo with `apt-mark unhold` once a newer official kernel is out) |
| backlight works in reverse, colour noise, touch mirrored | small overlay changes, see [Changing an overlay](overlays/README.md#changing-an-overlay) |

Reports are welcome as GitHub issues or in the [Armbian forum thread](https://forum.armbian.com/topic/7233-bananapi-pro-7-touchlcd-with-debian-buster-and-mainline-kernel-5xxxx/). Please include:

```bash
dmesg | grep -iE "sun4i|lvds|panel|edt|pwm|i2c-2"
grep -A1 -i edt /proc/bus/input/devices
```

## Arkada20

A retro game console system for the Banana Pro with a LeMaker panel: a handheld with the 5" panel or an arcade cabinet with the 7" one. The board boots straight into RetroArch (NES, SNES, Game Boy, GBA, Mega Drive, PlayStation, arcade with MAME 2003-Plus and FBNeo...), Wi-Fi is set up in the menu, games are copied over the network. No games are included.

More: [arkada20/README.md](arkada20/README.md).

## GPIO

The 40-pin header of the Banana Pro, with the two LeMaker libraries working again on the current kernel: **WiringBP** (WiringPi for C, with `gpio readall`) and **LMK.GPIO** (RPi.GPIO for Python). pigpio cannot run on the A20, its successor **lg** (lgpio, rgpio) works instead: software PWM and servos on any pin, alerts, control over the network. Plus the standard Linux tools (libgpiod), a colour pinout and tested examples.

More: [gpio/README.md](gpio/README.md).

## Repository contents

| Folder | Contents |
|---|---|
| [`overlays/`](overlays/README.md) | Device Tree overlays for the LCD panels and their technical description |
| [`armbian-build/`](armbian-build/README.md) | scripts to build the images yourself |
| [`arkada20/`](arkada20/README.md) | the Arkada20 game console |
| [`gpio/`](gpio/README.md) | GPIO libraries, pinout, examples |
| `stare jądro sunxi 3.4/` | original LeMaker `fex`/`bin` files for the old 3.4 kernel, kept as the source of the panel parameters |

This repository started as a fork of [LeMaker/fex_configuration](https://github.com/LeMaker/fex_configuration).

The story behind it (in Polish): [Banana Pro po latach: ekrany LeMaker w Armbianie, konsola Arkada20 i GPIO](https://cyryllo.pl/blog/banana-pro-po-latach-ekrany-lemaker-arkada20-gpio/).
