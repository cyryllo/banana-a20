#!/bin/sh
# Blink an LED with the standard Linux GPIO tools (package "gpiod").
# Wiring: LED + 330 ohm resistor from physical pin 11 (PI19) to GND.
# Run:    sudo ./blink.sh
#
# libgpiod uses the kernel GPIO number: PI19 = 8 * 32 + 19 = 275 on gpiochip0.
# "-t 0" sets the value and exits at once (the pin keeps its level).
LED=275
for i in 1 2 3 4 5; do
	gpioset -c gpiochip0 -t 0 $LED=1; sleep 0.5
	gpioset -c gpiochip0 -t 0 $LED=0; sleep 0.5
done
