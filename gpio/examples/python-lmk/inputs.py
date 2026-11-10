#!/usr/bin/env python3
"""Show the level of free header pins live (no wiring needed).

Run: sudo python3 inputs.py      (Ctrl+C to stop)
Touch a pin with a wire to GND or 3.3 V and watch it change. Only free
pins are read, see the pinout; pins used by I2C/SPI/UART are skipped.
"""
import time
import LMK.GPIO as GPIO

FREE = [7, 11, 12, 13, 15, 16, 18, 22, 29, 33, 35, 36, 37, 38]

GPIO.setmode(GPIO.BOARD)
GPIO.setwarnings(False)
for pin in FREE:
    GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)
try:
    while True:
        print("  ".join(f"{pin:2}:{GPIO.input(pin)}" for pin in FREE), end="\r", flush=True)
        time.sleep(0.2)
except KeyboardInterrupt:
    print()
finally:
    GPIO.cleanup()
