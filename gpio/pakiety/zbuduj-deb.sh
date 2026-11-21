#!/bin/bash
# CO: buduje pakiety .deb bibliotek GPIO (WiringBP, LMK.GPIO, lg) dla
# Debiana 13 armhf. Wynik: gpio/pakiety/dist/*.deb.
# Opiekun pakietow z git config (user.name, user.email) albo ze zmiennych
# DEBFULLNAME i DEBEMAIL.
# DLACZEGO kontener arm32v7/debian:trixie (przez QEMU), a nie kompilacja
# krzyzowa: setup.py Pythona i SWIG buduja wtedy modul dla wlasciwego Pythona
# 3.13 armhf bez dodatkowej konfiguracji; biblioteki sa male, wiec emulacja
# trwa kilka minut.
# DLACZEGO obraz arm32v7/..., a nie debian:trixie z --platform: pobranie
# debian:trixie dla ARM nadpisuje lokalny obraz amd64, z ktorego korzystaja
# inne skrypty w repozytorium.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
GPIO=$(cd .. && pwd)
IMIE=${DEBFULLNAME:-$(git config user.name 2>/dev/null || true)}
EMAIL=${DEBEMAIL:-$(git config user.email 2>/dev/null || true)}
[[ -n "${IMIE}" && -n "${EMAIL}" ]] || { echo "BLAD: ustaw DEBFULLNAME i DEBEMAIL (opiekun pakietu)" >&2; exit 1; }

mkdir -p dist
rm -f dist/*.deb
docker run --rm --platform linux/arm/v7 \
    -e OPIEKUN="${IMIE} <${EMAIL}>" \
    -e WLASCICIEL="$(id -u):$(id -g)" \
    -v "${GPIO}:/src:ro" \
    -v "${PWD}/dist:/out" \
    arm32v7/debian:trixie bash /src/pakiety/w-kontenerze.sh

echo ">> pakiety w ${PWD}/dist:"
for p in dist/*.deb; do
    dpkg-deb --field "$p" Package Version Depends | sed 's/^/   /'
    echo
done
