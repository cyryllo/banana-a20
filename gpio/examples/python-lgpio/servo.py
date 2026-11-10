#!/usr/bin/env python3
"""Move a hobby servo with lgpio (tx_servo, any pin).

Wiring: servo signal (yellow/white) to physical pin 11 (PI19 = 275),
        servo + to an external 5 V supply, servo - to that supply's GND
        AND to a GND pin of the board (pin 9). Do not power a servo from pin 2/4.
Run:    sudo python3 servo.py

The pulses are timed in software: steady on an idle board, they jitter when
the CPU is busy (e.g. RetroArch). For steady servos use hardware PWM on pin 12
or a PCA9685 board on I2C, see the README.
"""
import time
import lgpio

SERVO = 275
h = lgpio.gpiochip_open(0)
lgpio.gpio_claim_output(h, SERVO, 0)
try:
    for width in (1000, 1500, 2000, 1500):      # microseconds: one end, centre, other end
        print(f"pulse {width} us", flush=True)
        lgpio.tx_servo(h, SERVO, width, 50)     # 50 Hz
        time.sleep(1)
except KeyboardInterrupt:
    pass
finally:
    lgpio.tx_servo(h, SERVO, 0)                 # stop pulses
    lgpio.gpio_free(h, SERVO)
    lgpio.gpiochip_close(h)
