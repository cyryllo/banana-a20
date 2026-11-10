# Issue 1

**Title:** udev: touchscreen pointer never pressed/released correctly (KMS, UDEV_TOUCH_SUPPORT)

**Is there an existing issue for this?** [x] This is a bug in RetroArch frontend, [x] I have searched the existing issues

**Description:**

With the udev input driver built with `-DUDEV_TOUCH_SUPPORT`, taps on a touchscreen do nothing in the menu. I found three bugs in `input/drivers/udev_input.c`. All three are still in master (49582a9, line numbers below are from that commit).

**1. The simulated pointer is reported pressed after release** ([line 2393](https://github.com/libretro/RetroArch/blob/49582a9383c9094ed89dbaa7ffc5fb6f4b7bd2db/input/drivers/udev_input.c#L2393))

```c
/* Release the pointer only after all contacts are released */
if (touch->pointer_enabled)
   touch->pointer_btn_pp = (touch->staging_active == 0);
```

`staging_active` has already been decremented here, so the condition is inverted: the pointer is pressed after the last finger is lifted and released while a finger is still down. The menu acts on release, so taps never register. Fix: `(touch->staging_active > 0)`.

**2. `udev_input_touch_state()` always returns 0 for the pointer** ([lines 3037-3041](https://github.com/libretro/RetroArch/blob/49582a9383c9094ed89dbaa7ffc5fb6f4b7bd2db/input/drivers/udev_input.c#L3037-L3041))

```c
case RETRO_DEVICE_POINTER:
case RARCH_DEVICE_POINTER_SCREEN:
   screen = (device == RARCH_DEVICE_MOUSE_SCREEN);
   break;
   switch (id)
```

The stray `break` leaves before `switch (id)`, so pointer X/Y/pressed are never reported. The comparison also uses `RARCH_DEVICE_MOUSE_SCREEN` instead of `RARCH_DEVICE_POINTER_SCREEN`. Fix: remove the `break` and compare with `RARCH_DEVICE_POINTER_SCREEN`.

**3. Single-touch emulation is mixed into MT slot 0** ([ABS_X line 2659](https://github.com/libretro/RetroArch/blob/49582a9383c9094ed89dbaa7ffc5fb6f4b7bd2db/input/drivers/udev_input.c#L2659), [ABS_Y around line 2683](https://github.com/libretro/RetroArch/blob/49582a9383c9094ed89dbaa7ffc5fb6f4b7bd2db/input/drivers/udev_input.c#L2683), [BTN_TOUCH line 2729](https://github.com/libretro/RetroArch/blob/49582a9383c9094ed89dbaa7ffc5fb6f4b7bd2db/input/drivers/udev_input.c#L2729))

For multi-touch devices the kernel also sends single-touch emulation (`ABS_X`, `ABS_Y`, `BTN_TOUCH`) that follows the oldest active contact. The code writes it into slot 0 (`BTN_TOUCH` even into the current slot) on top of the MT slot data. When a second contact outlives the first one, the emulation jumps to it: slot 0 gets that position and a second touch up, the log shows `Cannot report touch up since there are no active points.` and the menu sees phantom releases and taps while scrolling. The MT slots carry the same data, so the fix is to skip these three events when the device has MT slots:

```c
if (touch->info_slots.enabled && touch->info_slots.range > 1)
   break;
```

Single-touch devices (no `ABS_MT_SLOT`) are not affected by this change.

Bugs 1 and 2 seem to date back to the touch rewrite in #15282 (2023).

Side note: nothing in the build system defines `UDEV_TOUCH_SUPPORT` (configure, `Makefile.common`), so distribution builds have no touchscreen support in udev at all. Maybe it could become a configure option once these bugs are fixed.

I have patches against v1.20.0 tested on hardware and can open a PR against master if that helps:
https://github.com/cyryllo/banana-a20/tree/arkada20-v1.0-trixie-6.18.62/armbian-build/konsola/latki-retroarch (0001, 0002, 0007)

**Expected behavior:** A tap selects a menu entry, the pointer is pressed while a finger is down and released when the last finger is lifted.

**Steps to reproduce the bug:**

1. Build RetroArch for Linux with KMS and udev, `CFLAGS=-DUDEV_TOUCH_SUPPORT`.
2. Run it on a device with a multi-touch touchscreen (evdev with `ABS_MT_SLOT`), `input_driver = "udev"`, `menu_pointer_enable = "true"`, `input_touch_vmouse_pointer = "true"`.
3. Tap a menu entry: nothing happens. With 1 and 2 fixed, taps work, but with two contacts the menu gets phantom releases (bug 3).

**Version/Commit:** 1.20.0 (built from the v1.20.0 tag). The same code is in master 49582a9.

**Bisect Results:** Probably since #15282 (2023), not bisected.

**Present in the nightly version:** I don't know (no nightly build for this platform, the code in master is unchanged)

**Platform & operating system:** Linux armhf, Debian 13 (Armbian), kernel 6.18.62, LeMaker Banana Pro (Allwinner A20)

**Affected Cores:** None (menu)

**Environment information:** KMS + EGL + OpenGL ES 2 (Mesa lima, Mali-400), udev input, no X11/Wayland. Touchscreen: FocalTech FT5x06 (`edt-ft5x06` driver), 1024x600, multi-touch with slots.

**Relevant log output:** `[udev] Cannot report touch up since there are no active points.` (bug 3)

---

# Issue 2

**Title:** KMS context: no get_metrics, menu gets DPI 0 (no touch drag/swipe)

**Is there an existing issue for this?** [x] This is a bug in RetroArch frontend, [x] I have searched the existing issues

**Description:**

`gfx/drivers_context/drm_ctx.c` has no `get_metrics` callback ([line 1462](https://github.com/libretro/RetroArch/blob/49582a9383c9094ed89dbaa7ffc5fb6f4b7bd2db/gfx/drivers_context/drm_ctx.c#L1462)), so the menu always gets DPI 0 in KMS mode. With DPI 0 the menu skips pointer drag detection, swipe gestures and press direction, so on a touchscreen only taps work: lists cannot be scrolled and XMB categories cannot be changed by swiping.

The DRM connector already has the physical size: `g_drm_connector->mmWidth` / `mmHeight`, filled by the kernel from the panel description (device tree `width-mm`/`height-mm`) or from the EDID. A small callback fixes it:

```c
static bool gfx_ctx_drm_get_metrics(void *data,
      enum display_metric_types type, float *value)
{
   unsigned mm_width  = g_drm_connector ? g_drm_connector->mmWidth  : 0;
   unsigned mm_height = g_drm_connector ? g_drm_connector->mmHeight : 0;
   unsigned px_width  = g_drm_mode ? g_drm_mode->hdisplay : 0;

   switch (type)
   {
      case DISPLAY_METRIC_MM_WIDTH:
         if (!mm_width)
            return false;
         *value = (float)mm_width;
         return true;
      case DISPLAY_METRIC_MM_HEIGHT:
         if (!mm_height)
            return false;
         *value = (float)mm_height;
         return true;
      case DISPLAY_METRIC_DPI:
         if (!mm_width || !px_width)
            return false;
         *value = ((float)px_width * 25.4f) / (float)mm_width;
         return true;
      default:
         break;
   }

   *value = 0.0f;
   return false;
}
```

Patch against v1.20.0, tested on hardware (0003): https://github.com/cyryllo/banana-a20/tree/arkada20-v1.0-trixie-6.18.62/armbian-build/konsola/latki-retroarch . I can open a PR against master.

**Expected behavior:** The menu gets the real DPI of the display in KMS mode, touch drag and swipe gestures work.

**Steps to reproduce the bug:**

1. Run RetroArch with `video_context_driver = "kms"` on a display that reports its size (`/sys/class/drm/*/` or EDID).
2. On a touchscreen (with the udev touch fixes from #ISSUE1), try to drag a menu list or swipe between XMB categories: nothing moves, only taps work.

**Version/Commit:** 1.20.0, the same code in master 49582a9.

**Bisect Results:** The KMS context never had `get_metrics`.

**Present in the nightly version:** I don't know (code in master is unchanged)

**Platform & operating system:** Linux armhf, Debian 13 (Armbian), kernel 6.18.62, LeMaker Banana Pro (Allwinner A20)

**Affected Cores:** None (menu)

**Environment information:** KMS + EGL + OpenGL ES 2 (Mesa lima, Mali-400), 7" 1024x600 LVDS panel, 154 x 86 mm (DPI about 169).
