**English** | [Polski](README.pl.md)

# Bosman20: 3D printer host for the Banana Pro (Allwinner A20)

Bosman20 turns a LeMaker Banana Pro (Banana Pi Pro) with a LeMaker LCD panel into a ready 3D printer host: **Klipper**, **Moonraker**, **Mainsail** in the browser and **KlipperScreen** on the touchscreen. Write the image to an SD card, connect the printer board over USB, set up Wi-Fi with your finger and print.

It is built on Armbian (Debian 13 trixie, mainline kernel) with the LeMaker LCD support from this repository. Everything is installed with [KIAUH](https://github.com/dw-0/kiauh), the same way as by hand, so KIAUH updates and manages it later.

| What | Status |
|---|---|
| Klipper, Moonraker, Mainsail | installed with KIAUH; the same stack runs on the author's printers on a Banana Pro |
| KlipperScreen on the 7" panel | tested: picture and touch |
| 5" panel | works with the same overlay (`lemaker-lcd5`), smaller layout |
| Wake the screen by touch | see [Known issues](#known-issues) |

## First boot

1. Write the image to an SD card ([USBImager](https://gitlab.com/bztsrc/usbimager) or balenaEtcher), connect the 7" panel, power on.
2. KlipperScreen starts on the panel. It shows that Klipper is not ready until a printer is configured.
3. Wi-Fi: in KlipperScreen open **Network** and pick your network (or connect a network cable).
4. Open Mainsail in a browser: **http://bosman20.local** (or the IP address shown in KlipperScreen).
5. Connect the printer board over USB and edit `printer.cfg` in Mainsail (**Machine**), see [Configuring the printer](#configuring-the-printer).

There is no setup wizard. The account for SSH:

| User | Password |
|---|---|
| `bosman` | `bosman` |

You must choose a new password on the first SSH login (`ssh bosman@bosman20.local`). The `root` account has no password login, use `sudo`.

## Configuring the printer

The image contains an example `printer.cfg` that only has the host part. For your printer:

1. Take the configuration of your printer or board from Klipper (`~/klipper/config/printer-*.cfg` or `generic-*.cfg`) and copy it into `printer.cfg` in Mainsail.
2. Find the serial port of the board: `ls /dev/serial/by-id/` over SSH, put it into `[mcu] serial:`.
3. Build and flash the Klipper firmware for the board: `cd ~/klipper && make menuconfig && make` (the ARM and AVR compilers are already installed), then follow the instructions for your board.
4. Restart Klipper from Mainsail.

`printer.cfg` already includes `mainsail.cfg` (macros for Mainsail).

## Updates

- From Mainsail: **Machine → Update Manager** (Klipper, Moonraker, Mainsail, KlipperScreen).
- From SSH: `~/kiauh/kiauh.sh` (menu), or `~/kiauh/kiauh.sh update klipper` and so on.
- System packages: `sudo apt update && sudo apt upgrade`.

## Screen

The 7" panel is enabled. For the 5" panel change `overlays=lemaker-lcd7` to `overlays=lemaker-lcd5` in `/boot/armbianEnv.txt` (`sudo nano /boot/armbianEnv.txt`) and reboot. KlipperScreen turns the screen off after one hour without use; change the time in the KlipperScreen settings (screen power off time).

## Security

Mainsail and Moonraker have no password. Anyone in your local network can control the printer, as in other Klipper images. Do not make the printer reachable from the internet; for remote access use a VPN, or set up `[authorization]` in `moonraker.conf`.

## Known issues

- **Touch does not wake the dimmed screen.** When KlipperScreen turns the screen off, the kernel also cuts the power of the touch controller (it shares the panel supply), so touch cannot wake it. Workaround: set a longer blanking time or "never" in KlipperScreen. The fix (`vcc-supply` in the touch node) is tested and in the overlays of this repository; it will be in the next Bosman20 image and is proposed for Armbian.
- **Kernel updates**: until an official Armbian kernel with the LeMaker changes is out, `apt upgrade` may install a kernel without the panel support. Keep the kernel: `sudo apt-mark hold linux-image-current-sunxi linux-dtb-current-sunxi`.

## Building the image

On a Linux x86 computer with Docker (requirements: [../armbian-build/README.md](../armbian-build/README.md#requirements-the-computer-you-build-on)), from the main folder of the repository:

```bash
bosman20/zbuduj-pakiety-python.sh          # Python packages for armhf (about 20 min, once)
armbian-build/zbuduj-obraz-pr.sh --pulpit brak --ekran 7 --klipper
```

The image is `~/armbian-build/output/images/Bosman20_<date>_bananapipro_trixie_<kernel>.img`.

### How the build works

| File | What it does |
|---|---|
| `zbuduj-pakiety-python.sh` | builds the Python packages (wheels) of Klipper, Moonraker and KlipperScreen for armhf in an ARM container; on armhf many have no ready packages and piwheels is not always reachable |
| `customize-bosman20.sh` | runs inside the image while it is built: account, KIAUH install, NetworkManager, name `bosman20` |
| `instaluj-stos.sh` | the KIAUH commands (`install klipper`, `moonraker`, `mainsail`) and the KlipperScreen installer |
| `systemctl-budowanie` | stand-in `systemctl` for the build only: starting services is impossible without systemd, enabling them works |

Inside the image build the ARM programs run through QEMU emulation, where `sudo` cannot raise a normal user's rights. The installers therefore run as root with `HOME`, `USER` and `LOGNAME` of the `bosman` user, and the files get `bosman` as owner at the end. The result is the same layout as an install by hand.

## Licenses

Klipper (GPL v3), Moonraker (GPL v3), Mainsail (GPL v3), KlipperScreen (AGPL v3), KIAUH (GPL v3): the image installs them from their official repositories, the exact versions are listed in `/usr/local/share/bosman20-wersje.txt`.
