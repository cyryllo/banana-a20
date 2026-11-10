#!/usr/bin/env python3
"""Banana Pro 40-pin header (CON6): pinout picture and pin table.

WHAT: one table of pins (below) -> bananapro-pinout.svg, bananapro-pinout.png
and PINS.md (Markdown table, also copied into ../README.md), plus the Polish
versions bananapro-pinout-pl.svg/.png, PINS.pl.md and ../README.pl.md.
WHY one source: the picture and the table cannot drift apart.

Usage: python3 generuj-pinout.py   (PNG needs inkscape, otherwise it is skipped)

Sources of the data (checked 2026-11-10 on a Banana Pro, Armbian 6.18.62):
- physical pin -> SoC pin: WiringBP physToGpio_BP, the same as LMK.GPIO
- functions: Linux drivers/pinctrl/sunxi/pinctrl-sun4i-a10.c (A20 variant)
  and the Armbian overlays README (README.sun7i-a20-overlays)
- default use: sun7i-a20-bananapro.dts and
  /sys/kernel/debug/pinctrl/1c20800.pinctrl/pinmux-pins on the board
"""

import os
import shutil
import subprocess

TU = os.path.dirname(os.path.abspath(__file__))

# Colours by group (similar to the usual Raspberry Pi pinout pictures).
KOLORY = {
    "3v3":  ("#f5a623", "3.3 V"),
    "5v":   ("#e2463f", "5 V"),
    "gnd":  ("#3b3b3b", "Ground"),
    "gpio": ("#3fa34d", "GPIO (free)"),
    "i2c":  ("#2f7fd1", "I2C"),
    "uart": ("#8e4ec6", "UART (serial)"),
    "spi":  ("#d6336c", "SPI"),
    "busy": ("#8a8f98", "Used by the board"),
}

# pin: (group, SoC pin, default use in Armbian, other functions, interrupt)
# Power pins only have the group. "default" = what the stock Armbian device
# tree uses the pin for, "" = free GPIO.
PINY = {
    1: ("3v3",), 2: ("5v",), 4: ("5v",), 6: ("gnd",), 9: ("gnd",),
    14: ("gnd",), 17: ("3v3",), 20: ("gnd",), 25: ("gnd",), 30: ("gnd",),
    34: ("gnd",), 39: ("gnd",),
    3:  ("i2c",  "PB21", "I2C2 SDA (/dev/i2c-1)", "", False),
    5:  ("i2c",  "PB20", "I2C2 SCL (/dev/i2c-1)", "", False),
    7:  ("gpio", "PH2",  "", "", True),
    8:  ("uart", "PH4",  "UART4 TX (/dev/ttyS1)", "", True),
    10: ("uart", "PH5",  "UART4 RX (/dev/ttyS1)", "", True),
    11: ("gpio", "PI19", "", "SPI1 MISO, UART2 RX", True),
    12: ("gpio", "PI3",  "", "PWM1", False),
    13: ("gpio", "PI18", "", "SPI1 MOSI, UART2 TX", True),
    15: ("gpio", "PI17", "", "SPI1 SCK, UART2 CTS", True),
    16: ("gpio", "PH20", "", "CAN TX", True),
    18: ("gpio", "PH21", "", "CAN RX", True),
    19: ("spi",  "PI12", "SPI0 MOSI", "UART6 TX", True),
    21: ("spi",  "PI13", "SPI0 MISO", "UART6 RX", True),
    22: ("gpio", "PI16", "", "SPI1 CS0, UART2 RTS", True),
    23: ("spi",  "PI11", "SPI0 SCK", "", True),
    24: ("spi",  "PI10", "SPI0 CS0", "", True),
    26: ("spi",  "PI14", "SPI0 CS1", "", True),
    27: ("gpio", "PI1",  "", "I2C3 SDA (LCD touch)", False),
    28: ("gpio", "PI0",  "", "I2C3 SCL (LCD touch)", False),
    29: ("gpio", "PB3",  "", "", False),
    31: ("uart", "PI21", "UART7 RX (/dev/ttyS2)", "", False),
    32: ("uart", "PI20", "UART7 TX (/dev/ttyS2)", "", False),
    33: ("gpio", "PB13", "", "SPDIF out", False),
    35: ("gpio", "PB7",  "", "I2S0 LRCK", False),
    36: ("gpio", "PB6",  "", "I2S0 BCLK", False),
    37: ("gpio", "PB5",  "", "I2S0 MCLK", False),
    38: ("gpio", "PB12", "", "I2S0 DIN", False),
    40: ("busy", "PB8",  "SATA 5 V switch", "I2S0 DOUT", False),
}

