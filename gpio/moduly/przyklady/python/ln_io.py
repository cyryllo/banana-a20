#!/usr/bin/python3
"""ln_io.py: diody i przyciski plytki LN IO z Pythona przez LMK.GPIO.

CO: "diody": wedrujace swiatlo na 8 diodach (zworki CN1 w pozycji LED);
    "przyciski": przez 15 s wypisuje nacisniecia 4 przyciskow (zworki H11),
    z przerwaniami (add_event_detect).
Uzycie: sudo python3 ln_io.py diody|przyciski
Wymaga: pakiet python3-lmk-gpio.
DLACZEGO numeracja BOARD: numery pinow zlacza 40-pin, takie jak na schemacie
LN IO (GPIO0..7 = piny 11, 12, 13, 15, 16, 18, 22, 7).
"""
import sys
import time

import LMK.GPIO as GPIO

DIODY = [11, 12, 13, 15, 16, 18, 22, 7]   # GPIO0..GPIO7
PRZYCISKI = [13, 15, 16, 18]              # GPIO2..GPIO5 (te same piny co diody 2-5)


def diody():
    for p in DIODY:
        GPIO.setup(p, GPIO.OUT, initial=GPIO.LOW)
    print("Diody: wedrujace swiatlo")
    for p in DIODY + DIODY[-2::-1]:
        GPIO.output(p, GPIO.HIGH)
        time.sleep(0.12)
        GPIO.output(p, GPIO.LOW)


def przyciski():
    # DLACZEGO podciaganie: przycisk zwiera pin do GND, wiec nacisniety = 0 (zbocze opadajace).
    def nacisniety(kanal):
        print(f"Przycisk na pinie {kanal} nacisniety")

    for p in PRZYCISKI:
        GPIO.setup(p, GPIO.IN, pull_up_down=GPIO.PUD_UP)
        GPIO.add_event_detect(p, GPIO.FALLING, callback=nacisniety, bouncetime=200)
    print("Przyciski: naciskaj przez 15 s (zworki diod na pinach 13, 15, 16, 18 zdjete)")
    time.sleep(15)


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("diody", "przyciski"):
        sys.exit("Uzycie: sudo python3 ln_io.py diody|przyciski")
    GPIO.setwarnings(False)
    GPIO.setmode(GPIO.BOARD)
    try:
        diody() if sys.argv[1] == "diody" else przyciski()
    finally:
        GPIO.cleanup()


if __name__ == "__main__":
    main()
