#!/usr/bin/env python3
"""Blink an LED on a Banana Pro over the network with rgpio (like pigpiod).

On the Banana Pro: start the daemon, it listens on port 8889:
    sudo rgpiod -n <IP of your computer>     (or -l: only local connections)
On any computer with the rgpio module (from gpio/lg/PY_RGPIO):
    python3 remote_blink.py <IP of the Banana Pro>
Wiring: LED + 330 ohm resistor from physical pin 11 (PI19 = 275) to GND.
"""
import sys
import time
import rgpio

LED = 275
sbc = rgpio.sbc(sys.argv[1] if len(sys.argv) > 1 else "localhost", 8889)
if not sbc.connected:
    sys.exit("cannot connect to rgpiod")
h = sbc.gpiochip_open(0)
sbc.gpio_claim_output(h, LED, 0)
try:
    for _ in range(10):
        sbc.gpio_write(h, LED, 1)
        time.sleep(0.5)
        sbc.gpio_write(h, LED, 0)
        time.sleep(0.5)
except KeyboardInterrupt:
    pass
finally:
    sbc.gpio_free(h, LED)
    sbc.gpiochip_close(h)
    sbc.stop()
