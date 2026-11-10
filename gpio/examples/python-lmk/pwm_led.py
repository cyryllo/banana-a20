#!/usr/bin/env python3
"""Fade an LED with software PWM (GPIO.PWM, works on any pin).

Wiring: LED + 330 ohm resistor on physical pin 11 (PI19).
Run:    sudo python3 pwm_led.py
"""
import time
import LMK.GPIO as GPIO

LED = 11
GPIO.setmode(GPIO.BOARD)
GPIO.setup(LED, GPIO.OUT)
pwm = GPIO.PWM(LED, 100)      # 100 Hz
pwm.start(0)                  # duty cycle in percent
try:
    for _ in range(3):
        for duty in list(range(0, 101, 2)) + list(range(100, -1, -2)):
            pwm.ChangeDutyCycle(duty)
            time.sleep(0.02)
except KeyboardInterrupt:
    pass
finally:
    pwm.stop()
    GPIO.cleanup()
