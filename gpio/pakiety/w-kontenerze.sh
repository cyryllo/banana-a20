#!/bin/bash
# CO: druga czesc zbuduj-deb.sh, dziala w kontenerze arm32v7/debian:trixie.
# Kompiluje WiringBP, LMK.GPIO i lg, sklada pliki pakietow w /tmp/pakiety/<nazwa>
# i robi z nich .deb w /out.
# DLACZEGO wlasne kopiowanie plikow zamiast "make install": Makefile WiringBP
# wpisuje sciezki na sztywno (/usr/local), robi chown i ldconfig, a Makefile lg
# instaluje modul Pythona przez setup.py install; do pakietu potrzebujemy
# czystego drzewa plikow.
set -euo pipefail

echo ">> narzedzia do budowania"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    build-essential dpkg-dev python3-dev python3-setuptools python3-pip python3-wheel swig > /dev/null

MULTI=$(dpkg-architecture -qDEB_HOST_MULTIARCH)
ARCH=$(dpkg-architecture -qDEB_HOST_ARCH)
PY=$(python3 -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')
PY_NAST=$(python3 -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1] + 1}")')
PYDIR=/usr/lib/python3/dist-packages
B=/tmp/budowa
P=/tmp/pakiety
rm -rf "$B" "$P"
mkdir -p "$B" "$P"
cp -a /src/WiringBP /src/LMK.GPIO /src/lg "$B/"

# CO: dpkg-shlibdeps czyta debian/control z biezacego katalogu.
mkdir -p /tmp/sd/debian
printf 'Source: gpio\n\nPackage: gpio\nArchitecture: any\n' > /tmp/sd/debian/control

# CO: zaleznosci od bibliotek systemowych (libc6 i inne) dla plikow ELF.
# DLACZEGO --ignore-missing-info: nasze wlasne biblioteki (np. liblgpio.so.1)
# nie naleza jeszcze do zadnego pakietu; zaleznosc od nich dopisujemy recznie.
zaleznosci() {
    local katalog_lib=$1; shift
    (cd /tmp/sd && dpkg-shlibdeps -O --ignore-missing-info -l"$katalog_lib" "$@" 2> /dev/null) \
        | sed -n 's/^shlibs:Depends=//p'
}

# CO: plik copyright: naglowek + tekst licencji z projektu.
copyright() {
    local R=$1 nazwa=$2 zrodlo=$3 licencja=$4 plik=$5
    install -d "$R/usr/share/doc/$nazwa"
    {
        echo "Upstream: $zrodlo"
        echo "Packaging: https://github.com/cyryllo/banana-a20 (gpio/), with fixes for"
        echo " the Banana Pro on mainline Linux."
        echo "License: $licencja"
        echo
        cat "$plik"
    } > "$R/usr/share/doc/$nazwa/copyright"
}

# CO: sklada .deb z katalogu R. Argumenty: nazwa wersja R Depends sekcja opis [dodatkowe pola].
# Opis: pierwsza linia = krotki opis, kolejne linie = dluzszy opis.
pakiet() {
    local nazwa=$1 wersja=$2 R=$3 dep=$4 sekcja=$5 opis=$6 dodatki=${7:-}
    local krotki dlugi
    krotki=$(printf '%s\n' "$opis" | head -1)
    dlugi=$(printf '%s\n' "$opis" | tail -n +2 | sed 's/^$/./; s/^/ /')
    install -d "$R/DEBIAN"
    {
        echo "Package: $nazwa"
        echo "Version: $wersja"
        echo "Architecture: $ARCH"
        echo "Maintainer: $OPIEKUN"
        echo "Installed-Size: $(du -sk --exclude=DEBIAN "$R" | cut -f1)"
        echo "Depends: $dep"
        [[ -n "$dodatki" ]] && printf '%s\n' "$dodatki"
        echo "Section: $sekcja"
        echo "Priority: optional"
        echo "Homepage: https://github.com/cyryllo/banana-a20/tree/master/gpio"
        echo "Description: $krotki"
        echo "$dlugi"
    } > "$R/DEBIAN/control"
    dpkg-deb --root-owner-group -Zxz --build "$R" /out/ > /dev/null
    echo "   $nazwa $wersja"
}

