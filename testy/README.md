**English** | [Polski](README.pl.md)

# Testing Armbian images on the Banana Pi Pro

The board maintainer's checklist for testing Armbian images on the Banana Pi Pro (LeMaker Banana Pro, Allwinner A20) before a release, with a script that does most of it by itself.

Armbian asks the maintainer to sign off that the board is tested and ready for the release ([board maintainer rules](https://docs.armbian.com/contribute/board-maintainer/)). The images prepared for a release are in https://fi.mirror.armbian.de/incoming/igorpecovnik/ and https://rsync.armbian.com/incoming/ . Something not working is normal: what matters is that it is documented and reported.

## Script

On the board, with the test image written to the SD card:

```bash
wget https://raw.githubusercontent.com/cyryllo/banana-a20/master/testy/test-bananapipro.sh
chmod +x test-bananapipro.sh
sudo ./test-bananapipro.sh
```

| Option | What it does |
|---|---|
| (none) | automatic checks, then a few questions (picture, touch, sound) |
| `--bez-pytan` | automatic checks only, e.g. over SSH without a screen |
| `--aktualizacja` | first `apt update` and `apt full-upgrade`, then the test |

The output goes to the home directory:

- `raport-bananapipro-<date>.md`: the report in English (Markdown), ready to paste into the Armbian forum or a GitHub issue,
- `raport-bananapipro-<date>-szczegoly.txt`: full `dmesg`, lists of devices, display modes and packages (for bug reports).

At the end the script asks whether to upload the system log with `armbianmonitor -u` (a public link on paste.armbian.com, added to the report). The script writes nothing to SATA and USB disks: the speed tests only read. On the SD card it writes a 64 MB file and deletes it right away. The questions on the board are in Polish.

## Checklist

A = the script checks it, Q = the script asks, M = manually.

| Area | What | How |
|---|---|---|
| Boot | the minimal (CLI) image boots | M: run the script on that image |
| Boot | the desktop (XFCE) image boots | M: run the script on that image |
| System | board, image version, kernel, overlays | A |
| System | no failed service (`systemctl --failed`), boot time | A |
| System | kernel errors in `dmesg`, temperature, CPU frequency | A |
| SD card | write and read speed, `mmc` errors in `dmesg` | A |
| SATA | disk detected, read speed | A (when a disk is connected) |
| USB | devices on the ports, USB stick read speed | A (when connected) |
| USB | keyboard and mouse work | Q |
| Ethernet | 1000 Mb/s link, IP address | A |
| Wi-Fi | interface, driver, network scan | A |
| Network | gateway answers, DNS works | A |
| HDMI | monitor detected, display mode | A |
| HDMI | picture is correct | Q |
| LeMaker panels | overlay, panel in the device tree, backlight, touch driver, touch supply (`vcc-supply`) | A |
| LeMaker panels | picture is correct | Q |
| LeMaker panels | touch: 5 taps = 5 touches (counted from the input device) | A + Q |
| LeMaker panels | touch wakes the blanked screen (desktop) | Q |
| LeMaker panels | every overlay: `lemaker-lcd5`, `lemaker-lcd7`, `lemaker-lcd7-hdmi` with an HDMI monitor | M: change `overlays=`, reboot, run the script again |
| Desktop | menu, windows, file manager work smoothly | Q |
| Audio | sound cards | A |
| Audio | headphone output (test tone in both channels), HDMI audio | Q |
| Packages | dpkg/apt state, kernel version, held packages | A |
| Upgrade | `apt full-upgrade` from the previous release, reboot, everything works | M: `--aktualizacja`, reboot, run the script again |
| Power | `sudo reboot` and `sudo poweroff` work | M |

## After the test

- Everything works: sign off the board in the release testing form (linked from the [board maintainer rules](https://docs.armbian.com/contribute/board-maintainer/)) or post on the forum with the report.
- Something does not work: open an issue in [armbian/build](https://github.com/armbian/build/issues) with the report, the details file and the `armbianmonitor -u` link. Armbian treats these as most important: the image does not boot, corrupt packages, SD card or eMMC not working as expected. Wi-Fi, Bluetooth, GPIO and overlays have a lower priority.
