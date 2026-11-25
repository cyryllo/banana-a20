## Banana Pi Pro: Armbian 26.11.3 test report

- Board: LeMaker Banana Pi Pro (A20, 1 GB), powered over micro USB
- Image: `Armbian_26.11.3_Bananapipro_resolute_current_6.18.65_xfce_desktop.img.xz` from fi.mirror.armbian.de/incoming/igorpecovnik/bananapipro/archive/ (Ubuntu 26.04, XFCE, kernel 6.18.65-current-sunxi, U-Boot 2026.07, build `0bf4c8e96`)
- Minimal (CLI) image: `Armbian_26.11.3_Bananapipro_resolute_current_6.18.65_minimal.img.xz`, same checks: 25 pass, 0 fail, 2 warnings (4 kernel log lines of the same kinds, the same 2 `mmc` lines), 4 skipped (Ethernet cable, SATA disk, USB stick, HDMI picture question); HDMI console fine, no simpledrm issue without X
- Date: 2026-11-25
- Tested with: `test-bananapipro.sh --minimalny` (automatic release checklist) and manual checks
- Result: **both images ready for release**, with one desktop issue on HDMI without a panel (below, workaround known)

### Required checks (automatic, HDMI only, default `overlays=`)

| Result | Area | Details |
|---|---|---|
| ✅ | Board, image | LeMaker Banana Pro, Armbian 26.11.3 resolute, kernel 6.18.65 |
| ✅ | Services | running, no failed units; boot 1 min 6 s |
| ⚠️ | Kernel log | 6 lines err or worse: `simple-framebuffer already registered` (2x), `Unsupported infoframe type 129/131` (HDMI, 2x), `brcmf_p2p ... timeout` (Wi-Fi P2P, not used); no functional effect |
| ✅ | Memory, temperature, CPU | 960 MB; 34 C idle; ondemand 528-960 MHz, 2 cores |
| ✅ | SD card | write 8.5 MB/s, read 23 MB/s; 2 `mmc` error lines in dmesg at boot, no errors afterwards |
| ✅ | USB | keyboard and mouse work |
| ✅ | Wi-Fi | brcmfmac, scan OK, connected (-52 dBm), 20 pings to the gateway, 0% loss |
| ✅ | Network | gateway and DNS OK |
| ✅ | HDMI | monitor detected, 1920x1080 (with the workaround below) |
| ✅ | Audio | sun4icodec and sun4ihdmi cards present |
| ✅ | Load | 60 s on both cores: max 39 C, no throttling (960 MHz), lowest supply 5.27 V (AXP209 ADC), no new kernel errors |
| ✅ | Packages | linux-image-current-sunxi 26.11.3, dpkg/apt consistent |
| ➖ | Ethernet | `end0` and PHY RTL8211E detected; link not tested (no cable at hand) |
| ➖ | SATA, USB storage | AHCI driver loaded; no disk / stick at hand |

### Issue found: black screen on HDMI when X starts (no LCD panel)

With HDMI only, U-Boot and the console show on the monitor, but it goes black when LightDM/Xorg starts. Cause: `CONFIG_DRM_SUN4I=y` binds at 0.5 s, `CONFIG_DRM_SIMPLEDRM=m` loads from the initramfs at 2.8 s and takes the U-Boot framebuffer, so there are two KMS devices and Xorg picks simpledrm as the primary screen. Same in `linux-sunxi-{legacy,current,edge}.config`, so it likely affects all 32-bit sunxi desktop images on HDMI without a panel. Details and logs: ISSUE_LINK.

Workaround, tested on this board (the picture comes back):

```bash
echo "blacklist simpledrm" | sudo tee /etc/modprobe.d/blacklist-simpledrm.conf
sudo update-initramfs -u
sudo reboot
```

### Optional checks

| Result | Area | Details |
|---|---|---|
| ✅ | LeMaker 7" LCD | `overlays=lemaker-lcd7`: picture OK, LVDS 1024x600, confirmed by the tester |
| ✅ | LCD touch | FT5x06 found at boot (retry patch), touch confirmed by the tester; `vcc-supply` present in all three LeMaker overlays (wake by touch, #11337) |
| ✅ | Board LEDs | blue and green LEDs found and blinked |
| ✅ | IR receiver, POWER button | `sunxi-ir` (rc0) and `axp20x-pek` found |
| ✅ | GPIO | 16 free header pins pass the pull-up/pull-down test (pins used by I2C, UART and SPI not touched) |

Note: with an LCD panel and an HDMI monitor at the same time, the HDMI picture needs `overlays=lemaker-lcd7-hdmi` and `extraargs=video=HDMI-A-1:1920x1080@60`, because the LCD and HDMI share PLL3 (documented behaviour).