# CO: wypakowuje kolo Pythona (wheel) do dist-packages.
# DLACZEGO kolo: pip buduje modul C dokladnie jak przy zwyklej instalacji,
# a kolo to tylko archiwum zip z gotowymi plikami i metadanymi.
wypakuj_kolo() {
    local kolo=$1 R=$2
    install -d "$R$PYDIR"
    python3 -m zipfile -e "$kolo" "$R$PYDIR"
    find "$R$PYDIR" -name '*.so' -exec strip --strip-unneeded {} +
    find "$R$PYDIR" -name 'RECORD' -path '*.dist-info/*' -delete
    find "$R$PYDIR" -type d -exec chmod 755 {} +
    find "$R$PYDIR" -type f -exec chmod 644 {} +
}

# ------------------------------------------------------------------ WiringBP
echo ">> WiringBP"
W=$B/WiringBP
make -s -C "$W/wiringPi" > /dev/null
make -s -C "$W/devLib" INCLUDE="-I. -I../wiringPi" > /dev/null
# DLACZEGO dowiazania: biblioteki maja soname "libwiringPi.so" (bez numeru),
# a linker szuka nazwy bez wersji.
ln -sf libwiringPi.so.2.0 "$W/wiringPi/libwiringPi.so"
ln -sf libwiringPiDev.so.2.0 "$W/devLib/libwiringPiDev.so"
make -s -C "$W/gpio" INCLUDE="-I../wiringPi -I../devLib" LDFLAGS="-L../wiringPi -L../devLib" gpio > /dev/null

R=$P/wiringbp
L=$R/usr/lib/$MULTI
install -d "$L" "$R/usr/include" "$R/usr/bin" "$R/usr/share/man/man1"
for lib in wiringPi/libwiringPi devLib/libwiringPiDev; do
    install -m 644 "$W/$lib.so.2.0" "$L/"
    strip --strip-unneeded "$L/$(basename "$lib").so.2.0"
    # DLACZEGO dowiazanie w pakiecie: soname bez numeru, wiec program szuka
    # przy uruchomieniu wlasnie pliku libwiringPi.so.
    ln -s "$(basename "$lib").so.2.0" "$L/$(basename "$lib").so"
