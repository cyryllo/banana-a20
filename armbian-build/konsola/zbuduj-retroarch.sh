#!/bin/bash
# Kompiluje RetroArch dla Banana Pro (A20, armhf) na komputerze x86, w kontenerze
# Debiana 13 z kompilatorem krzyzowym i bibliotekami armhf (multiarch).
#
# CO: RetroArch bez X, Qt i Wayland: obraz przez KMS + EGL + OpenGL ES (lima),
# pady, klawiatura i dotyk przez udev, dzwiek ALSA, Wi-Fi w menu przez nmcli.
# DLACZEGO wlasny, a nie z Debiana: Debianowy RetroArch nie ma obslugi ekranu
# dotykowego (UDEV_TOUCH_SUPPORT nie jest nigdzie definiowane, trzeba podac
# przy kompilacji) ani sterownika Wi-Fi (--enable-wifi = sterownik nmcli).
# DLACZEGO v1.20.0: ta sama wersja co retroarch-assets, libretro-core-info,
# profile padow i bazy gier w obrazie.
#
# Uzycie: ./zbuduj-retroarch.sh [katalog_wyjsciowy]   (domyslnie ./retroarch-bin)
#         DODATKOWE_CFLAGS="-D..." ./zbuduj-retroarch.sh katalog   (np. wersja diagnostyczna)
#         LATKI_DIR=/inny/katalog ./zbuduj-retroarch.sh katalog    (inne latki niz latki-retroarch/)
#         Z_SYMBOLAMI=1 DODATKOWE_CFLAGS="-g" ./zbuduj-retroarch.sh katalog  (do gdb, bez strip)
# Wynik: <katalog>/retroarch oraz WERSJA.txt

set -euo pipefail

SKRYPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OUT=$(realpath -m "${1:-${SKRYPT_DIR}/retroarch-bin}")
WERSJA=v1.20.0
mkdir -p "${OUT}"
command -v docker > /dev/null || { echo "BLAD: brak dockera" >&2; exit 1; }

docker run --rm -i -v "${OUT}:/out" -v "${LATKI_DIR:-${SKRYPT_DIR}/latki-retroarch}:/latki:ro" -e WERSJA="${WERSJA}" -e DODATKOWE_CFLAGS="${DODATKOWE_CFLAGS:-}" -e Z_SYMBOLAMI="${Z_SYMBOLAMI:-}" -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
	debian:trixie bash -euo pipefail << 'EOF'
export DEBIAN_FRONTEND=noninteractive
T=arm-linux-gnueabihf
dpkg --add-architecture armhf
apt-get update -qq
# CO: kompilator krzyzowy i biblioteki armhf, z ktorymi RetroArch bedzie linkowany.
# DLACZEGO libxkbcommon: bez niej udev nie zamienia klawiszy na litery (UDEV_XKB_HANDLING
# wlacza sie tylko z HAVE_XKBCOMMON + HAVE_KMS) i nie da sie nic wpisac, np. hasla Wi-Fi.
apt-get install -y -qq --no-install-recommends \
	crossbuild-essential-armhf git ca-certificates make pkgconf file \
	libdrm-dev:armhf libgbm-dev:armhf libegl-dev:armhf libgles-dev:armhf \
	libudev-dev:armhf libasound2-dev:armhf libfreetype-dev:armhf zlib1g-dev:armhf \
	libxkbcommon-dev:armhf > /dev/null

# CO: pkg-config, ktory szuka bibliotek armhf zamiast bibliotek komputera.
cat > /usr/local/bin/${T}-pkg-config << 'PKG'
#!/bin/sh
export PKG_CONFIG_LIBDIR=/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/share/pkgconfig
exec pkgconf "$@"
PKG
chmod +x /usr/local/bin/${T}-pkg-config

git clone -q --depth 1 --branch "${WERSJA}" https://github.com/libretro/RetroArch.git /src
cd /src
# CO: nasze poprawki RetroArch (latki-retroarch/*.patch), np. dotyk w udev.
for l in /latki/*.patch; do
	[ -e "${l}" ] || continue
	git apply "${l}" && echo ">> latka: $(basename "${l}")" >> /out/WERSJA-latki.txt
done
# DLACZEGO te flagi: Cortex-A7 z NEON-VFPv4 (procesor A20) i obsluga dotyku w udev.
export CFLAGS="-marm -mcpu=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -O2 -DUDEV_TOUCH_SUPPORT ${DODATKOWE_CFLAGS}"
export CXXFLAGS="${CFLAGS}"
CROSS_COMPILE=${T}- ./configure --prefix=/usr \
	--disable-x11 --disable-wayland --disable-qt --disable-sdl2 --disable-sdl \
	--disable-vulkan --disable-opengl1 --disable-opengl_core \
	--enable-kms --enable-egl --enable-opengles --enable-opengles3 \
	--enable-udev --enable-alsa --disable-pulse --disable-jack --disable-pipewire --disable-oss \
	--enable-freetype --enable-neon --enable-floathard \
	--disable-ffmpeg --disable-v4l2 --disable-libusb --disable-dbus \
	--enable-wifi --enable-networking > /out/configure.log 2>&1 || { tail -30 /out/configure.log; exit 1; }
make -j"$(nproc)" > /out/make.log 2>&1 || { tail -30 /out/make.log; exit 1; }
[ -n "${Z_SYMBOLAMI}" ] || ${T}-strip retroarch
cp retroarch /out/retroarch
echo "RetroArch ${WERSJA} $(git rev-parse --short HEAD), CFLAGS: ${CFLAGS}" > /out/WERSJA.txt
cat /out/WERSJA-latki.txt >> /out/WERSJA.txt 2> /dev/null; rm -f /out/WERSJA-latki.txt
grep -E "HAVE_(KMS|EGL|OPENGLES|UDEV|ALSA|WIFI|FREETYPE|NEON|XKBCOMMON|X11|QT)\b" config.mk | tr '\n' ' ' >> /out/WERSJA.txt
rm -f /out/make.log
chown -R "${HOST_UID}:${HOST_GID}" /out
EOF

echo ">> Gotowe: ${OUT}/retroarch"
cat "${OUT}/WERSJA.txt"; echo
file "${OUT}/retroarch"
