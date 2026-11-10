#!/usr/bin/env python3
"""React to a button with an event callback (interrupt, no busy polling).

Wiring: push button between physical pin 13 (PI18) and GND (pin 14),
        optional LED on pin 11 (toggles on each press).
Run:    sudo python3 button.py     (Ctrl+C to stop)
"""
import time
import LMK.GPIO as GPIO

LED, BUTTON = 11, 13
presses = 0


def pressed(channel):
    """Called from a background thread on every press."""
    global presses
    presses += 1
    GPIO.output(LED, presses % 2)
    print(f"press {presses} on pin {channel}", flush=True)


GPIO.setmode(GPIO.BOARD)
GPIO.setup(LED, GPIO.OUT, initial=GPIO.LOW)
# The internal pull-up keeps the pin HIGH, a press pulls it LOW.
GPIO.setup(BUTTON, GPIO.IN, pull_up_down=GPIO.PUD_UP)
# bouncetime: ignore contact bounce for 200 ms after an event.
GPIO.add_event_detect(BUTTON, GPIO.FALLING, callback=pressed, bouncetime=200)
print("waiting for the button on pin 13, Ctrl+C to stop", flush=True)
try:
    while True:
        time.sleep(1)
except KeyboardInterrupt:
    pass
finally:
    GPIO.cleanup()
