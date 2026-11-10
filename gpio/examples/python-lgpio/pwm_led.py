#!/usr/bin/env python3
"""Fade an LED with lgpio software PWM (tx_pwm, any pin).

Wiring: LED + 330 ohm resistor on physical pin 11 (PI19 = 275).
Run:    sudo python3 pwm_led.py
"""
import time
import lgpio

LED = 275
h = lgpio.gpiochip_open(0)
lgpio.gpio_claim_output(h, LED, 0)
try:
    for _ in range(3):
        for duty in list(range(0, 101, 5)) + list(range(100, -1, -5)):
            lgpio.tx_pwm(h, LED, 200, duty)   # 200 Hz, duty in percent
            time.sleep(0.05)
except KeyboardInterrupt:
    pass
finally:
    lgpio.tx_pwm(h, LED, 0, 0)               # stop PWM
    lgpio.gpio_free(h, LED)
    lgpio.gpiochip_close(h)
