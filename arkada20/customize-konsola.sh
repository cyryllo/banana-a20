#!/bin/bash
# Konsola do gier na Banana Pro: RetroArch na ekranie od startu (jak Lakka).
# Uruchamiany w chroot obrazu przez customize-image.sh (zbuduj-obraz-pr.sh --konsola).
# Pliki z katalogu arkada20/ sa tu widoczne jako /tmp/overlay/konsola/.

set -euo pipefail

SRC=/tmp/overlay/konsola
ROMS=/home/roms
LR=/usr/lib/arm-linux-gnueabihf/libretro
SHARE=/usr/share/libretro
# DLACZEGO v1.20.0: wersja Debianowych retroarch-assets/libretro-core-info; profile
# padow i bazy gier sa wydawane pod tym samym numerem. Nasz RetroArch jest nowszy
# (commit z master, zbuduj-retroarch.sh), ale z tymi plikami dziala poprawnie
# (sprawdzone na plytce 2026-11-12: ikony, gra z padem, Wi-Fi, dotyk).
WERSJA=v1.20.0

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

# CO: biblioteki dla naszego RetroArch, grafika menu, opisy rdzeni, NetworkManager.
# DLACZEGO nie RetroArch ani rdzenie z Debiana: Debianowy RetroArch nie ma dotyku
# ani Wi-Fi w menu, a kazdy rdzen z Debiana zalezy od niego (sciagnalby Qt i X11).
# libgl1-mesa-dri: sterownik lima dla Mesa. samba: udzial z grami jak w Lakce.
# network-manager: Wi-Fi z menu RetroArch (sterownik nmcli).
apt-get install -y --no-install-recommends \
	retroarch-assets libretro-core-info \
	libasound2t64 libfreetype6 libudev1 libgbm1 libdrm2 libgles2 libegl1 libgl1-mesa-dri \
	libxkbcommon0 xkb-data \
	alsa-utils samba curl ca-certificates network-manager avahi-daemon libnss-mdns wsdd2

# CO: nasz RetroArch (zbuduj-retroarch.sh): KMS + GLES, udev z dotykiem, Wi-Fi przez nmcli.
install -m 0755 "${SRC}/retroarch-bin/retroarch" /usr/local/bin/retroarch
install -m 0644 "${SRC}/retroarch-bin/WERSJA.txt" /usr/local/share/retroarch-konsola-wersja.txt