done
install -m 644 "$W"/wiringPi/*.h "$W"/devLib/*.h "$R/usr/include/"
# DLACZEGO bez bitu setuid (oryginal mial 4755): instrukcja i tak uzywa
# "sudo gpio", a program z dostepem do /dev/mem nie powinien dawac roota kazdemu.
install -m 755 "$W/gpio/gpio" "$R/usr/bin/gpio"
strip "$R/usr/bin/gpio"
gzip -9n < "$W/gpio/gpio.1" > "$R/usr/share/man/man1/gpio.1.gz"
copyright "$R" wiringbp "https://github.com/LeMaker/WiringBP (WiringPi by Gordon Henderson)" \
    "LGPL-3.0-or-later" "$W/COPYING.LESSER"
# CO: ldconfig po instalacji bibliotek (odswieza cache bibliotek systemu).
install -d "$R/DEBIAN"; echo "activate-noawait ldconfig" > "$R/DEBIAN/triggers"
DEP=$(zaleznosci "$L" "$L"/*.so.2.0 "$R/usr/bin/gpio")
pakiet wiringbp 2.0-1 "$R" "$DEP" libs "WiringPi port for the Banana Pi / Banana Pro (C library and gpio command)
WiringBP is the LeMaker port of the WiringPi GPIO library for the Banana Pi
and Banana Pro (Allwinner A20), fixed for mainline Linux (Armbian): kernel
GPIO numbers for sysfs and interrupts, I2C bus detection, PWM that does not
switch off the LCD backlight.

The package has the shared libraries (libwiringPi, libwiringPiDev), the
headers for building programs and the gpio command (gpio readall). Most
commands need root: sudo gpio readall." \
"Conflicts: wiringpi"

# ------------------------------------------------------------------ LMK.GPIO
echo ">> LMK.GPIO"
(cd "$B/LMK.GPIO" && python3 -m pip wheel -q --no-deps --no-build-isolation -w "$B/kola" . 2>&1 | grep -v "^$" | grep -iv "warning\|deprecat" || true)
R=$P/python3-lmk-gpio
# DLACZEGO lmk_gpio: nowe setuptools zapisuja nazwe "LMK.GPIO" w kole jako lmk_gpio.
wypakuj_kolo "$(ls "$B"/kola/lmk_gpio-*.whl)" "$R"
copyright "$R" python3-lmk-gpio "https://github.com/LeMaker/LMK.GPIO" \
    "MIT (source files, LeMaker Team; based on RPi.GPIO by Ben Croston), GPL-2 (LICENSE file below)" \
    "$B/LMK.GPIO/LICENSE"
DEP=$(zaleznosci /nonexistent $(find "$R" -name '*.so'))
pakiet python3-lmk-gpio 0.0.1-1 "$R" "python3 (>= $PY~), python3 (<< $PY_NAST), $DEP" python \
"Python module LMK.GPIO for the Banana Pi / Banana Pro (RPi.GPIO style)
LMK.GPIO is the LeMaker port of RPi.GPIO for the Banana Pi and Banana Pro
(Allwinner A20), fixed for mainline Linux (Armbian) and Python 3.13: board
detection, kernel GPIO numbers, edge events and callbacks.

Usage: import LMK.GPIO as GPIO. Access to the pins needs root."

# ------------------------------------------------------------------ lg
echo ">> lg (lgpio, rgpio)"
G=$B/lg
make -s -C "$G" lib rgpiod rgs > /dev/null
R=$P/lgpio
L=$R/usr/lib/$MULTI
install -d "$L" "$R/usr/include" "$R/usr/bin" "$R/usr/share/man/man1" "$R/usr/share/man/man3"
for lib in liblgpio librgpio; do
    install -m 644 "$G/$lib.so.1" "$L/"
    ln -s "$lib.so.1" "$L/$lib.so"
done
install -m 644 "$G/lgpio.h" "$G/rgpio.h" "$R/usr/include/"
install -m 755 "$G/rgpiod" "$G/rgs" "$R/usr/bin/"
for m in rgpiod.1 rgs.1; do gzip -9n < "$G/$m" > "$R/usr/share/man/man1/$m.gz"; done
for m in lgpio.3 rgpio.3; do gzip -9n < "$G/$m" > "$R/usr/share/man/man3/$m.gz"; done
copyright "$R" lgpio "https://github.com/joan2937/lg" "Unlicense (public domain)" "$G/UNLICENCE"
# CO: ldconfig po instalacji bibliotek (odswieza cache bibliotek systemu).
install -d "$R/DEBIAN"; echo "activate-noawait ldconfig" > "$R/DEBIAN/triggers"
DEP=$(zaleznosci "$L" "$L"/*.so.1 "$R/usr/bin/rgpiod" "$R/usr/bin/rgs")
pakiet lgpio 0.2.2-1 "$R" "$DEP" libs "lg GPIO library (lgpio, rgpio) with the rgpiod daemon
lg by joan2937 (the author of pigpio) works through the kernel GPIO character
device, so it runs on any Linux board. This build includes a fix for GPIO
numbers above 255 in alerts, needed on the Banana Pro (most header pins are
in bank PI, lines 256 and up).

The package has liblgpio (local GPIO, I2C, SPI, serial, software PWM and
servo pulses), librgpio with the rgpiod daemon (the same over the network),
the rgs command and the headers."

echo ">> lg: Python (lgpio, rgpio)"
(cd "$G/PY_LGPIO" && LDFLAGS="-L$G" CFLAGS="-I$G" python3 -m pip wheel -q --no-deps --no-build-isolation -w "$B/kola" . 2>&1 | grep -iv "warning\|deprecat" || true)
(cd "$G/PY_RGPIO" && python3 -m pip wheel -q --no-deps --no-build-isolation -w "$B/kola" . 2>&1 | grep -iv "warning\|deprecat" || true)
R=$P/python3-lgpio
wypakuj_kolo "$(ls "$B"/kola/lgpio-*.whl)" "$R"
wypakuj_kolo "$(ls "$B"/kola/rgpio-*.whl)" "$R"
copyright "$R" python3-lgpio "https://github.com/joan2937/lg" "Unlicense (public domain)" "$G/UNLICENCE"
DEP=$(zaleznosci "$P/lgpio/usr/lib/$MULTI" $(find "$R" -name '*.so'))
pakiet python3-lgpio 0.2.2-1 "$R" "lgpio (= 0.2.2-1), python3 (>= $PY~), python3 (<< $PY_NAST), $DEP" python \
"Python modules lgpio and rgpio (lg GPIO library)
lgpio controls the GPIO, I2C, SPI and serial ports of this board; rgpio does
the same on a remote board through the rgpiod daemon. Both report alerts
(edges) with full GPIO numbers, also above 255 (Banana Pro bank PI)."

chown -R "$WLASCICIEL" /out
