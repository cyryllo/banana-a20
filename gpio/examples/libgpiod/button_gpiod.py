#!/usr/bin/env python3
"""Wait for button presses with libgpiod edge events (interrupt, no polling).

Wiring: push button between physical pin 13 (PI18 = 274) and GND.
Run:    sudo python3 button_gpiod.py     (Ctrl+C to stop)
"""
from datetime import timedelta
import gpiod
from gpiod.line import Bias, Direction, Edge

BUTTON = 274
settings = gpiod.LineSettings(direction=Direction.INPUT, bias=Bias.PULL_UP,
                              edge_detection=Edge.FALLING,
                              debounce_period=timedelta(milliseconds=200))
with gpiod.request_lines("/dev/gpiochip0", consumer="button", config={BUTTON: settings}) as request:
    print("waiting for the button on pin 13, Ctrl+C to stop", flush=True)
    presses = 0
    try:
        while True:
            for event in request.read_edge_events():   # blocks until an edge
                presses += 1
                print(f"press {presses} ({event.event_type.name})", flush=True)
    except KeyboardInterrupt:
        pass
