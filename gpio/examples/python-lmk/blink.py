#!/usr/bin/env python3
"""Blink an LED with LMK.GPIO (same API as RPi.GPIO).

Wiring: LED + 330 ohm resistor from physical pin 11 (PI19) to GND (pin 9).
Run:    sudo python3 blink.py
"""
import time
import LMK.GPIO as GPIO

LED = 11                      # physical pin number, because of GPIO.BOARD

GPIO.setmode(GPIO.BOARD)      # or GPIO.BCM: then the LED is BCM 17
GPIO.setup(LED, GPIO.OUT, initial=GPIO.LOW)
try:
    for _ in range(10):
        GPIO.output(LED, GPIO.HIGH)
        time.sleep(0.5)
        GPIO.output(LED, GPIO.LOW)
        time.sleep(0.5)
except KeyboardInterrupt:
    pass
finally:
    GPIO.cleanup()            # back to input, also after Ctrl+C
