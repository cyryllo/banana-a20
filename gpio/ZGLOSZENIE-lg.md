# Issue for joan2937/lg

Paste at https://github.com/joan2937/lg/issues/new

**Title:** Alerts report a wrong GPIO number on chips with more than 256 lines (lgGpioReport_t.gpio is uint8_t)

**Text:**

`lgGpioReport_t` stores the GPIO offset in a `uint8_t`:

```c
typedef struct
{
   uint64_t timestamp;
   uint8_t chip;
   uint8_t gpio;   /* offset into gpio device */
   uint8_t level;
   uint8_t flags;
} lgGpioReport_t;
```

Some SoCs have more than 256 lines on one gpiochip. The Allwinner A20 (Banana Pi / Banana Pro) has 288 lines on `gpiochip0`, and most pins of the 40-pin header are in bank PI (offsets 256-287). For these pins the report carries only the low 8 bits: an alert on offset 274 is reported as `gpio 18`.

The result:

- C alert callbacks (`lgGpioSetAlertsFunc`) receive `report.gpio = 18` for line 274,
- the Python `lgpio` and `rgpio` modules match callbacks by `gpio`, so callbacks on lines above 255 never run (line 244 works, line 274 does not).

Steps (Banana Pro, Armbian, kernel 6.18, lg master bcccd78): claim an alert on line 274 (`lgpio.gpio_claim_alert(h, 274, lgpio.BOTH_EDGES, lgpio.SET_PULL_UP)`), add `lgpio.callback(...)`, change the level: the kernel delivers the events, the callback count stays 0.

A possible fix that keeps the struct size (16 bytes) and the old field: put the full offset into the former padding, fill it in `lgPthAlerts.c`, and use it in the Python modules and `rgpio.c`:

```c
   uint8_t flags;
   uint16_t gpio16;   /* full offset, gpio holds only the low 8 bits */
} lgGpioReport_t;
```

In Python `struct.unpack('QBBBBHH', msgbuf)` instead of `'QBBBBI'`, and use `gpio16` when `(gpio16 & 0xFF) == gpio` (so a new client still works with an old rgpiod, which leaves padding there). I tested this on the board: C alerts report 274, Python lgpio and remote rgpio (rgpiod) callbacks on line 274 all fire. The patch (about 30 lines): https://github.com/cyryllo/banana-a20/commit/9cc7a0f

Thank you for lg, it runs fine on the A20 otherwise (PWM, servo pulses, alerts, rgpiod).
