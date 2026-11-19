#!/bin/bash
# CO: buduje pakiet lemaker-screen_<wersja>_all.deb w katalogu dist/.
# Wersja z WERSJA w lemaker_screen.py, opiekun pakietu z git config (user.name,
# user.email) albo ze zmiennych DEBFULLNAME i DEBEMAIL.
# DLACZEGO dpkg-deb, a nie debhelper: to dwa skrypty Pythona bez kompilacji;
# dpkg-deb jest w kazdym Debianie i nie wymaga dodatkowych pakietow.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
NAZWA=lemaker-screen
WERSJA=$(sed -n 's/^WERSJA = "\(.*\)"$/\1/p' lemaker_screen.py)
[[ -n "${WERSJA}" ]] || { echo "BLAD: brak WERSJA w lemaker_screen.py" >&2; exit 1; }
IMIE=${DEBFULLNAME:-$(git config user.name 2>/dev/null || true)}
EMAIL=${DEBEMAIL:-$(git config user.email 2>/dev/null || true)}
[[ -n "${IMIE}" && -n "${EMAIL}" ]] || { echo "BLAD: ustaw DEBFULLNAME i DEBEMAIL (opiekun pakietu)" >&2; exit 1; }

python3 -m py_compile lemaker_screen.py lemaker_screen_gui.py
rm -rf __pycache__

ROBOCZY=$(mktemp -d)
trap 'rm -rf "${ROBOCZY}"' EXIT
R="${ROBOCZY}/${NAZWA}_${WERSJA}_all"

# CO: pliki pakietu.
# DLACZEGO /usr/bin/lemaker-screen jako plik, a nie dowiazanie: pkexec
# porownuje rzeczywista sciezke programu z regula polkit (exec.path).
install -Dm755 lemaker_screen.py "${R}/usr/bin/${NAZWA}"
install -Dm755 lemaker_screen_gui.py "${R}/usr/bin/${NAZWA}-gui"
install -Dm644 lemaker_screen.py "${R}/usr/share/${NAZWA}/lemaker_screen.py"
install -Dm644 pakiet/lemaker-screen.desktop "${R}/usr/share/applications/${NAZWA}.desktop"
install -Dm644 pakiet/lemaker-screen.svg "${R}/usr/share/icons/hicolor/scalable/apps/${NAZWA}.svg"
install -Dm644 pakiet/io.github.cyryllo.lemaker-screen.policy "${R}/usr/share/polkit-1/actions/io.github.cyryllo.lemaker-screen.policy"
install -Dm644 README.md "${R}/usr/share/doc/${NAZWA}/README.md"
install -Dm644 README.pl.md "${R}/usr/share/doc/${NAZWA}/README.pl.md"
install -Dm644 pakiet/copyright "${R}/usr/share/doc/${NAZWA}/copyright"

ROZMIAR=$(du -sk "${R}" | cut -f1)
mkdir -p "${R}/DEBIAN"
cat > "${R}/DEBIAN/control" << EOF
Package: ${NAZWA}
Version: ${WERSJA}
Architecture: all
Maintainer: ${IMIE} <${EMAIL}>
Installed-Size: ${ROZMIAR}
Depends: python3 (>= 3.9)
Recommends: python3-gi, gir1.2-gtk-3.0, pkexec | policykit-1
Section: utils
Priority: optional
Homepage: https://github.com/cyryllo/banana-a20
Description: settings for the LeMaker LCD panels on the Banana Pi / Banana Pro
 Choose the LeMaker 5" or 7" LCD panel (or HDMI only), set the brightness
 and reset the touch controller on a Banana Pi / Banana Pro with Armbian.
 It uses the official Armbian overlays lemaker-lcd5, lemaker-lcd7 and
 lemaker-lcd7-hdmi and edits /boot/armbianEnv.txt (with a backup).
 .
 Two front ends: the lemaker-screen command and a small GTK window
 (lemaker-screen-gui, "LeMaker screen" in the menu). English and Polish.
EOF

mkdir -p dist
dpkg-deb --root-owner-group --build "${R}" dist/ > /dev/null
PAKIET="dist/${NAZWA}_${WERSJA}_all.deb"
echo ">> ${PAKIET}"
dpkg-deb --info "${PAKIET}" | sed -n 's/^ \(Package\|Version\|Depends\|Recommends\|Installed-Size\):/  \1:/p'
