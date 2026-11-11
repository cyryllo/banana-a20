#!/bin/bash
# Bosman20: host drukarki 3D z Klipper, Moonraker, Mainsail i KlipperScreen.
# Uruchamiany w chroot obrazu przez customize-image.sh (zbuduj-obraz-pr.sh --klipper).
# Pliki z katalogu bosman20/ sa tu widoczne jako /tmp/overlay/bosman20/.
#
# CO: konto bosman, instalacja przez KIAUH (jak recznie na plytce), KlipperScreen
#     na ekranie LCD, siec przez NetworkManager, nazwa bosman20.local.
# DLACZEGO KIAUH: ten sam uklad katalogow i uslug co przy instalacji recznej,
#     wiec uzytkownik moze potem aktualizowac wszystko z menu KIAUH.

set -euo pipefail
SRC=/tmp/overlay/bosman20
UZ=bosman
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
# CO: narzedzia dla KIAUH i instalatorow; reszte zaleznosci KIAUH doinstaluje sam.
apt-get install -y -qq --no-install-recommends git sudo ca-certificates curl \
	network-manager avahi-daemon libnss-mdns polkitd > /dev/null

# CO: konto bosman/bosman z wymuszona zmiana hasla przy pierwszym logowaniu,
# root bez logowania haslem, bez kreatora Armbiana (jak w Arkada20).
# DLACZEGO te grupy: dialout = port szeregowy plytki drukarki (USB), video/input/
# render/tty = KlipperScreen (X11 i dotyk), netdev = siec z KlipperScreen.
rm -f /root/.not_logged_in_yet
useradd -m -s /bin/bash -G sudo,dialout,tty,video,input,render,audio,plugdev,netdev "${UZ}"
echo "${UZ}:${UZ}" | chpasswd

# CO: na czas budowania zastepczy systemctl.
# DLACZEGO: KIAUH i instalatory wolaja "sudo systemctl start/restart"; w chroot
# systemd nie dziala, wiec start konczylby instalacje bledem. Zastepczy systemctl
# pomija uruchamianie, a "enable" przekazuje dalej (dziala bez systemd).
install -m 0755 "${SRC}/systemctl-budowanie" /usr/local/sbin/systemctl

# CO: instalacja jako root z HOME/USER/LOGNAME uzytkownika bosman, potem pliki
# dostaja wlasciciela bosman (szczegoly w instaluj-stos.sh).
env HOME="/home/${UZ}" USER="${UZ}" LOGNAME="${UZ}" TERM=xterm PIP_FIND_LINKS="${SRC}/wheels" \
	bash "${SRC}/instaluj-stos.sh"
chown -R "${UZ}:${UZ}" "/home/${UZ}"

rm -f /usr/local/sbin/systemctl
chage -d 0 "${UZ}"
passwd -l root

# CO: siecia zarzadza NetworkManager (panel sieci w KlipperScreen ustawia Wi-Fi palcem).
# DLACZEGO wylaczone networkd: inaczej dwa programy zarzadzalyby tymi samymi kartami.
sed -i 's/renderer: networkd/renderer: NetworkManager/' /etc/netplan/*.yaml 2> /dev/null || true
systemctl disable systemd-networkd.service systemd-networkd-wait-online.service 2> /dev/null || true
systemctl enable NetworkManager.service avahi-daemon.service

# CO: nazwa w sieci bosman20 (Mainsail: http://bosman20.local).
echo bosman20 > /etc/hostname
sed -i 's/^127\.0\.1\.1\s.*/127.0.1.1\tbosman20/' /etc/hosts
grep -q '^127\.0\.1\.1' /etc/hosts || echo -e "127.0.1.1\tbosman20" >> /etc/hosts

# CO: wersje w obrazie (do opisu wydania i zrodel GPL).
{
	echo "Bosman20 $(date -u +%F)"
	for d in kiauh klipper moonraker KlipperScreen; do
		# DLACZEGO safe.directory: git jako root nie czyta repozytoriow innego uzytkownika.
		echo "${d} $(git -c safe.directory='*' -C "/home/${UZ}/${d}" log -1 --format='%h %cs' 2> /dev/null || echo brak)"
	done
	echo "mainsail $(cat "/home/${UZ}/mainsail/.version" 2> /dev/null || echo '?')"
} > /usr/local/share/bosman20-wersje.txt
cat /usr/local/share/bosman20-wersje.txt
