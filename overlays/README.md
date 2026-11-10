# LeMaker LCD panels: technical details

How the LeMaker LCD panels work on the mainline kernel, how the overlays were made and how to install or change them by hand. For normal use see the [main README](../README.md#lemaker-lcd-panels).

## Files

| File | Panel | Connector | Resolution | Kernel panel driver |
|---|---|---|---|---|
| `bananapro-lemaker-lcd35.dts` | 3.5" BL035-RGB-002 | RGB | 320x240 | `lemaker,bl035-rgb-002` (panel-simple) |
| `bananapro-lemaker-lcd5.dts` | 5" | RGB | 800x480 | `panel-dpi`, timings in the overlay |
| `bananapro-lemaker-lcd7.dts` | 7" | LVDS | 1024x600 | `panel-lvds`, `vesa-24` |
| `bananapro-lemaker-lcd7-hdmi.dts` | 7" for use with HDMI | LVDS | 1024x600 | as above, 42.429 MHz |
| `bananapro-disable-hdmi.dts` | turns HDMI off | | | |

These are the sources of the `lemaker-lcd...` overlays that are now in Armbian (`sun7i-a20-lemaker-lcd5/lcd7/lcd7-hdmi`, [armbian/build#11296](https://github.com/armbian/build/pull/11296)). The 3.5" overlay is only here, it was never tested (no hardware). Only one panel overlay can be active at a time (they share TCON0, the pins and the touch address).

## How it works

- **Display:** all panels use TCON0 (`&tcon0_out` endpoint 0), panel power on PH12, backlight PWM0 (PB2) with enable PH8.
- **7" LVDS:** the A20 TCON only switches to LVDS mode when the panel is `compatible = "panel-lvds"` (`vesa-24`, 55 MHz, 1024x600; `lcd7-hdmi`: 42.429 MHz).
- **5" RGB:** generic `panel-dpi` with timings in the overlay (29.7 MHz, 800x480; the fex file had 30 MHz).
- **3.5" RGB:** `lemaker,bl035-rgb-002` from the kernel's `panel-simple`, no timings in the overlay.
- **Touch:** FocalTech FT5x06 on I2C3 (PI0/PI1, address 0x38, IRQ PH9), identified as `generic ft5x06 (79)`. The fex pin `ctp_wakeup` (PH7) is the active-low RESET line, so it is `reset-gpios = <&pio 7 7 1>` (the driver then waits 300 ms for the controller). At boot the first I2C transfer to the controller always fails with a bus error (`mv64xxx ... Ctlr Error status 0x0`), the adapter recovers the bus and returns -EAGAIN. Neither powering the controller from PH12 (`vcc-supply`) nor holding PH7 high from early boot (`gpio-hog`) helps. A small kernel patch makes `edt-ft5x06` retry the identification once (`identification failed, retrying` in `dmesg`), merged in Armbian as [armbian/build#11294](https://github.com/armbian/build/pull/11294). Without it, bind the driver again by hand: `echo 2-0038 | sudo tee /sys/bus/i2c/drivers/edt_ft5x06/bind`.
- **LCD + HDMI:** the outputs share no pins, but in `ccu-sun4i-a10.c` the clocks `tcon0-ch0-sclk`, `tcon1-ch1-sclk2` and `hdmi` have the same parents (PLL3 `pll-video0` first) and `CLK_SET_RATE_PARENT`. When booting with HDMI, the LCD sets PLL3 for itself, then HDMI moves it to 297 MHz while the LCD divider stays the same, so the LCD pixel clock goes wrong (`clk_rate_exclusive_get` in `sun4i_tcon.c` only locks the rate when the channel is enabled, too late). The fix is an LCD clock derived from the same 297 MHz: 5" 29.7 MHz = 297 / 10 (`sun4i_tcon_dclk` takes the first exact divider, from 4 up, and for 29.7 MHz that is 10); 7" LVDS has a fixed divider of 7, so 42.429 MHz × 7 = 297.003 MHz, which `ccu_mult` rounds down to 297 MHz. HDMI uses 297 MHz only in 1080p and 720p. A cleaner long-term fix would be to keep TCON0 on `pll-video1`.
- **Panel switching in the older images (up to v0.5):** U-Boot ignores lines starting with `#` in `armbianEnv.txt`; `lemaker-lcd` keeps one active `user_overlays=` line and leaves non-LeMaker overlays untouched.

## fex to Device Tree timing conversion

The parameters come from the original LeMaker `fex` files (in [`stare jądro sunxi 3.4/`](../stare%20jądro%20sunxi%203.4/)).

- `hback-porch = lcd_hbp - lcd_hspw`, `vback-porch = lcd_vbp - lcd_vspw` (fex back porches include the sync pulse)
- `vtotal = lcd_vt / 2` (fex stores a doubled value)
- `hfront-porch = lcd_ht - lcd_x - lcd_hbp`, `vfront-porch = lcd_vt/2 - lcd_y - lcd_vbp`

| Panel | Pixel clock | Horizontal (active/front/back/sync) | Vertical | Refresh |
|---|---|---|---|---|
| 5" | 29.7 MHz | 800/40/48/40 | 480/13/3/29 | ~61 Hz |
| 7" | 55 MHz | 1024/170/50/100 | 600/15/10/10 | ~64 Hz |
| 3.5" | 7 MHz (panel-simple) | htotal 408 | vtotal 262 | |

Per-panel calculations are in the comments of the overlay files.

## Manual installation on an existing Armbian

Only needed for the 3.5" panel, for an Armbian kernel without the LeMaker support, or to try changed overlays. Requires Armbian `current` (6.18) for the Banana Pro (`bananapipro`, DTB `sun7i-a20-bananapro.dtb`) and `device-tree-compiler`.

```bash
git clone https://github.com/cyryllo/banana-a20.git
cd banana-a20

# overlays for all panels + panel switch command
for f in overlays/bananapro-*.dts; do sudo armbian-add-overlay "$f"; done
sudo install -m 0755 armbian-build/lemaker-lcd /usr/local/sbin/
sudo lemaker-lcd 7        # your panel; also removes the other overlays added above

sudo reboot
```

**Touch driver:** older Armbian kernels do not build `edt-ft5x06` (`CONFIG_TOUCHSCREEN_EDT_FT5X06`, enabled by [armbian/build#11293](https://github.com/armbian/build/pull/11293)). Build it as an external module:

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

The unpatched driver fails at boot (see [How it works](#how-it-works)). Either apply the patch from this repository to `edt-ft5x06.c` before `make`:

```bash
patch -p4 < ~/banana-a20/armbian-build/userpatches/kernel/archive/sunxi-6.18/edt-ft5x06-retry-identify-after-bus-recovery.patch
```

or install the retry service, which binds the driver again after boot:

```bash
sudo install -m 0755 armbian-build/lemaker-touch-retry /usr/local/sbin/
sudo install -m 0644 armbian-build/lemaker-touch-retry.service /etc/systemd/system/
sudo systemctl enable lemaker-touch-retry.service
```

## Changing an overlay

Take the source from this folder (the same settings as `lemaker-lcd...`), edit it, run `sudo armbian-add-overlay <file>.dts`, remove the `lemaker-lcd...` value from `overlays=` in `/boot/armbianEnv.txt` and reboot. Typical changes:

| Symptom | Change in the overlay |
|---|---|
| Backlight works in reverse (0 = brightest) | `pwms = <&pwm 0 50000 0>;` → `... 1>;` |
| 5"/3.5": colour noise | add `pixelclk-active = <0>;` or `<1>;` to `panel-timing` |
| Touch mirrored or axes swapped | add `touchscreen-inverted-x;`, `touchscreen-inverted-y;` or `touchscreen-swapped-x-y;` to `touchscreen@38` |

## Testing overlays without the board

```bash
# Device tree sources from mainline (only the needed folders)
git clone --depth 1 --filter=blob:none --sparse https://github.com/torvalds/linux.git lnx
cd lnx && git sparse-checkout set --no-cone '/arch/arm/boot/dts/allwinner/' '/include/dt-bindings/'

# Base DTB with symbols (-@)
D=arch/arm/boot/dts/allwinner
cpp -nostdinc -I include -I $D -undef -x assembler-with-cpp $D/sun7i-a20-bananapro.dts > /tmp/bp.pre
dtc -@ -I dts -O dtb -o /tmp/bp.dtb /tmp/bp.pre

# Compile and apply an overlay (graph_port / graph_child_address warnings are harmless)
dtc -@ -I dts -O dtb -o /tmp/lcd5.dtbo ../overlays/bananapro-lemaker-lcd5.dts
fdtoverlay -i /tmp/bp.dtb -o /tmp/bp_lcd5.dtb /tmp/lcd5.dtbo && echo OK
```

The overlays use no `#include` or macros, because `armbian-add-overlay` compiles them with plain `dtc -@`.

## Sources

- Original LeMaker repository: <https://github.com/LeMaker/fex_configuration>
- Armbian overlays: <https://docs.armbian.com/User-Guide_Armbian_overlays/>
- Armbian build framework: <https://docs.armbian.com/build-framework/getting-started/>
