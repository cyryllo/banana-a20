#!/usr/bin/python3
"""hub_32io.py: 32 diody LN HUB-32IO (2 x MCP23017 na I2C) z Pythona przez lgpio.

CO: wszystkie diody migaja 3 razy, potem wedrujace swiatlo przez 32 wyjscia.
Uzycie: sudo python3 hub_32io.py
Wymaga: pakiet python3-lgpio. I2C2 (piny 3 i 5) jest w Armbianie wlaczone domyslnie.
"""
import glob
import os
import time

import lgpio

IODIRA, IODIRB, OLATA, OLATB = 0x00, 0x01, 0x14, 0x15
ADRESY = (0x20, 0x21)


def magistrala_i2c2():
    """CO: numer /dev/i2c-N kontrolera I2C2 (piny 3 i 5, adres 1c2b400).
    DLACZEGO po adresie: numery i2c-N zaleza od kolejnosci w jadrze."""
    for d in glob.glob("/sys/class/i2c-dev/i2c-*"):
        if "1c2b400" in os.path.realpath(os.path.join(d, "device")):
            return int(d.rsplit("-", 1)[1])
    return 1


def main():
    bus = magistrala_i2c2()
    uklady = [lgpio.i2c_open(bus, a) for a in ADRESY]
    try:
        for h in uklady:
            lgpio.i2c_write_byte_data(h, IODIRA, 0x00)
            lgpio.i2c_write_byte_data(h, IODIRB, 0x00)

        def ustaw(wzor):
            """wzor: 32 bity, bit n = dioda n (0-15 uklad 0x20, 16-31 uklad 0x21)."""
            for i, h in enumerate(uklady):
                lgpio.i2c_write_byte_data(h, OLATA, (wzor >> (16 * i)) & 0xFF)
                lgpio.i2c_write_byte_data(h, OLATB, (wzor >> (16 * i + 8)) & 0xFF)

        print(f"LN HUB-32IO na /dev/i2c-{bus}: wszystkie diody migaja 3 razy")
        for _ in range(3):
            ustaw(0xFFFFFFFF)
            time.sleep(0.5)
            ustaw(0)
            time.sleep(0.5)
        print("Wedrujace swiatlo")
        for n in range(32):
            ustaw(1 << n)
            time.sleep(0.08)
        ustaw(0)
    finally:
        for h in uklady:
            lgpio.i2c_close(h)


if __name__ == "__main__":
    main()
