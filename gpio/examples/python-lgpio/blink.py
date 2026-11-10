#!/usr/bin/env python3
"""Blink an LED with lgpio (the pigpio successor, works on any Linux board).

Wiring: LED + 330 ohm resistor from physical pin 11 (PI19) to GND (pin 9).
Run:    sudo python3 blink.py
lgpio uses kernel GPIO numbers: PI19 = 8 * 32 + 19 = 275 on gpiochip0.
"""
import time
import lgpio

LED = 275
h = lgpio.gpiochip_open(0)
lgpio.gpio_claim_output(h, LED, 0)
try:
    for _ in range(10):
        lgpio.gpio_write(h, LED, 1)
        time.sleep(0.5)
        lgpio.gpio_write(h, LED, 0)
        time.sleep(0.5)
except KeyboardInterrupt:
    pass
finally:
    lgpio.gpio_free(h, LED)
    lgpio.gpiochip_close(h)
