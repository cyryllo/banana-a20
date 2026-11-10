# LeMaker LCD panels for Banana Pro on current kernels

Ready-to-use Armbian images (Debian 13 trixie, kernel 6.18) for the **LeMaker Banana Pro** with working **LeMaker LCD panels and touch**. Fork of [LeMaker/fex_configuration](https://github.com/LeMaker/fex_configuration), whose old `script.bin` files only work with the sunxi 3.4 kernel.

| Panel | Display | Touch |
|---|---|---|
| 7" LVDS 1024x600 | ✅ tested, also together with HDMI (`lemaker-lcd7-hdmi`) | ✅ tested |
| 5" RGB 800x480 | ✅ tested, also together with HDMI 1920x1080 | driver and overlay checked (correct coordinates), full test pending: the test panel has a cracked touch glass |
| 3.5" RGB 320x240 | not tested (no hardware) | same controller as 7" |

The images also work on the original Banana Pi (non-"Pro").

**Also in this repository:**

| Folder | Project |
|---|---|
| [gpio/](gpio/README.md) | **GPIO**: pinout of the 40-pin header, WiringBP (C, `gpio readall`) and LMK.GPIO (Python, RPi.GPIO API) fixed for the current kernel, libgpiod, examples |
| [arkada20/](arkada20/README.md) | **Arkada20**: retro game console image (RetroArch without a desktop, like Lakka) for a handheld or an arcade cabinet |

**Official Armbian support is on the way.** The touch driver, the touch fix and the panel overlays are submitted to Armbian: [#11293](https://github.com/armbian/build/pull/11293), [#11294](https://github.com/armbian/build/pull/11294), [#11296](https://github.com/armbian/build/pull/11296). The images here are built from the official Armbian build framework with these three changes, so they work exactly like the official Armbian images will once the changes are merged.

## Quick start (recommended)

1. Download an image from [Releases](https://github.com/cyryllo/fex_configuration/releases):
   - **`..._xfce_desktop.img.xz`**: XFCE desktop, 7" panel enabled (`lemaker-lcd7`, for use without an HDMI monitor)
   - **`..._minimal.img.xz`**: no desktop, LCD disabled (HDMI only), a base for your own setup
2. Write it to an SD card with [USBImager](https://gitlab.com/bztsrc/usbimager) or balenaEtcher.
3. Connect the panel, insert the card, power on. The LCD shows a picture once the kernel starts (U-Boot messages are on HDMI only).

## Choosing the panel

The panel is chosen by the `overlays=` line in `/boot/armbianEnv.txt` (`sudo nano /boot/armbianEnv.txt`, then `sudo reboot`):

```
overlays=lemaker-lcd7
```

| Value | Panel |
|---|---|
| `lemaker-lcd5` | 5" RGB, also together with HDMI |
| `lemaker-lcd7` | 7" LVDS without HDMI (64 Hz) |
| `lemaker-lcd7-hdmi` | 7" LVDS for use with HDMI (about 50 Hz) |

Use only one `lemaker-lcd...` value at a time. Other overlays can stay on the same line, separated by spaces. To turn the LCD off, remove the `lemaker-lcd...` value (or the whole line if nothing else is on it).

The 3.5" panel is not in the images (no hardware to test it), see [Manual installation](#manual-installation-on-an-existing-armbian).

`/boot` is on the ext4 system partition, so it cannot be edited from Windows. Boot once with HDMI (or SSH) to switch the panel.

## Screen settings

**Brightness** (0 = off, 255 = maximum, 200 after the first boot):

```bash
cat /sys/class/backlight/*/brightness                 # current value
echo 120 | sudo tee /sys/class/backlight/*/brightness  # set it
```

systemd stores the last value and restores it at the next boot. On the XFCE desktop you can also use the brightness slider of the power manager panel plugin. Only the backlight off: `echo 0 | sudo tee /sys/class/backlight/*/brightness`.

**HDMI resolution with the LCD on:** keep HDMI at 1920x1080 or 1280x720 (see below), set by the `extraargs=` line in `/boot/armbianEnv.txt`, e.g. `extraargs=video=HDMI-A-1:1280x720@60`.

**Turning HDMI off** (LCD only): `sudo armbian-add-overlay overlays/bananapro-disable-hdmi.dts` from a clone of this repository, then reboot. It adds `user_overlays=bananapro-disable-hdmi`, remove that line to turn HDMI back on.

## LCD and HDMI at the same time

If the LCD works without HDMI but flickers when an HDMI monitor is connected, both outputs fight over a shared clock (see [How it works](#how-it-works)). Two fixes:

- **Use LCD and HDMI together:** on the 7" use `overlays=lemaker-lcd7-hdmi` (refresh ~50 Hz instead of 64 Hz), the 5" (`lemaker-lcd5`) already works. HDMI must run at **1920x1080 or 1280x720**: add `extraargs=video=HDMI-A-1:1920x1080@60` to `/boot/armbianEnv.txt`, and on the desktop pick one of these two modes for HDMI too.
- **No HDMI needed:** turn HDMI off, see [Screen settings](#screen-settings).

## Problems

| Symptom | Fix |
|---|---|
| LCD flickers only with HDMI connected | See [LCD and HDMI at the same time](#lcd-and-hdmi-at-the-same-time) |
| Backlight works in reverse | In the overlay change `pwms = <&pwm 0 50000 0>;` to `... 1>;` |
| 5"/3.5": colour noise | Add `pixelclk-active = <0>;` or `<1>;` to `panel-timing` |
| Touch mirrored or axes swapped | Add `touchscreen-inverted-x;`, `-inverted-y;` or `touchscreen-swapped-x-y;` to `touchscreen@38` |
| Touch or the panel stopped after `apt upgrade` | Until the Armbian changes are merged, the official kernel has no touch driver and no `lemaker-lcd...` overlays: `sudo apt-mark hold linux-image-current-sunxi linux-dtb-current-sunxi` |

To change an overlay, take its source from `overlays/` in this repository (the same settings as `lemaker-lcd...`), edit it, run `sudo armbian-add-overlay <file>.dts`, remove the `lemaker-lcd...` value from `overlays=` and reboot.

Reports are welcome in the [Armbian forum thread](https://forum.armbian.com/topic/7233-bananapi-pro-7-touchlcd-with-debian-buster-and-mainline-kernel-5xxxx/) or as GitHub issues. Please include:

```bash
dmesg | grep -iE "sun4i|lvds|panel|edt|pwm|i2c-2"
grep -A1 -i edt /proc/bus/input/devices
```

---

## Technical details

### Repository contents

| Path | Contents |
|---|---|
| `overlays/` | Device Tree overlays for the 3.5", 5" and 7" panels, the 7" variant for use with HDMI (`lcd7-hdmi`) and `bananapro-disable-hdmi` |
| `armbian-build/` | Scripts to build the images yourself (`zbuduj-obraz-pr.sh`: official Armbian + the three Armbian PRs, used for the images since v0.6; `zbuduj-obraz.sh`: older images with `lemaker-lcd`), see [armbian-build/README.md](armbian-build/README.md) |
| `arkada20/` | **Arkada20**: a retro game console image (RetroArch without a desktop, like Lakka) for the Banana Pro with a LeMaker LCD, see [arkada20/README.md](arkada20/README.md) |
| `gpio/` | **GPIO**: pinout, WiringBP, LMK.GPIO, libgpiod, examples, see [gpio/README.md](gpio/README.md) |
| `stare jądro sunxi 3.4/` | Original LeMaker `fex`/`bin` files for the old 3.4 kernel, kept as the source of the parameters |

### Manual installation on an existing Armbian

Requires Armbian `current` (6.18) for the Banana Pro (`bananapipro`, DTB `sun7i-a20-bananapro.dtb`) and `device-tree-compiler`.

```bash
git clone https://github.com/cyryllo/fex_configuration.git
cd fex_configuration

# overlays for all panels + panel switch command
for f in overlays/bananapro-*.dts; do sudo armbian-add-overlay "$f"; done
sudo install -m 0755 armbian-build/lemaker-lcd /usr/local/sbin/
sudo lemaker-lcd 7        # your panel; also removes the other overlays added above

sudo reboot
```

**Touch driver:** Armbian does not build `edt-ft5x06` (`CONFIG_TOUCHSCREEN_EDT_FT5X06`). The ready-made images include it. On a stock Armbian build it as an external module:

```bash
sudo apt install build-essential linux-headers-current-sunxi
mkdir ~/ft5x06 && cd ~/ft5x06
wget https://raw.githubusercontent.com/torvalds/linux/v6.18/drivers/input/touchscreen/edt-ft5x06.c
echo 'obj-m += edt-ft5x06.o' > Makefile
make -C /lib/modules/$(uname -r)/build M=$PWD modules
sudo make -C /lib/modules/$(uname -r)/build M=$PWD modules_install
sudo depmod -a
```

Rebuild it after every kernel update. Replace `v6.18` with your kernel version if different.

This unpatched driver fails at boot (see [How it works](#how-it-works)). Either apply the patch from this repository to `edt-ft5x06.c` before `make`:

```bash
patch -p4 < ~/fex_configuration/armbian-build/userpatches/kernel/archive/sunxi-6.18/edt-ft5x06-retry-identify-after-bus-recovery.patch
```

or install the retry service, which binds the driver again after boot:

```bash
sudo install -m 0755 armbian-build/lemaker-touch-retry /usr/local/sbin/
sudo install -m 0644 armbian-build/lemaker-touch-retry.service /etc/systemd/system/
sudo systemctl enable lemaker-touch-retry.service
```

### How it works

- **Display:** all panels use TCON0 (`&tcon0_out` endpoint 0), panel power on PH12, backlight PWM0 (PB2) with enable PH8. Only one panel overlay can be active.
- **7" LVDS:** the A20 TCON only switches to LVDS mode when the panel is `compatible = "panel-lvds"` (`vesa-24`, 55 MHz, 1024x600; `lcd7-hdmi`: 42.429 MHz).
- **5" RGB:** generic `panel-dpi` with timings in the overlay (29.7 MHz, 800x480; the fex file had 30 MHz).
- **3.5" RGB:** `lemaker,bl035-rgb-002` from the kernel's `panel-simple`, no timings in the overlay.
- **Touch:** FocalTech FT5x06 on I2C3 (PI0/PI1, address 0x38, IRQ PH9), identified as `generic ft5x06 (79)`. The fex pin `ctp_wakeup` (PH7) is the active-low RESET line, so it is `reset-gpios = <&pio 7 7 1>` (the driver then waits 300 ms for the controller). At boot the first I2C transfer to the controller always fails with a bus error (`mv64xxx ... Ctlr Error status 0x0`), the adapter recovers the bus and returns -EAGAIN. Neither powering the controller from PH12 (`vcc-supply`) nor holding PH7 high from early boot (`gpio-hog`) helps. The images carry a small kernel patch that makes `edt-ft5x06` retry the identification once (`identification failed, retrying` in `dmesg`). Without it, bind the driver again by hand: `echo 2-0038 | sudo tee /sys/bus/i2c/drivers/edt_ft5x06/bind`.
- **LCD + HDMI:** the outputs share no pins, but in `ccu-sun4i-a10.c` the clocks `tcon0-ch0-sclk`, `tcon1-ch1-sclk2` and `hdmi` have the same parents (PLL3 `pll-video0` first) and `CLK_SET_RATE_PARENT`. When booting with HDMI, the LCD sets PLL3 for itself, then HDMI moves it to 297 MHz while the LCD divider stays the same, so the LCD pixel clock goes wrong (`clk_rate_exclusive_get` in `sun4i_tcon.c` only locks the rate when the channel is enabled, too late). The fix is an LCD clock derived from the same 297 MHz: 5" 29.7 MHz = 297 / 10 (`sun4i_tcon_dclk` takes the first exact divider, from 4 up, and for 29.7 MHz that is 10); 7" LVDS has a fixed divider of 7, so 42.429 MHz × 7 = 297.003 MHz, which `ccu_mult` rounds down to 297 MHz. HDMI uses 297 MHz only in 1080p and 720p. A cleaner long-term fix would be to keep TCON0 on `pll-video1`.
- **Panel switching:** U-Boot ignores lines starting with `#` in `armbianEnv.txt`; `lemaker-lcd` keeps one active `user_overlays=` line and leaves non-LeMaker overlays untouched.

### fex to Device Tree timing conversion

- `hback-porch = lcd_hbp - lcd_hspw`, `vback-porch = lcd_vbp - lcd_vspw` (fex back porches include the sync pulse)
- `vtotal = lcd_vt / 2` (fex stores a doubled value)
- `hfront-porch = lcd_ht - lcd_x - lcd_hbp`, `vfront-porch = lcd_vt/2 - lcd_y - lcd_vbp`

Per-panel calculations are in the comments of the overlay files.

### Sources

- Original LeMaker repository: <https://github.com/LeMaker/fex_configuration>
- Armbian overlays: <https://docs.armbian.com/User-Guide_Armbian_overlays/>
- Armbian build framework: <https://docs.armbian.com/build-framework/getting-started/>