# WiringPi (wPi) and BCM numbers used by WiringBP and LMK.GPIO, from "gpio readall".
WPI_BCM = {
    3: (8, 2), 5: (9, 3), 7: (7, 4), 8: (15, 14), 10: (16, 15), 11: (0, 17),
    12: (1, 18), 13: (2, 27), 15: (3, 22), 16: (4, 23), 18: (5, 24),
    19: (12, 10), 21: (13, 9), 22: (6, 25), 23: (14, 11), 24: (10, 8),
    26: (11, 7), 27: (30, 0), 28: (31, 1), 29: (21, 5), 31: (22, 6),
    32: (26, 12), 33: (23, 13), 35: (24, 19), 36: (27, 16), 37: (25, 26),
    38: (28, 20), 40: (29, 21),
}


# Texts of the picture and the table. "en" is the default, "pl" the Polish version.
TEKSTY = {
    "en": {
        "tytul": "Banana Pro 40-pin header (CON6)",
        "podtytul": "Allwinner A20, Armbian with the mainline kernel. Pin 1 has the square solder pad.",
        "kolumny": ("SoC pin", "kernel GPIO", "wPi", "BCM", "Default in Armbian", "Other functions"),
        "legenda": {"3v3": "3.3 V", "5v": "5 V", "gnd": "Ground", "gpio": "GPIO (free)", "i2c": "I2C",
                    "uart": "UART (serial)", "spi": "SPI", "busy": "Used by the board"},
        "masa": "GND",
        "przerwania": "= the pin can trigger interrupts (edge detection: wiringPiISR, "
                      "GPIO.add_event_detect, gpiomon, lgpio alerts).",
        "uwagi": [
            "kernel GPIO = bank * 32 + pin (PA = 0, PB = 1 ... PI = 8), the number for libgpiod and lgpio (gpiochip0) "
            "and /sys/class/gpio. wPi / BCM = numbering of WiringBP and LMK.GPIO.",
            "Default in Armbian: pins taken by drivers in the stock device tree; they still work as GPIO after the driver "
            "is disabled. Other functions: enable with an Armbian overlay (overlays= in /boot/armbianEnv.txt).",
            "Pin 40 (PB8) switches the 5 V supply of the SATA disk: do not use it as GPIO. "
            "Pins 27/28 carry the touchscreen of the LeMaker LCD panels (I2C3) when a lemaker-lcd overlay is on.",
            "All signal pins are 3.3 V, never connect 5 V to them.",
        ],
        "naglowek_tabeli": "| Pin | SoC pin | Kernel GPIO | wPi | BCM | Interrupt | Default in Armbian | Other functions |",
        "tak": "yes",
        "wygenerowane": "<!-- Generated by pinout/generuj-pinout.py, do not edit by hand. -->",
        "slowa": {},
    },
    "pl": {
        "tytul": "Złącze 40 pinów Banana Pro (CON6)",
        "podtytul": "Allwinner A20, Armbian z jądrem mainline. Pin 1 ma kwadratowe pole lutownicze.",
        "kolumny": ("Pin SoC", "GPIO jądra", "wPi", "BCM", "Domyślnie w Armbianie", "Inne funkcje"),
        "legenda": {"3v3": "3,3 V", "5v": "5 V", "gnd": "Masa", "gpio": "GPIO (wolny)", "i2c": "I2C",
                    "uart": "UART (port szeregowy)", "spi": "SPI", "busy": "Zajęty przez płytkę"},
        "masa": "GND",
        "przerwania": "= pin może zgłaszać przerwania (wykrywanie zboczy: wiringPiISR, "
                      "GPIO.add_event_detect, gpiomon, lgpio).",
        "uwagi": [
            "GPIO jądra = bank * 32 + pin (PA = 0, PB = 1 ... PI = 8), numer dla libgpiod i lgpio (gpiochip0) "
            "i /sys/class/gpio. wPi / BCM = numeracja WiringBP i LMK.GPIO.",
            "Domyślnie w Armbianie: piny zajęte przez sterowniki w standardowym opisie sprzętu; po wyłączeniu sterownika "
            "działają jako GPIO. Inne funkcje: włączane nakładką Armbiana (overlays= w /boot/armbianEnv.txt).",
            "Pin 40 (PB8) włącza zasilanie 5 V dysku SATA: nie używaj go jako GPIO. "
            "Piny 27/28 to dotyk ekranów LeMaker (I2C3), gdy włączona jest nakładka lemaker-lcd.",
            "Wszystkie piny sygnałowe mają 3,3 V, nigdy nie podłączaj do nich 5 V.",
        ],
        "naglowek_tabeli": "| Pin | Pin SoC | GPIO jądra | wPi | BCM | Przerwania | Domyślnie w Armbianie | Inne funkcje |",
        "tak": "tak",
        "wygenerowane": "<!-- Wygenerowane przez pinout/generuj-pinout.py, nie zmieniaj ręcznie. -->",
        # pin descriptions that differ in Polish (the rest are names)
        "slowa": {"SATA 5 V switch": "włącznik 5 V SATA", "(LCD touch)": "(dotyk LCD)", "SPDIF out": "wyjście SPDIF",
                  "I2S0 DIN": "I2S0 wejście", "I2S0 DOUT": "I2S0 wyjście"},
    },
}


