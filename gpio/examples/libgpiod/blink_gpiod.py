#!/usr/bin/env python3
"""Blink an LED with the standard libgpiod Python binding (python3-libgpiod 2.x).

Wiring: LED + 330 ohm resistor from physical pin 11 (PI19) to GND.
Run:    sudo python3 blink_gpiod.py
libgpiod uses kernel GPIO numbers: PI19 = 8 * 32 + 19 = 275.
"""
import time
import gpiod
from gpiod.line import Direction, Value

LED = 275
settings = gpiod.LineSettings(direction=Direction.OUTPUT, output_value=Value.INACTIVE)
with gpiod.request_lines("/dev/gpiochip0", consumer="blink", config={LED: settings}) as request:
    try:
        for _ in range(10):
            request.set_value(LED, Value.ACTIVE)
            time.sleep(0.5)
            request.set_value(LED, Value.INACTIVE)
            time.sleep(0.5)
    except KeyboardInterrupt:
        pass
