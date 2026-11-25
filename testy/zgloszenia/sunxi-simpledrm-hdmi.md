**Title:** sunxi (32-bit): desktop image goes black on HDMI when X starts: simpledrm (module) binds after the built-in sun4i-drm and stays

### Setup

- Board: Banana Pi Pro (A20)
- Image: Armbian 26.11.3 stable, Ubuntu 26.04 (resolute), XFCE desktop (LightDM, Xorg 21.1.22, modesetting driver)
- Build: armbian/build `0bf4c8e96`, kernel `6.18.65-current-sunxi`, U-Boot `2026.07_armbian-2026.07-Sece3-Pd4c7-H8519-V2473-Bd800-R448a`
- HDMI only (no LCD overlay), monitor Dell S3422DW (native 3440x1440)

### What happens

U-Boot and the kernel console are visible on the HDMI monitor. When LightDM/Xorg starts, the monitor loses the signal and stays black.

### Why

1. U-Boot leaves its framebuffer enabled for the kernel: `/chosen/framebuffer@7e000000`, `simple-framebuffer`, `status = "okay"`, 3440x1440 (the native mode of the monitor).
2. `CONFIG_DRM_SUN4I=y`: sun4i-drm is built in and binds at 0.5 s. It removes conflicting firmware framebuffers at bind time, but at that moment none is registered yet.
3. `CONFIG_DRM_SIMPLEDRM=m`: simpledrm is a module in the initramfs, it loads at 2.8 s and binds to `framebuffer@7e000000`. Nothing removes it any more, so there are two KMS devices:

   ```
   [    0.522896] [drm] Initialized sun4i-drm 1.0.0 for display-engine on minor 0
   [    2.768820] [drm] Initialized simpledrm 1.0.0 for 7e000000.framebuffer on minor 1
   [    2.836545] simple-framebuffer 7e000000.framebuffer: [drm] fb1: simpledrmdrmfb frame buffer device
   [    4.952126] Error: Driver 'simple-framebuffer' is already registered, aborting...
   ```

   ```
   card0: sun4i-drm          card0-HDMI-A-1
   card1: simple-framebuffer card1-Unknown-1
   card2: lima
   ```

4. Xorg (modesetting) takes the simpledrm device as the primary screen and the real HDMI output only as a secondary GPU:

   ```
   (II) modeset(0): using drv /dev/dri/card1
   (II) modeset(G0): using drv /dev/dri/card0
   (II) modeset(0): Modeline "3440x1440"x60.0  297.22  3440 3440 3440 3440  1440 1440 1440 1440 (86.4 kHz eP)
   (II) modeset(0): Output None-1 using initial mode 3440x1440 +0+0
   ```

   The picture goes to a framebuffer that no longer drives the HDMI hardware, so the monitor is black.

With a panel overlay (for example `overlays=lemaker-lcd7`) sun4i-drm binds much later (about 31 s, it waits for the panel), simpledrm is already registered and gets removed, and there is only one KMS device. That is probably why this went unnoticed: it shows only on HDMI without a panel.

The two `Driver 'simple-framebuffer' is already registered` errors come from `simplefb` (`CONFIG_FB_SIMPLE=m`) trying to register a driver with the same name as simpledrm.

### Affected

`config/kernel/linux-sunxi-legacy.config`, `linux-sunxi-current.config` and `linux-sunxi-edge.config` all have `CONFIG_DRM_SUN4I=y`, `CONFIG_DRM_SIMPLEDRM=m` and `CONFIG_FB_SIMPLE=m`, so likely every 32-bit sunxi desktop image used on HDMI without a panel. `linux-sunxi64-current.config` has no simpledrm.

### Possible fixes

- Disable `CONFIG_DRM_SIMPLEDRM` and `CONFIG_FB_SIMPLE` in the 32-bit sunxi configs, like sunxi64. sun4i-drm is built in and takes over the display 0.5 s after boot, so the firmware framebuffer is not needed.
- Or build simpledrm in (`=y`), so it registers before sun4i-drm binds and gets removed by it.

Workaround on an installed system, tested on the Banana Pi Pro: after it only sun4i-drm and lima are left, Xorg uses the HDMI output and the monitor shows the desktop. (`simplefb` from `CONFIG_FB_SIMPLE=m` then registers `fb1` on the U-Boot framebuffer; Xorg does not use it, but it is the same leftover.)

```bash
echo "blacklist simpledrm" | sudo tee /etc/modprobe.d/blacklist-simpledrm.conf
sudo update-initramfs -u
sudo reboot
```

I am the maintainer of the Banana Pi Pro and can open a PR for the configs once the preferred fix is agreed.