def tlumacz(jezyk, t):
    """Pin description in the given language."""
    for a, b in TEKSTY[jezyk]["slowa"].items():
        t = t.replace(a, b)
    return t


def numer_jadra(soc):
    """PH2 -> 226: kernel GPIO number = bank * 32 + pin (bank A = 0)."""
    return (ord(soc[1]) - ord("A")) * 32 + int(soc[2:])


def nazwa(pin, jezyk="en"):
    p = PINY[pin]
    if p[0] == "gnd":
        return TEKSTY[jezyk]["masa"]
    if p[0] in ("3v3", "5v"):
        return TEKSTY[jezyk]["legenda"][p[0]]
    return p[1]


def esc(t):
    return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


# ---------------------------------------------------------------- SVG
SZER, WIERSZ, GORA = 1640, 36, 150
WYS = GORA + 20 * WIERSZ + 240
SRODEK = SZER // 2
FONT = "DejaVu Sans, Verdana, Arial, sans-serif"
MONO = "DejaVu Sans Mono, Consolas, monospace"

# Column centres (distance from the middle of the header), mirrored on the right.
KOL_SOC, KOL_GPIO, KOL_WPI, KOL_BCM, KOL_DOM, KOL_ALT = 92, 182, 248, 306, 455, 655
KOLOR_IRQ = "#ffe08a"


def tekst(x, y, t, rozm=14, kolor="#1d1d1f", kotwica="middle", waga="normal", font=FONT):
    return (f'<text x="{x}" y="{y}" font-family="{font}" font-size="{rozm}" fill="{kolor}" '
            f'text-anchor="{kotwica}" font-weight="{waga}">{esc(t)}</text>')


def pigulka(x, y, szer, kolor, t, kolor_t="#ffffff", rozm=13, font=FONT):
    return (f'<rect x="{x - szer / 2}" y="{y - 12}" width="{szer}" height="24" rx="12" fill="{kolor}"/>'
            + tekst(x, y + 5, t, rozm, kolor_t, waga="bold", font=font))


def rysuj(jezyk="en"):
    T = TEKSTY[jezyk]
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{SZER}" height="{WYS}" viewBox="0 0 {SZER} {WYS}">',
         f'<rect width="{SZER}" height="{WYS}" fill="#ffffff"/>',
         tekst(SRODEK, 48, T["tytul"], 30, waga="bold"),
         tekst(SRODEK, 78, T["podtytul"], 15, "#555555")]

    # Column headings (both sides).
    y = GORA - 22
    for strona in (-1, 1):
        for x, t in zip((KOL_SOC, KOL_GPIO, KOL_WPI, KOL_BCM, KOL_DOM, KOL_ALT), T["kolumny"]):
            s.append(tekst(SRODEK + strona * x, y, t, 13, "#777777", waga="bold"))

    # The header itself.
    s.append(f'<rect x="{SRODEK - 46}" y="{GORA - 6}" width="92" height="{20 * WIERSZ + 12}" '
             f'rx="10" fill="#1f2a30"/>')

    for wiersz in range(20):
        y = GORA + wiersz * WIERSZ + WIERSZ // 2
        if wiersz % 2:
            s.append(f'<rect x="20" y="{y - WIERSZ / 2}" width="{SZER - 40}" height="{WIERSZ}" '
                     f'fill="#f4f5f7"/>')
            s.append(f'<rect x="{SRODEK - 46}" y="{y - WIERSZ / 2}" width="92" height="{WIERSZ}" '
                     f'fill="#1f2a30"/>')
        for pin, strona in ((2 * wiersz + 1, -1), (2 * wiersz + 2, 1)):
            p = PINY[pin]
            kolor = KOLORY[p[0]][0]
            px = SRODEK + strona * 22
            # Pad: square for pin 1, round for the rest.
            if pin == 1:
                s.append(f'<rect x="{px - 14}" y="{y - 14}" width="28" height="28" rx="3" fill="{kolor}" '
                         f'stroke="#ffffff" stroke-width="2"/>')
            else:
                s.append(f'<circle cx="{px}" cy="{y}" r="14" fill="{kolor}" stroke="#ffffff" stroke-width="2"/>')
            s.append(tekst(px, y + 5, str(pin), 13, "#ffffff", waga="bold"))

            if p[0] in ("3v3", "5v", "gnd"):
                s.append(pigulka(SRODEK + strona * KOL_SOC, y, 74, kolor, nazwa(pin, jezyk)))
                continue
            grupa, soc, dom, alt, przerw = p
            dom, alt = tlumacz(jezyk, dom), tlumacz(jezyk, alt)
            wpi, bcm = WPI_BCM[pin]
            s.append(pigulka(SRODEK + strona * KOL_SOC, y, 74, kolor, soc, font=MONO))
            # WHAT: interrupt-capable pins get a yellow background behind the number.
            if przerw:
                s.append(pigulka(SRODEK + strona * KOL_GPIO, y, 52, KOLOR_IRQ, "", rozm=12))
            s.append(tekst(SRODEK + strona * KOL_GPIO, y + 5, str(numer_jadra(soc)), 14, font=MONO))
            s.append(tekst(SRODEK + strona * KOL_WPI, y + 5, str(wpi), 14, "#555555", font=MONO))
            s.append(tekst(SRODEK + strona * KOL_BCM, y + 5, str(bcm), 14, "#555555", font=MONO))
            if dom:
                s.append(pigulka(SRODEK + strona * KOL_DOM, y, 200, kolor, dom, rozm=12))
            else:
                s.append(tekst(SRODEK + strona * KOL_DOM, y + 5, "GPIO", 13, KOLORY["gpio"][0], waga="bold"))
            if alt:
                s.append(tekst(SRODEK + strona * KOL_ALT, y + 5, alt, 13, "#444444"))

    # Legend.
    y = GORA + 20 * WIERSZ + 46
    x = 60
    for klucz in ("3v3", "5v", "gnd", "gpio", "i2c", "uart", "spi", "busy"):
        kolor, opis = KOLORY[klucz][0], T["legenda"][klucz]
        s.append(f'<circle cx="{x}" cy="{y}" r="10" fill="{kolor}"/>')
        s.append(tekst(x + 18, y + 5, opis, 14, kotwica="start"))
        x += 30 + len(opis) * 8 + 40
    s.append(pigulka(86, y + 34, 52, KOLOR_IRQ, "226", "#1d1d1f", 14, MONO))
    s.append(tekst(122, y + 39, T["przerwania"], 14, "#333333", kotwica="start"))
    y += 24
    uwagi = T["uwagi"]
    for i, u in enumerate(uwagi):
        s.append(tekst(60, y + 40 + i * 24, u, 14, "#333333", kotwica="start"))
    s.append("</svg>")
    return "\n".join(s) + "\n"


