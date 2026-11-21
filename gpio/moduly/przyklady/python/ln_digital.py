#!/usr/bin/python3
"""ln_digital.py: LN Digital (MCP23S17 na SPI) z Pythona przez lgpio.

CO: wedrujace swiatlo na wyjsciach P0-P7, potem przez 15 s wypisuje nacisniete
przyciski S1-S4 (wejscia IN0-IN3).
Uzycie: sudo python3 ln_digital.py
Wymaga: pakiet python3-lgpio, nakladka spi-spidev z param_spidev_spi_bus=0 (/dev/spidev0.0).
DLACZEGO lgpio, a nie osobna biblioteka: lgpio ma SPI, a MCP23S17 obsluguje sie
kilkoma rejestrami; nie potrzeba przenosic starych bibliotek LeMakera.
"""
import time

import lgpio

# CO: rejestry MCP23S17 (IOCON.BANK = 0, domyslnie po wlaczeniu).
IODIRA, IODIRB, IOCON, GPPUB, GPIOB, OLATA = 0x00, 0x01, 0x0A, 0x0D, 0x13, 0x14
ADRES = 0  # zworki JP1 (A0) i JP2 (A1)


class MCP23S17:
    def __init__(self, spi_dev=0, spi_cs=0, adres=ADRES):
        self.h = lgpio.spi_open(spi_dev, spi_cs, 1_000_000, 0)
        self.op = 0x40 | (adres << 1)
        # DLACZEGO HAEN: bez niego uklad ignoruje adres z zworek (wszystkie plytki = adres 0).
        self.zapisz(IOCON, 0x08)

    def zapisz(self, rejestr, wartosc):
        lgpio.spi_write(self.h, [self.op, rejestr, wartosc])

    def czytaj(self, rejestr):
        _, dane = lgpio.spi_xfer(self.h, [self.op | 1, rejestr, 0])
        return dane[2]

    def zamknij(self):
        lgpio.spi_close(self.h)


def main():
    m = MCP23S17()
    try:
        m.zapisz(IODIRA, 0x00)   # port A: wyjscia (P0-P7 przez ULN2803)
        m.zapisz(IODIRB, 0xFF)   # port B: wejscia (IN0-IN7)
        m.zapisz(GPPUB, 0xFF)    # podciaganie wejsc; nacisniety przycisk = 0
        print("Wyjscia P0-P7: wedrujace swiatlo")
        for n in list(range(8)) + list(range(6, -1, -1)):
            m.zapisz(OLATA, 1 << n)
            time.sleep(0.1)
        m.zapisz(OLATA, 0)
        print("Przyciski S1-S4: naciskaj przez 15 s")
        poprz = 0xFF
        koniec = time.time() + 15
        while time.time() < koniec:
            teraz = m.czytaj(GPIOB)
            for n in range(4):
                if poprz & (1 << n) and not teraz & (1 << n):
                    print(f"Przycisk S{n + 1} nacisniety")
            poprz = teraz
            time.sleep(0.02)
    finally:
        m.zapisz(OLATA, 0)
        m.zamknij()


if __name__ == "__main__":
    main()
