#!/bin/bash
# CO: buduje pakiet armbian-watch_<wersja>_all.deb w katalogu dist/.
# Wersja pochodzi z WERSJA w armbian-watch.py, opiekun pakietu z git config
# (user.name, user.email) albo ze zmiennych DEBFULLNAME i DEBEMAIL.
# DLACZEGO dpkg-deb, a nie debhelper: program to jeden skrypt Pythona, bez
# kompilacji; dpkg-deb jest w kazdym Debianie i nie wymaga dodatkowych pakietow.
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
NAZWA=armbian-watch
WERSJA=$(sed -n 's/^WERSJA = "\(.*\)"$/\1/p' armbian-watch.py)
[[ -n "${WERSJA}" ]] || { echo "BLAD: brak WERSJA w armbian-watch.py" >&2; exit 1; }
IMIE=${DEBFULLNAME:-$(git config user.name 2>/dev/null || true)}
EMAIL=${DEBEMAIL:-$(git config user.email 2>/dev/null || true)}
[[ -n "${IMIE}" && -n "${EMAIL}" ]] || { echo "BLAD: ustaw DEBFULLNAME i DEBEMAIL (opiekun pakietu)" >&2; exit 1; }

python3 -m py_compile armbian-watch.py
rm -rf __pycache__

ROBOCZY=$(mktemp -d)
trap 'rm -rf "${ROBOCZY}"' EXIT
R="${ROBOCZY}/${NAZWA}_${WERSJA}_all"

# CO: pliki pakietu. Skrypt dostaje staly /usr/bin/python3 zamiast env,
# jak wymaga polityka Debiana (program ma uzywac systemowego Pythona).
install -Dm755 armbian-watch.py "${R}/usr/bin/${NAZWA}"
sed -i '1s|^#!.*|#!/usr/bin/python3|' "${R}/usr/bin/${NAZWA}"
install -Dm644 pakiet/armbian-watch.desktop "${R}/usr/share/applications/${NAZWA}.desktop"
install -Dm644 ikona/armbian-watch.svg "${R}/usr/share/icons/hicolor/scalable/apps/${NAZWA}.svg"
install -Dm644 README.md "${R}/usr/share/doc/${NAZWA}/README.md"
install -Dm644 README.pl.md "${R}/usr/share/doc/${NAZWA}/README.pl.md"
install -Dm644 pakiet/copyright "${R}/usr/share/doc/${NAZWA}/copyright"

ROZMIAR=$(du -sk --exclude=DEBIAN "${R}" | cut -f1)
mkdir -p "${R}/DEBIAN"
# DLACZEGO Conflicts/Replaces: do wersji 1.2.0 pakiet nazywal sie
# czujka-armbian; instalacja nowego usuwa stary (ustawienia, stan i autostart
# przenosi sam program przy pierwszym starcie).
cat > "${R}/DEBIAN/control" << EOF
Package: ${NAZWA}
Version: ${WERSJA}
Architecture: all
Maintainer: ${IMIE} <${EMAIL}>
Installed-Size: ${ROZMIAR}
Depends: python3 (>= 3.9), python3-pyqt6
Conflicts: czujka-armbian
Replaces: czujka-armbian
Section: utils
Priority: optional
Homepage: https://github.com/cyryllo/banana-a20
Description: tray monitor for GitHub, file directories and apt packages
 Armbian Watch sits in the system tray and checks at start and then every hour
 (configurable) the things you would otherwise keep looking at: new files in
 a directory on a web server, your GitHub pull requests, GitHub issues, new
 commits in chosen files of a branch, GitHub releases and the version of a
 package in an apt repository. When something changes it shows a desktop
 notification.
 .
 It started as a helper for Armbian board maintainers (waiting for test
 images before a release), so it ships Armbian templates, but it watches
 any GitHub project, any file directory and any apt repository.
 .
 The user interface is in Polish and English. Formerly named
 "Czujka Armbian" (package czujka-armbian). This is not an official
 Armbian project.
EOF

mkdir -p dist
dpkg-deb --root-owner-group --build "${R}" dist/ > /dev/null
PAKIET="dist/${NAZWA}_${WERSJA}_all.deb"
echo ">> ${PAKIET}"
dpkg-deb --info "${PAKIET}" | sed -n 's/^ \(Package\|Version\|Depends\|Installed-Size\):/  \1:/p'