# ---------------------------------------------------------------- Markdown
def tabela(jezyk="en"):
    T = TEKSTY[jezyk]
    w = [T["wygenerowane"], "", T["naglowek_tabeli"], "|---:|---|---:|---:|---:|:---:|---|---|"]
    for pin in range(1, 41):
        p = PINY[pin]
        if p[0] in ("3v3", "5v", "gnd"):
            w.append(f"| {pin} | **{nazwa(pin, jezyk)}** | | | | | | |")
            continue
        grupa, soc, dom, alt, przerw = p
        wpi, bcm = WPI_BCM[pin]
        w.append(f"| {pin} | {soc} | {numer_jadra(soc)} | {wpi} | {bcm} | {T['tak'] if przerw else ''} "
                 f"| {tlumacz(jezyk, dom) or 'GPIO'} | {tlumacz(jezyk, alt)} |")
    return "\n".join(w) + "\n"


def main():
    # WHAT: English and Polish versions: picture, table file and the table in the README.
    for jezyk, przyrostek, readme in (("en", "", "README.md"), ("pl", "-pl", "README.pl.md")):
        svg = os.path.join(TU, f"bananapro-pinout{przyrostek}.svg")
        with open(svg, "w") as f:
            f.write(rysuj(jezyk))
        with open(os.path.join(TU, "PINS.md" if jezyk == "en" else "PINS.pl.md"), "w") as f:
            f.write(tabela(jezyk))
        # the same table inside gpio/README(.pl).md, between the PINS markers
        sciezka = os.path.join(TU, "..", readme)
        if os.path.exists(sciezka):
            tekst_r = open(sciezka).read()
            poczatek, koniec = "<!-- PINS START -->", "<!-- PINS END -->"
            if poczatek in tekst_r and koniec in tekst_r:
                przed = tekst_r.split(poczatek)[0]
                po = tekst_r.split(koniec)[1]
                with open(sciezka, "w") as f:
                    f.write(przed + poczatek + "\n" + tabela(jezyk) + koniec + po)
        if shutil.which("inkscape"):
            subprocess.run(["inkscape", svg, "--export-type=png", "--export-width=1640",
                            "--export-filename=" + os.path.join(TU, f"bananapro-pinout{przyrostek}.png")],
                           check=True, capture_output=True)
        else:
            print("inkscape not found, PNG skipped")
        print("OK:", svg)


if __name__ == "__main__":
    main()
