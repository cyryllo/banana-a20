#!/bin/sh
# Print a line for every press of a button, using an interrupt.
# Wiring: push button between physical pin 13 (PI18 = 274) and GND.
# Run:    sudo ./button.sh      (Ctrl+C to stop)
#
# "-b pull-up" turns on the internal pull-up, "-e falling" = the moment of pressing,
# "-p 200ms" ignores contact bounce.
gpiomon -c gpiochip0 -b pull-up -e falling -p 200ms 274