# CO: nasze rdzenie skompilowane przez zbuduj-rdzenie.sh.
mkdir -p "${LR}"
install -m 0644 "${SRC}"/rdzenie/*_libretro.so "${LR}/"
install -m 0644 "${SRC}/rdzenie/WERSJE.txt" "${LR}/WERSJE-konsola.txt"

# CO: czcionki menu XMB, Ozone i Material UI: DejaVu Sans zamiast Roboto.
# DLACZEGO: Debian zastepuje czcionki RetroArch dowiazaniami do Roboto, a Roboto
# nie ma znakow klawiszy specjalnych klawiatury ekranowej (U+21E6, U+21E7, U+21E9,
# U+2295, U+23CE: Backspace, Shift, nastepna strona, Enter); DejaVu Sans i Sans
# Bold maja wszystkie (sprawdzone fc-query). Ozone i Material UI nie maja
# ustawienia czcionki, wiec podmieniamy dowiazania; dpkg-divert pilnuje, zeby
# aktualizacja retroarch-assets ich nie przywrocila. RGUI ma wlasne symbole.
A=/usr/share/libretro/assets
F=/usr/share/fonts/truetype/dejavu
for para in "xmb/monochrome/font.ttf DejaVuSans.ttf" "ozone/regular.ttf DejaVuSans.ttf" \
	"ozone/bold.ttf DejaVuSans-Bold.ttf" "glui/font.ttf DejaVuSans.ttf"; do
	set -- ${para}
	dpkg-divert --local --rename --add --divert "${A}/$1.debian" "${A}/$1"
	ln -sfn "${F}/$2" "${A}/$1"
done

# CO: profile padow (automatyczne przypisanie przyciskow po podlaczeniu).
# DLACZEGO z GitHuba: Debian nie ma tego pakietu, bez profili kazdy pad
# trzeba by ustawic recznie w menu.
mkdir -p "${SHARE}/autoconfig"
curl -fsSL "https://github.com/libretro/retroarch-joypad-autoconfig/archive/refs/tags/${WERSJA}.tar.gz" |
	tar -xz -C "${SHARE}/autoconfig" --strip-components=1 "retroarch-joypad-autoconfig-${WERSJA#v}/udev"

# CO: wlasne profile padow, ktorych nie ma w bazie libretro (konsola/autoconfig/udev/*.cfg).
# DLACZEGO warunek: katalog moze byc pusty, a pusty wzorzec przerwalby skrypt (set -e).
if compgen -G "${SRC}/autoconfig/udev/*.cfg" > /dev/null; then
	cp "${SRC}"/autoconfig/udev/*.cfg "${SHARE}/autoconfig/udev/"
fi

# CO: bazy gier tylko dla obslugiwanych systemow.
# DLACZEGO: bez nich "Skanuj katalog" nie rozpozna gier i nie zrobi list
# z nazwami. Cale repozytorium baz ma kilkaset MB, potrzebne jest kilkanascie plikow.
mkdir -p "${SHARE}/database/rdb"
while read -r baza; do
	[[ -z "${baza}" ]] && continue
	curl -fsSL -o "${SHARE}/database/rdb/${baza}.rdb" \
		"https://raw.githubusercontent.com/libretro/libretro-database/${WERSJA}/rdb/${baza// /%20}.rdb"
done <<- 'EOF'
	Nintendo - Nintendo Entertainment System
	Nintendo - Super Nintendo Entertainment System
	Nintendo - Game Boy
	Nintendo - Game Boy Color
	Nintendo - Game Boy Advance
	Sega - Mega Drive - Genesis
	Sega - Master System - Mark III
	Sega - Game Gear
	Sega - 32X
	Sony - PlayStation
	MAME 2003-Plus
	FBNeo - Arcade Games
EOF

# CO: katalogi na gry, BIOS-y i zapisy, tworzone przy starcie systemu.
# DLACZEGO tmpfiles, a nie mkdir: Armbian czysci /home po customize-image
# (sprawdzone: w gotowym obrazie /home byl pusty). systemd-tmpfiles tworzy
# brakujace katalogi przy kazdym starcie, istniejacych nie rusza.
{
	echo "d ${ROMS} 0755 root root -"
	for d in nes snes gb gba megadrive mastersystem gamegear psx mame2003 fbneo bios zapisy zrzuty; do
		echo "d ${ROMS}/${d} 0755 root root -"
	done
	# DLACZEGO: bez tego katalogu RetroArch nie zapisuje logu (log_to_file).
	echo "d /root/.config/retroarch/logs 0755 root root -"
} > /etc/tmpfiles.d/konsola-roms.conf

# CO: nazwa w sieci bez znajomosci IP: avahi-daemon (mDNS: arkada20.local, Linux,
# Windows 10/11, macOS, telefony) i wsdd2 (konsola widoczna w "Sieci" Eksploratora
# Windows). DLACZEGO: sama Samba rozglasza nazwe tylko przez NetBIOS (nmbd), ktory
# nowe Windowsy czesto maja wylaczony, a Linux go nie uzywa.
install -m 0644 "${SRC}/avahi-samba.service" /etc/avahi/services/samba.service
systemctl enable avahi-daemon.service wsdd2.service

# CO: udzialy sieciowe bez hasla, jak w Lakce: \\arkada20\roms (gry), bios,
# zapisy (zapisy gier i stany) i zrzuty (zrzuty ekranu).
# DLACZEGO osobne udzialy, choc bios/zapisy/zrzuty leza w roms: od razu widac je
# w otoczeniu sieciowym, np. do kopii zapasowej zapisow.
# DLACZEGO force user = root: RetroArch dziala jako root, pliki z sieci
# musza miec tego samego wlasciciela. Udzialy sa widoczne tylko w sieci lokalnej.
# Bez udzialu z konfiguracja RetroArch: zapis bez hasla do konfiguracji mogl by
# zablokowac konsole.
for udzial in "roms:/home/roms:Gry dla RetroArch" "bios:/home/roms/bios:BIOS dla emulatorow" \
	"zapisy:/home/roms/zapisy:Zapisy gier i stany" "zrzuty:/home/roms/zrzuty:Zrzuty ekranu"; do
	IFS=: read -r nazwa sciezka opis <<< "${udzial}"
	cat >> /etc/samba/smb.conf <<- EOF

		[${nazwa}]
		   comment = ${opis}
		   path = ${sciezka}
		   browseable = yes
		   read only = no
		   guest ok = yes
		   force user = root
	EOF
done

# CO: konfiguracja RetroArch i usluga uruchamiajaca go na ekranie.
install -d /root/.config/retroarch
install -m 0644 "${SRC}/retroarch.cfg" /root/.config/retroarch/retroarch.cfg
install -m 0644 "${SRC}/retroarch-konsola.service" /etc/systemd/system/retroarch-konsola.service
install -m 0755 "${SRC}/konsola-listy" /usr/local/bin/konsola-listy
install -m 0755 "${SRC}/konsola-reset-dotyku" /usr/local/bin/konsola-reset-dotyku
# CO: gry startowe (opcja --gry), do /home/roms kopiuje je konsola-listy przy pierwszym starcie.
if [[ -d "${SRC}/gry" ]]; then
	mkdir -p /usr/local/share/konsola
	cp -r "${SRC}/gry" /usr/local/share/konsola/
fi
install -m 0644 "${SRC}/konsola-listy.service" "${SRC}/konsola-listy.path" /etc/systemd/system/
systemctl enable retroarch-konsola.service konsola-listy.path

# CO: siecia zarzadza NetworkManager zamiast systemd-networkd.
# DLACZEGO: menu Wi-Fi w RetroArch dziala przez nmcli. Kreator Armbiana zapisuje
# Wi-Fi do netplan bez "renderer", wiec dziedziczy domyslny z 10-dhcp-all-interfaces.yaml;
# po zmianie na NetworkManager siec z kreatora trafia do NetworkManagera, tak jak
# w obrazach Armbian z pulpitem.
# DLACZEGO wylaczone systemd-networkd-wait-online: bez urzadzen dla networkd czekalby
# przy kazdym starcie do 2 minut (na nim czekala Samba).
sed -i 's/renderer: networkd/renderer: NetworkManager/' /etc/netplan/*.yaml
systemctl disable systemd-networkd.service systemd-networkd-wait-online.service 2> /dev/null || true
systemctl enable NetworkManager.service

# CO: bez kreatora Armbiana; domyslne konto gracz/gracz z wymuszona zmiana hasla.
# DLACZEGO: konsola ma dzialac od razu po wlaczeniu, jak Lakka: Wi-Fi ustawia sie
# w menu RetroArch, a przez SSH loguje sie na gracz/gracz. System sam wymusza
# nowe haslo przy pierwszym logowaniu (chage -d 0), wiec domyslne nie zostaje.
# Root bez hasla do logowania (passwd -l), administracja przez sudo.
# Plik .not_logged_in_yet tworzy Armbian przed customize-image (distro-agnostic.sh).
rm -f /root/.not_logged_in_yet
useradd -m -s /bin/bash -G sudo,audio,video,input,render,plugdev,netdev gracz
echo "gracz:gracz" | chpasswd
chage -d 0 gracz
passwd -l root
# CO: konto Samby gracz/gracz do udzialow sieciowych.
# DLACZEGO: Windows 11 (od 24H2) blokuje dostep goscia, wymaga loginu i hasla.
# Samba ma wlasne hasla, niezalezne od systemowych (zmiana: sudo smbpasswd gracz).
printf 'gracz\ngracz\n' | smbpasswd -a -s gracz
# CO: katalog domowy gracza tworzony przy starcie z /etc/skel (C = kopiuj, jesli brak).
# DLACZEGO: Armbian czysci /home po customize-image, wiec useradd -m tu nie wystarcza
# (sprawdzone: w gotowym obrazie /home byl pusty).
cat > /etc/tmpfiles.d/konsola-gracz.conf <<- 'EOF'
	C /home/gracz - - - - /etc/skel
	Z /home/gracz - gracz gracz -
EOF

# CO: nazwa systemu w sieci: arkada20 (udzial z grami: \\arkada20\roms, SSH: gracz@arkada20).
# DLACZEGO: obraz konsoli to osobny system Arkada20, nazwa plytki (bananapipro)
# nic nie mowi uzytkownikowi szukajacemu konsoli w sieci.
echo arkada20 > /etc/hostname
sed -i 's/^127\.0\.1\.1.*/127.0.1.1\tarkada20/' /etc/hosts
grep -q "^127.0.1.1" /etc/hosts || printf '127.0.1.1\tarkada20\n' >> /etc/hosts

# CO: procesor zawsze na pelnej szybkosci (1 GHz).
# DLACZEGO: przy "ondemand" gra zaczyna sie od niskiego taktowania i pierwsze
# sekundy sie tna; A20 przy 1 GHz nie wymaga chlodzenia.
if [[ -f /etc/default/cpufrequtils ]]; then
	sed -i 's/^GOVERNOR=.*/GOVERNOR=performance/' /etc/default/cpufrequtils
fi

echo "konsola: $(ls "${LR}" | wc -l) rdzeni, $(ls "${SHARE}/autoconfig/udev" | wc -l) profili padow"
