**English** | [Polski](README.pl.md)

# LeMaker screen (`lemaker-screen`)

A simple tool to set up the LeMaker LCD panels on the Banana Pi and Banana Pro with Armbian, without editing files or remembering overlay names:

- **choose the screen:** no LCD (HDMI only), 5", 7", 7" together with an HDMI monitor,
- **brightness** of the backlight,
- **touch reset**, when touch reacts on its own or stops reacting,
- **HDMI 1080p mode**, needed when the LCD and HDMI work together,
- status: which screen is configured, which one works now, whether a reboot is needed.

Two front ends: a **window** (menu → Settings → **LeMaker screen**) and **commands** (`lemaker-screen`), also on images without a desktop and over SSH. In English; Polish with `--lang=pl` or `LEMAKER_SCREEN_LANG=pl`.

The tool uses the overlays that are in official Armbian since November 2026 (`lemaker-lcd5`, `lemaker-lcd7`, `lemaker-lcd7-hdmi`). On an older Armbian, update the system first: `sudo apt update && sudo apt full-upgrade`. The 3.5" panel is not on the list because it is not in Armbian (by hand: [overlays/README.md](../overlays/README.md)).

## Installation

On the board:

```bash
sudo apt install ./lemaker-screen_1.0.0_all.deb
```

The window needs `python3-gi`, `gir1.2-gtk-3.0` and `pkexec`, which the XFCE desktop image already has (`apt` installs what is missing). Without a desktop only the commands are used.

## Window

Menu → Settings → **LeMaker screen** (or the command `lemaker-screen-gui`):

| Part | What it does |
|---|---|
| Screen | choose the screen from the list and click **Apply**; the system asks for the password, then whether to reboot (the new screen works after a reboot). Below the list: which screen works now |
| Brightness | the slider works right away, no password |
| Touch | whether the touch controller works; **Reset**: the controller calibrates again |
| HDMI | whether a monitor is connected; **1920x1080**: force the HDMI mode needed for LCD + HDMI |

Tooltips explain the buttons. The window is about 470×250 pixels, so it fits on the 5" panel too.

## Commands

```bash
lemaker-screen                        # current settings
sudo lemaker-screen set 7             # 7" screen (5, 7, 7-hdmi or off)
sudo lemaker-screen set 5 --reboot    # 5" screen and reboot right away
lemaker-screen brightness 60          # brightness 60 %
lemaker-screen brightness +10         # 10 points brighter (-10 darker)
sudo lemaker-screen touch-reset       # reset touch
sudo lemaker-screen hdmi-1080p on     # HDMI 1920x1080 (on or off)
lemaker-screen --help                 # help
```

| Screen | Command | Notes |
|---|---|---|
| no LCD | `set off` | HDMI only |
| 5" RGB 800x480 | `set 5` | also works with HDMI, turns on HDMI 1080p mode |
| 7" LVDS 1024x600 | `set 7` | without an HDMI monitor, 64 Hz |
| 7" LVDS with HDMI | `set 7-hdmi` | with an HDMI monitor, 50 Hz, turns on HDMI 1080p mode |

## What exactly it changes

- In `/boot/armbianEnv.txt` it sets the `lemaker-lcd...` overlay in the `overlays=` line. Other overlays, e.g. `pwm` or `spi-spidev`, stay.
- It removes old `user_overlays=bananapro-lemaker-lcd...` from images made before November 2026, because two screen overlays at once break the boot.
- With 5" and 7"-HDMI it adds `video=HDMI-A-1:1920x1080@60` to `extraargs=`, because the LCD and HDMI share one clock and without it the LCD flickers.
- Before every change it makes a backup: `/boot/armbianEnv.txt.lemaker-screen.bak`.
- Brightness is changed through logind (no password, in the session on the board) or directly as root. The value comes back after a reboot.
- Touch reset unbinds and binds the `edt_ft5x06` driver, which sends a RESET pulse to the controller.

## Building the package

```bash
./zbuduj-deb.sh        # result: dist/lemaker-screen_<version>_all.deb
```

For tests without a board you can point it to a fake root directory: `LEMAKER_SCREEN_ROOT=/path python3 lemaker_screen.py`.

## License

GPL-3.0-or-later.
