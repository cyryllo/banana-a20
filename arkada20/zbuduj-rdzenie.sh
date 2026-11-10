#!/bin/bash
# Kompiluje rdzenie libretro dla Banana Pro (A20, Cortex-A7, armhf) na komputerze x86,
# w kontenerze Debiana 13 z kompilatorem krzyzowym arm-linux-gnueabihf.
#
# CO: rdzenie, ktorych nie ma w Debianie (MAME, FBNeo) albo ktore sa tam
# w ciezszych wersjach (lzejsze odpowiedniki dla slabego procesora).
# DLACZEGO sami: serwer libretro (buildbot) ma rdzenie armhf tylko z 2020 roku.
# DLACZEGO platform=rpi2: w Makefile'ach libretro to Cortex-A7 + NEON-VFPv4
# + hard-float, czyli dokladnie procesor A20; wlacza tez dynarec dla ARM.
#
# Uzycie: ./zbuduj-rdzenie.sh [katalog_wyjsciowy]   (domyslnie ./rdzenie)
# Wynik: <katalog>/*_libretro.so oraz WERSJE.txt (commity zrodel).

set -euo pipefail

SKRYPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OUT=$(realpath -m "${1:-${SKRYPT_DIR}/rdzenie}")
mkdir -p "${OUT}"
command -v docker > /dev/null || { echo "BLAD: brak dockera" >&2; exit 1; }

# CO: lista rdzeni: nazwa | repozytorium libretro | katalog z Makefile | plik Makefile | platforma
# DLACZEGO te: MAME 2003-Plus i FBNeo (automaty), FCEUmm (NES), Snes9x 2010 (SNES,
# lzejszy od pelnego Snes9x), gpSP (GBA z dynarec), PicoDrive (Mega Drive,
# Master System, 32X, Sega CD), PCSX ReARMed (PS1, dynarec i GPU na NEON),
# Gambatte (Game Boy, GBC), Genesis Plus GX (Game Gear).
# DLACZEGO nie rdzenie z Debiana: kazdy zalezy od pakietu retroarch, ktory
# sciagnalby Debianowy RetroArch z Qt i X11 obok naszego.
RDZENIE='
mame2003_plus|mame2003-plus-libretro|.|Makefile|rpi2
fbneo|FBNeo|src/burner/libretro|Makefile|rpi2
fceumm|libretro-fceumm|.|Makefile.libretro|unix
snes9x2010|snes9x2010|.|Makefile|unix
gpsp|gpsp|.|Makefile|rpi2
picodrive|picodrive|.|Makefile.libretro|rpi2
pcsx_rearmed|pcsx_rearmed|.|Makefile.libretro|rpi2
gambatte|gambatte-libretro|.|Makefile.libretro|rpi2
genesis_plus_gx|Genesis-Plus-GX|.|Makefile.libretro|rpi2
'

docker run --rm -i -v "${OUT}:/out" -e RDZENIE="${RDZENIE}" -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
	debian:trixie bash -euo pipefail << 'EOF'
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends crossbuild-essential-armhf git ca-certificates make python3 file > /dev/null
# DLACZEGO: PicoDrive buduje i uruchamia w trakcie kompilacji narzedzia ARM
# (generator Cyclone). Komputer uruchamia je przez qemu (binfmt), a ta zmienna
# wskazuje biblioteki ARM z kompilatora krzyzowego.
export QEMU_LD_PREFIX=/usr/arm-linux-gnueabihf
T=arm-linux-gnueabihf
# DLACZEGO flagi dla platform=unix: zwykly "unix" kompiluje dla ogolnego ARM,
# a z nimi kompilator moze uzyc NEON i instrukcji Cortex-A7.
FLAGI="-marm -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard"
: > /out/WERSJE.txt
while IFS='|' read -r nazwa repo katalog mk platforma; do
	[[ -z "${nazwa}" ]] && continue
	echo ">> ${nazwa}"
	git clone -q --depth 1 --recurse-submodules --shallow-submodules "https://github.com/libretro/${repo}.git" "/src/${nazwa}"
	cd "/src/${nazwa}/${katalog}"
	# DLACZEGO flagi w CC, a nie w CFLAGS: CFLAGS z linii polecen make zastepuje
	# wszystkie flagi z Makefile rdzenia (razem z potrzebnymi -D...).
	if [[ "${platforma}" == "unix" ]]; then
		opcje=(platform=unix CC="${T}-gcc ${FLAGI}" CXX="${T}-g++ ${FLAGI}")
	else
		opcje=(platform="${platforma}" CC="${T}-gcc" CXX="${T}-g++")
	fi
	opcje+=(AR="${T}-ar" STRIP="${T}-strip")
	make -f "${mk}" -j"$(nproc)" "${opcje[@]}" > "/out/${nazwa}.log" 2>&1 || { echo "BLAD kompilacji ${nazwa}, log: ${nazwa}.log"; continue; }
	so=$(ls -1 ./*_libretro.so | head -1)
	"${T}-strip" --strip-unneeded "${so}"
	cp "${so}" "/out/${nazwa}_libretro.so"
	echo "${nazwa} https://github.com/libretro/${repo} $(git -C /src/${nazwa} rev-parse --short HEAD) $(git -C /src/${nazwa} log -1 --format=%cs)" >> /out/WERSJE.txt
	rm -f "/out/${nazwa}.log"
done <<< "${RDZENIE}"
chown -R "${HOST_UID}:${HOST_GID}" /out
EOF

echo ">> Gotowe: ${OUT}"
cat "${OUT}/WERSJE.txt"
