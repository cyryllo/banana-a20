#!/usr/bin/env python3
"""React to a button with lgpio alerts (interrupt, kernel time stamps).

Wiring: push button between physical pin 13 (PI18 = 274) and GND,
        optional LED on pin 11 (275), toggles on each press.
Run:    sudo python3 button_alert.py     (Ctrl+C to stop)
Pins above 255 (bank PI) need the lg version from this repository,
the original one reports them with a wrong number.
"""
import time
import lgpio

LED, BUTTON = 275, 274
presses = 0


def pressed(chip, gpio, level, timestamp):
    """Called from the lgpio thread; timestamp is in nanoseconds."""
    global presses
    presses += 1
    lgpio.gpio_write(h, LED, presses % 2)
    print(f"press {presses} on GPIO {gpio} at {timestamp / 1e9:.6f} s", flush=True)


h = lgpio.gpiochip_open(0)
lgpio.gpio_claim_output(h, LED, 0)
# falling edge = the moment of pressing; internal pull-up keeps the pin high
lgpio.gpio_claim_alert(h, BUTTON, lgpio.FALLING_EDGE, lgpio.SET_PULL_UP)
lgpio.gpio_set_debounce_micros(h, BUTTON, 20000)   # ignore contact bounce < 20 ms
callback = lgpio.callback(h, BUTTON, lgpio.FALLING_EDGE, pressed)
print("waiting for the button on pin 13, Ctrl+C to stop", flush=True)
try:
    while True:
        time.sleep(1)
except KeyboardInterrupt:
    pass
finally:
    callback.cancel()
    lgpio.gpio_free(h, BUTTON)
    lgpio.gpio_free(h, LED)
    lgpio.gpiochip_close(h)
