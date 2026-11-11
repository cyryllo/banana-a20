#!/bin/bash
# Buduje pakiety Pythona (wheels) dla Klippera, Moonrakera i KlipperScreen
# na Banana Pro (armhf, Debian 13, Python 3.13), na komputerze x86 w kontenerze
# ARM (emulacja QEMU).
#
# CO: pip wheel dla wszystkich wymagan z aktualnych repozytoriow
#     (klippy-requirements, moonraker-requirements + speedups, KlipperScreen).
# DLACZEGO: na armhf czesc pakietow nie ma gotowych wheels na PyPI, a piwheels
#     (gotowe wheels dla Raspberry Pi) potrafi nie dzialac (2026-11-11 zrywal
#     polaczenia SSL). Kompilacja na A20 trwa kilkadziesiat minut; w obrazie
#     KIAUH bierze gotowe pakiety z tego katalogu (PIP_FIND_LINKS).
#
# Uzycie: ./zbuduj-pakiety-python.sh [katalog_wyjsciowy]   (domyslnie ./wheels)
# Wynik: <katalog>/*.whl oraz WERSJE.txt (commity repozytoriow).

set -euo pipefail

SKRYPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OUT=$(realpath -m "${1:-${SKRYPT_DIR}/wheels}")
mkdir -p "${OUT}"
command -v docker > /dev/null || { echo "BLAD: brak dockera" >&2; exit 1; }

docker run --rm -i --platform linux/arm/v7 -v "${OUT}:/out" -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
	debian:trixie bash -euo pipefail << 'EOF'
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# CO: kompilator i biblioteki potrzebne do zbudowania rozszerzen C:
# greenlet/cffi (Klipper), pillow, uvloop, streaming-form-data (Moonraker),
# pycairo, PyGObject, sdbus (KlipperScreen).
apt-get install -y -qq --no-install-recommends \
	git ca-certificates build-essential pkg-config python3-dev python3-venv \
	libffi-dev libjpeg62-turbo-dev zlib1g-dev libfreetype-dev libopenjp2-7-dev \
	libcairo2-dev libgirepository1.0-dev libsystemd-dev libdbus-1-dev > /dev/null

cd /tmp
for r in Klipper3d/klipper Arksine/moonraker KlipperScreen/KlipperScreen; do
	git clone -q --depth 1 "https://github.com/${r}.git"
done
python3 -m venv /tmp/venv
/tmp/venv/bin/pip install -q --upgrade pip wheel setuptools

# CO: osobne "pip wheel" dla kazdego programu do jednego katalogu.
# DLACZEGO osobno: kazdy ma wlasne srodowisko Pythona i wymagania sie wykluczaja
# (Klipper: Jinja2 2.11.3, Moonraker: jinja2 3.1.6). Gotowe wheels z PyPI
# (np. czysto pythonowe) pip pobiera, reszte kompiluje.
for req in klipper/scripts/klippy-requirements.txt \
	"moonraker/scripts/moonraker-requirements.txt -r moonraker/scripts/moonraker-speedups.txt" \
	KlipperScreen/scripts/KlipperScreen-requirements.txt; do
	echo ">> pip wheel -r ${req}"
	# shellcheck disable=SC2086
	/tmp/venv/bin/pip wheel -q -w /out -r ${req}
done

{
	echo "Wheels dla Python $(python3 -V | cut -d' ' -f2), $(uname -m), $(date -u +%Y-%m-%d)"
	for d in klipper moonraker KlipperScreen; do
		echo "${d} $(git -C "${d}" log -1 --format='%h %cs')"
	done
} > /out/WERSJE.txt
chown -R "${HOST_UID}:${HOST_GID}" /out
EOF

echo ">> Gotowe: $(ls "${OUT}"/*.whl | wc -l) pakietow w ${OUT}"
cat "${OUT}/WERSJE.txt"
