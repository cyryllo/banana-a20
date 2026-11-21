#!/bin/bash
# Test obrazu Armbian (Debian albo Ubuntu) na Banana Pi Pro (LeMaker Banana Pro,
# Allwinner A20) przed wydaniem: lista kontrolna opiekuna plytki. Wiekszosc
# sprawdzen jest automatyczna, o reszte (obraz, dzwiek, dotyk, diody, przyciski)
# skrypt pyta. Na koncu zapisuje raport po angielsku (do forum Armbiana albo
# zgloszenia na GitHubie) i plik ze szczegolami (dmesg, listy urzadzen).
#
# Uzycie (na plytce):
#   sudo ./test-bananapipro.sh                  wszystkie testy z pytaniami
#   sudo ./test-bananapipro.sh --bez-pytan      tylko sprawdzenia automatyczne
#   sudo ./test-bananapipro.sh --minimalny      to, czego wymaga Armbian, bez zadnej interakcji
#                                               (bez ekranu LCD, GPIO, diod, pilota i przycisku)
#   sudo ./test-bananapipro.sh --tylko sata,gpio   wybrane moduly (lista: --lista)
#   sudo ./test-bananapipro.sh --przygotuj      narzedzia + nakladki pwm i spi-spidev do testow GPIO
#   sudo ./test-bananapipro.sh --ekrany         ekrany LeMaker po kolei (kilka restartow)
#   sudo ./test-bananapipro.sh --aktualizacja   najpierw apt full-upgrade, potem test
#   --maszynowo   wyjscie dla programu okienkowego (WYNIK|..., PYTANIE|..., CZEKAJ|...)
#
# DLACZEGO zapis na SATA tylko do pliku na zamontowanej partycji: na dysku moga
# byc dane uzytkownika; niezamontowanego dysku skrypt tylko czyta. Na karcie SD
# zapisuje plik 64 MB i od razu go usuwa.

set -u
export LC_ALL=C

WERSJA_TESTU="2.0"
ENV=/boot/armbianEnv.txt
STAN_EKRANOW=/var/lib/test-bananapipro/ekrany

# CO: moduly testu w kolejnosci wykonania. "ekrany" jest osobnym trybem (--ekrany).
MODULY=(system sd sata usb ethernet wifi siec obraz lcd dzwiek diody ir przycisk gpio obciazenie pakiety)
# CO: test minimalny: lista kontrolna wydania Armbiana, same sprawdzenia automatyczne.
MODULY_MINIMALNE="system,sd,sata,usb,ethernet,wifi,siec,obraz,dzwiek,obciazenie,pakiety"
opis_modulu() {
	case "$1" in
		system) echo "plytka, obraz, jadro, uslugi, bledy jadra, temperatura" ;;
		sd) echo "karta SD: szybkosc zapisu i odczytu, bledy" ;;
		sata) echo "dysk SATA: wykrycie, lacze, odczyt, zapis na zamontowanej partycji" ;;
		usb) echo "urzadzenia USB, odczyt z pendrive'a, klawiatura i mysz" ;;
		ethernet) echo "Ethernet: lacze 1000 Mb/s, adres" ;;
		wifi) echo "Wi-Fi: sterownik, wyszukiwanie sieci, polaczenie, sygnal" ;;
		siec) echo "brama i DNS" ;;
		obraz) echo "HDMI: monitor, tryb, obraz" ;;
		lcd) echo "ekran LeMaker (ustawiony teraz): panel, jasnosc, dotyk, budzenie dotykiem" ;;
		dzwiek) echo "dzwiek: jack, HDMI, mikrofon na plytce" ;;
		diody) echo "diody na plytce (zielona, niebieska)" ;;
		ir) echo "odbiornik podczerwieni (pilot)" ;;
		przycisk) echo "przycisk zasilania na plytce" ;;
		gpio) echo "GPIO: wolne piny (bez kabli), dioda, PWM, przycisk, UART, SPI, I2C" ;;
		obciazenie) echo "obciazenie procesora: temperatura, taktowanie, napiecie zasilania" ;;
		pakiety) echo "pakiety: jadro, stan dpkg/apt" ;;
	esac
}

PYTANIA=1
MINIMALNY=0
AKTUALIZACJA=0
MASZ=0
TRYB=test
WYBRANE=""
for a in "$@"; do
	case "${a}" in
		--bez-pytan) PYTANIA=0 ;;
		--minimalny) PYTANIA=0; WYBRANE="${MODULY_MINIMALNE}"; MINIMALNY=1 ;;
		--aktualizacja) AKTUALIZACJA=1 ;;
		--maszynowo) MASZ=1 ;;
		--przygotuj) TRYB=przygotuj ;;
		--ekrany) TRYB=ekrany ;;
		--tylko=*) WYBRANE="${a#--tylko=}" ;;
		--tylko) WYBRANE="?" ;;
		# CO: lista modulow: nazwa|opis|wymagany (1 = w tescie minimalnym, lista kontrolna Armbiana).
		--lista) for m in "${MODULY[@]}"; do w=0; [[ ",${MODULY_MINIMALNE}," == *",${m},"* ]] && w=1; echo "${m}|$(opis_modulu "${m}")|${w}"; done; exit 0 ;;
		-h | --pomoc) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*)
			if [[ "${WYBRANE}" == "?" ]]; then WYBRANE="${a}"
			else echo "Nieznana opcja: ${a} (--pomoc)" >&2; exit 1; fi ;;
	esac
done
[[ "${WYBRANE}" == "?" ]] && { echo "--tylko: podaj moduly, np. --tylko sata,gpio (--lista)" >&2; exit 1; }

if [[ ${EUID} -ne 0 ]]; then
	exec sudo "$0" "$@"
fi

# CO: czy modul ma byc wykonany (wszystkie albo te z --tylko).
chce() { [[ -z "${WYBRANE}" || ",${WYBRANE}," == *",$1,"* ]]; }

# CO: raport i szczegoly w katalogu domowym uzytkownika, ktory uruchomil sudo
# (pkexec ustawia PKEXEC_UID zamiast SUDO_USER).
UZYTKOWNIK=${SUDO_USER:-}
[[ -z "${UZYTKOWNIK}" && -n "${PKEXEC_UID:-}" ]] && UZYTKOWNIK=$(id -nu "${PKEXEC_UID}")
UZYTKOWNIK=${UZYTKOWNIK:-root}
DOM=$(getent passwd "${UZYTKOWNIK}" | cut -d: -f6)
CZAS=$(date +%Y%m%d-%H%M)
PRZEDROSTEK="${DOM}/raport-bananapipro"
[[ "${TRYB}" == "ekrany" ]] && PRZEDROSTEK="${DOM}/raport-bananapipro-ekrany"
RAPORT="${PRZEDROSTEK}-${CZAS}.md"
SZCZEGOLY="${PRZEDROSTEK}-${CZAS}-szczegoly.txt"

WYNIKI=()   # "STATUS|obszar|test|szczegoly"
if [[ -t 1 && ${MASZ} -eq 0 ]]; then
	K_OK=$'\e[32m'; K_BLAD=$'\e[31m'; K_UWAGA=$'\e[33m'; K_POMIN=$'\e[90m'; K_0=$'\e[0m'
else
	K_OK=""; K_BLAD=""; K_UWAGA=""; K_POMIN=""; K_0=""
fi

# ======================================================================
# Wyjscie i pytania. W trybie --maszynowo kazda linia ma przedrostek, a odpowiedzi
# przychodza na standardowe wejscie (program okienkowy); inaczej z /dev/tty.
# DLACZEGO osobny tryb: okno uruchamia skrypt przez pkexec, bez terminala.
# ======================================================================

info() { if [[ ${MASZ} -eq 1 ]]; then echo "INFO|$*"; else echo "$*"; fi; }

# CO: zapisuje wynik jednego testu. STATUS: PASS, FAIL, WARN, SKIP.
wynik() {
	local status="$1" obszar="$2" test="$3" opis="${4:-}"
	WYNIKI+=("${status}|${obszar}|${test}|${opis}")
	[[ -n "${PLIK_WYNIKOW:-}" ]] && echo "${status}|${obszar}|${test}|${opis}" >> "${PLIK_WYNIKOW}"
	if [[ ${MASZ} -eq 1 ]]; then
		echo "WYNIK|${status}|${obszar}|${test}|${opis}"
		return
	fi
	local k="${K_OK}"
	case "${status}" in FAIL) k="${K_BLAD}" ;; WARN) k="${K_UWAGA}" ;; SKIP) k="${K_POMIN}" ;; esac
	printf '%s%-4s%s  %-9s %s%s\n' "${k}" "${status}" "${K_0}" "${obszar}" "${test}" "${opis:+: ${opis}}"
}

# CO: dopisuje wynik polecenia do pliku ze szczegolami.
zapisz() {
	{ echo "===== $1"; shift; "$@" 2>&1; echo; } >> "${SZCZEGOLY}"
}

# CO: pytanie tak/nie/pomin. Zwraca 0 = tak, 1 = nie, 2 = pomin.
zapytaj() {
	local odp
	while true; do
		if [[ ${MASZ} -eq 1 ]]; then
			echo "PYTANIE|$1"
			read -r odp || return 2
		else
			read -r -p ">>> $1 [t]ak / [n]ie / [p]omin: " odp < /dev/tty || return 2
		fi
		case "${odp,,}" in t | tak | y | yes) return 0 ;; n | nie | no) return 1 ;; p | pomin | s | skip | "") [[ ${MASZ} -eq 1 || -n "${odp}" ]] && return 2 ;; esac
	done
}

# CO: prosba o przygotowanie (np. "podlacz pilota"), czeka na potwierdzenie.
czekaj() {
	if [[ ${MASZ} -eq 1 ]]; then
		echo "CZEKAJ|$1"
		read -r _ || true
	else
		read -r -p ">>> $1 (Enter) " _ < /dev/tty || true
	fi
}

# CO: pytanie, ktorego wynik od razu trafia do raportu.
pytanie() {
	local obszar="$1" test="$2" tresc="$3"
	if [[ ${PYTANIA} -eq 0 ]]; then
		wynik SKIP "${obszar}" "${test}" "not asked (--bez-pytan)"
		return 2
	fi
	zapytaj "${tresc}"
	local r=$?
	case ${r} in
		0) wynik PASS "${obszar}" "${test}" "confirmed by the tester" ;;
		1) wynik FAIL "${obszar}" "${test}" "reported as not working by the tester" ;;
		*) wynik SKIP "${obszar}" "${test}" "skipped by the tester" ;;
	esac
	return ${r}
}

naglowek() { [[ ${MASZ} -eq 1 ]] && echo "MODUL|$1" || { echo; echo "== $1: $(opis_modulu "$1")"; }; }

ma() { command -v "$1" > /dev/null 2>&1; }

# CO: tekst z drzewa urzadzen (/proc/device-tree) bez bajtow zerowych.
# DLACZEGO funkcja: przy braku pliku "tr < plik 2>/dev/null" i tak wypisuje blad,
# bo przekierowanie wejscia jest wykonywane przed przekierowaniem bledow.
dt() { [[ -r "$1" ]] && tr -d '\0' < "$1"; }

# CO: szybkosc odczytu urzadzenia blokowego (MB/s), tylko odczyt.
odczyt_mbs() {
	dd if="$1" of=/dev/null bs=1M count="${2:-200}" iflag=direct 2>&1 | awk '/copied/ {print $(NF-1), $NF}'
}

# CO: zapis i odczyt pliku testowego w katalogu $1 (MB = $2). Wypisuje "zapis|odczyt".
zapis_odczyt() {
	local plik="$1/.test-bananapipro.$$" z c
	z=$(dd if=/dev/zero of="${plik}" bs=1M count="$2" conv=fsync 2>&1 | awk '/copied/ {print $(NF-1), $NF}')
	sync; echo 3 > /proc/sys/vm/drop_caches
	c=$(dd if="${plik}" of=/dev/null bs=1M 2>&1 | awk '/copied/ {print $(NF-1), $NF}')
	rm -f "${plik}"
	echo "${z}|${c}"
}

# CO: urzadzenie wejscia (/dev/input/eventN) po fragmencie nazwy z /proc/bus/input/devices.
urzadzenie_wejscia() {
	awk -v w="$1" 'tolower($0) ~ "^n: name=.*" tolower(w) {f=1} f && /^H: Handlers=/ {match($0, /event[0-9]+/); print "/dev/input/" substr($0, RSTART, RLENGTH); exit}' /proc/bus/input/devices
}

# CO: liczy zdarzenia z urzadzenia wejscia przez N sekund.
# Argumenty: urzadzenie sekundy typ kod [wartosc] [wylacznie]. Wypisuje: liczba;wartosci (do 8 roznych).
# "wylacznie" = EVIOCGRAB: zdarzenia dostaje tylko test, nie pulpit ani systemd
# (bez tego przycisk POWER wylacza system przez menedzera zasilania pulpitu).
# DLACZEGO wlasny czytnik: evtest nie zawsze jest w obrazie, a python3 jest zawsze
# (netplan z niego korzysta).
licz_zdarzenia() {
	python3 - "$@" << 'PY'
import os, select, struct, sys, time
dev, sek, typ, kod = sys.argv[1], float(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
wart = int(sys.argv[5]) if len(sys.argv) > 5 and sys.argv[5] != "-" else None
fmt = "llHHi"; size = struct.calcsize(fmt)
fd = os.open(dev, os.O_RDONLY | os.O_NONBLOCK)
if len(sys.argv) > 6 and sys.argv[6] == "wylacznie":
    import fcntl
    fcntl.ioctl(fd, 0x40044590, 1)   # EVIOCGRAB
koniec = time.time() + sek; n = 0; wartosci = []
while time.time() < koniec:
    r, _, _ = select.select([fd], [], [], max(0, koniec - time.time()))
    if not r:
        break
    try:
        dane = os.read(fd, size * 64)
    except BlockingIOError:
        continue
    for i in range(0, len(dane) - size + 1, size):
        _, _, t, k, v = struct.unpack(fmt, dane[i:i + size])
        if t == typ and k == kod and (wart is None or v == wart):
            n += 1
            if v not in wartosci and len(wartosci) < 8:
                wartosci.append(v)
print("%d;%s" % (n, " ".join("0x%x" % w for w in wartosci)))
PY
}

# ======================================================================
# Ustawienia ekranu w /boot/armbianEnv.txt (tryb --ekrany).
# DLACZEGO wlasna funkcja, a nie lemaker-screen: test ma dzialac na czystym
# obrazie, bez dodatkowych pakietow; zasady takie same jak w lemaker-screen.
# ======================================================================
ustaw_ekran() {
	python3 - "${ENV}" "$1" << 'PY'
import sys
plik, ekran = sys.argv[1], sys.argv[2]
nakl = {"5": "lemaker-lcd5", "7": "lemaker-lcd7", "7-hdmi": "lemaker-lcd7-hdmi", "off": None}[ekran]
linie = open(plik).read().splitlines()
def slowa(klucz):
    for l in linie:
        if l.startswith(klucz + "="):
            return l.split("=", 1)[1].split()
    return []
def ustaw(klucz, s):
    global linie
    nowe, jest = [], False
    for l in linie:
        if l.startswith(klucz + "="):
            if s and not jest:
                nowe.append(klucz + "=" + " ".join(s))
            jest = True
        else:
            nowe.append(l)
    if s and not jest:
        nowe.append(klucz + "=" + " ".join(s))
    linie = nowe
ov = [o for o in slowa("overlays") if not o.startswith("lemaker-lcd")]
if nakl:
    ov.append(nakl)
ustaw("overlays", ov)
ustaw("user_overlays", [o for o in slowa("user_overlays") if "lemaker-lcd" not in o])
ex = [s for s in slowa("extraargs") if not s.startswith("video=HDMI-A-1:")]
if ekran in ("5", "7-hdmi"):
    ex.append("video=HDMI-A-1:1920x1080@60")
ustaw("extraargs", ex)
open(plik + ".tmp", "w").write("\n".join(linie) + "\n")
import os
os.replace(plik + ".tmp", plik)
PY
}

# CO: ekran, ktory naprawde dziala (z drzewa urzadzen): off, 5, 7, 7-hdmi.
ekran_dzialajacy() {
	local z hz
	z=$(dt /proc/device-tree/lemaker-lcd-panel/compatible)
	[[ -z "${z}" ]] && { echo off; return; }
	if [[ "${z}" == *panel-lvds* ]]; then
		hz=$(od -An -tu4 --endian=big -N4 /proc/device-tree/lemaker-lcd-panel/panel-timing/clock-frequency 2> /dev/null | tr -d ' ')
		if [[ -n "${hz}" && ${hz} -lt 50000000 ]]; then echo 7-hdmi; else echo 7; fi
	else
		echo 5
	fi
}

opis_ekranu() {
	case "$1" in
		5) echo '5" RGB 800x480 (with HDMI 1080p)' ;;
		7) echo '7" LVDS 1024x600' ;;
		7-hdmi) echo '7" LVDS 1024x600 with HDMI 1080p' ;;
		off) echo "no LCD (HDMI only)" ;;
	esac
}

# ======================================================================
# Moduly testu
# ======================================================================

m_system() {
	. /etc/armbian-release 2> /dev/null || true
	. /etc/os-release 2> /dev/null || true
	MODEL=$(dt /proc/device-tree/model)
	JADRO=$(uname -r)
	OBRAZ="${IMAGE_TYPE:-?} ${VERSION:-?} ${BRANCH:-?}, ${PRETTY_NAME:-?}"
	if [[ "${MODEL}" == *"Banana Pro"* || "${MODEL}" == *"Banana Pi"* ]]; then
		wynik PASS System "board" "${MODEL}"
	else
		wynik WARN System "board" "${MODEL:-unknown}, this test is written for the Banana Pi Pro"
	fi
	wynik PASS System "image" "Armbian ${OBRAZ}, kernel ${JADRO}"
	wynik PASS System "overlays" "${OVERLAYS:-none}"

	local stan nieudane bledy pamiec t f
	stan=$(systemctl is-system-running 2> /dev/null)
	nieudane=$(systemctl --failed --no-legend --plain 2> /dev/null | awk '{print $1}' | tr '\n' ' ')
	zapisz "systemctl --failed" systemctl --failed
	if [[ -z "${nieudane// /}" ]]; then
		wynik PASS System "services" "${stan}, no failed units"
	else
		wynik FAIL System "services" "failed units: ${nieudane}"
	fi
	ma systemd-analyze && wynik PASS System "boot time" "$(systemd-analyze 2> /dev/null | head -1 | sed 's/Startup finished in //')"

	zapisz "dmesg (err and worse)" dmesg -l err,crit,alert,emerg
	zapisz "dmesg (full)" dmesg
	bledy=$(dmesg -l err,crit,alert,emerg 2> /dev/null | wc -l)
	if [[ ${bledy} -eq 0 ]]; then
		wynik PASS System "kernel errors" "none in dmesg"
	else
		wynik WARN System "kernel errors" "${bledy} lines in dmesg (err and worse), see details"
	fi

	pamiec=$(awk '/MemTotal/ {printf "%d MB", $2/1024}' /proc/meminfo)
	wynik PASS System "memory" "${pamiec}"
	if [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
		t=$(($(cat /sys/class/thermal/thermal_zone0/temp) / 1000))
		if [[ ${t} -lt 75 ]]; then wynik PASS System "temperature" "${t} C"; else wynik WARN System "temperature" "${t} C"; fi
	else
		wynik SKIP System "temperature" "no thermal zone"
	fi
	if [[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq ]]; then
		f=/sys/devices/system/cpu/cpu0/cpufreq
		wynik PASS System "cpufreq" "$(cat ${f}/scaling_governor), $(($(cat ${f}/scaling_min_freq) / 1000))-$(($(cat ${f}/scaling_max_freq) / 1000)) MHz, $(nproc) cores"
	else
		wynik WARN System "cpufreq" "no cpufreq"
	fi
}

m_sd() {
	local root wz mmc
	root=$(findmnt -no SOURCE /)
	wynik PASS Storage "root filesystem" "${root}, $(df -h / | awk 'NR==2 {print $4 " free of " $2}')"
	wz=$(zapis_odczyt /var/tmp 64)
	if [[ "${wz}" != "|" && "${wz}" != *"||"* && -n "${wz%%|*}" && -n "${wz##*|}" ]]; then
		wynik PASS Storage "SD card speed" "write ${wz%%|*}, read ${wz##*|} (64 MB file)"
	else
		wynik FAIL Storage "SD card speed" "write or read test failed"
	fi
	mmc=$(dmesg | grep -ciE 'mmc[0-9].*(error|timeout|fail)')
	if [[ ${mmc} -eq 0 ]]; then wynik PASS Storage "SD card errors" "none in dmesg"; else wynik WARN Storage "SD card errors" "${mmc} mmc error lines in dmesg"; fi
}

m_sata() {
	local sata model s lacze cel wolne wz
	zapisz "lsblk" lsblk -o NAME,TRAN,SIZE,MODEL,FSTYPE,MOUNTPOINT
	zapisz "dmesg ata/ahci" sh -c "dmesg | grep -iE 'ahci|ata[0-9]'"
	sata=$(lsblk -dno NAME,TRAN | awk '$2=="sata" {print $1}' | head -1)
	if [[ -z "${sata}" ]]; then
		if dmesg | grep -qi 'ahci'; then
			wynik SKIP SATA "disk detected" "AHCI driver loaded, no disk connected"
		else
			wynik FAIL SATA "disk detected" "no AHCI messages in dmesg"
		fi
		return
	fi
	model=$(lsblk -dno MODEL "/dev/${sata}" | xargs)
	wynik PASS SATA "disk detected" "/dev/${sata} ${model} $(lsblk -dno SIZE "/dev/${sata}")"
	lacze=$(dmesg | grep -oE 'SATA link up [0-9.]+ Gbps' | tail -1)
	[[ -n "${lacze}" ]] && wynik PASS SATA "link" "${lacze}"
	s=$(odczyt_mbs "/dev/${sata}" 300)
	if [[ -n "${s}" ]]; then wynik PASS SATA "read speed" "${s} (300 MB, raw read)"; else wynik FAIL SATA "read speed" "read failed"; fi
	# CO: zapis tylko do pliku na zamontowanej, zapisywalnej partycji z co najmniej 1 GB wolnego.
	cel=$(lsblk -lno MOUNTPOINT "/dev/${sata}" | grep -v '^$' | while read -r mp; do
		wolne=$(df -Pm "${mp}" | awk 'NR==2 {print $4}')
		[[ ${wolne:-0} -ge 1024 && -w "${mp}" ]] && { echo "${mp}"; break; }
	done)
	if [[ -n "${cel}" ]]; then
		wz=$(zapis_odczyt "${cel}" 512)
		if [[ -n "${wz%%|*}" && -n "${wz##*|}" ]]; then
			wynik PASS SATA "write and read" "write ${wz%%|*}, read ${wz##*|} (512 MB file on ${cel}, deleted)"
		else
			wynik FAIL SATA "write and read" "failed on ${cel}"
		fi
	else
		wynik SKIP SATA "write and read" "no mounted partition with 1 GB free (the test never writes to an unmounted disk)"
	fi
	if dmesg | grep -qiE 'ata[0-9].*(hard resetting|failed command|exception Emask)'; then
		wynik WARN SATA "link errors" "ata resets or errors in dmesg (cable or power supply?)"
	else
		wynik PASS SATA "link errors" "none in dmesg"
	fi
}

m_usb() {
	local n nazwy dysk s
	ma lsusb && zapisz "lsusb" lsusb
	n=$(find /sys/bus/usb/devices -maxdepth 1 -name '[0-9]*-[0-9]*' ! -name '*:*' | wc -l)
	nazwy=$(for d in /sys/bus/usb/devices/[0-9]*-[0-9]*; do [[ "$d" == *:* ]] && continue; [[ -r "$d/product" ]] && cat "$d/product"; done 2> /dev/null | tr '\n' ',' | sed 's/,$//; s/,/, /g')
	if [[ ${n} -gt 0 ]]; then
		wynik PASS USB "devices" "${n}: ${nazwy}"
	else
		wynik WARN USB "devices" "no USB device connected, connect a USB stick or keyboard to test the ports"
	fi
	dysk=$(lsblk -dno NAME,TRAN | awk '$2=="usb" {print $1}' | head -1)
	if [[ -n "${dysk}" ]]; then
		s=$(odczyt_mbs "/dev/${dysk}" 100)
		if [[ -n "${s}" ]]; then wynik PASS USB "storage read speed" "/dev/${dysk}: ${s} (100 MB, read only)"; else wynik FAIL USB "storage read speed" "read failed"; fi
	else
		wynik SKIP USB "storage read speed" "no USB storage connected"
	fi
	[[ ${PYTANIA} -eq 1 ]] && pytanie USB "keyboard and mouse" "Czy klawiatura i mysz USB dzialaja (jesli podlaczone)?"
}

m_ethernet() {
	local eth pr ip4
	eth=$(ls /sys/class/net | grep -E '^(end|eth)' | head -1)
	if [[ -z "${eth}" ]]; then wynik FAIL Ethernet "interface" "no Ethernet interface"; return; fi
	if [[ "$(cat /sys/class/net/${eth}/carrier 2> /dev/null)" == "1" ]]; then
		pr=$(cat /sys/class/net/${eth}/speed 2> /dev/null)
		ip4=$(ip -4 -br addr show "${eth}" | awk '{print $3}')
		if [[ "${pr}" == "1000" ]]; then wynik PASS Ethernet "link" "${eth} ${pr} Mb/s ${ip4}"
		else wynik WARN Ethernet "link" "${eth} ${pr} Mb/s ${ip4} (expected 1000, check the cable or switch)"; fi
	else
		wynik SKIP Ethernet "link" "${eth} present, no cable connected"
	fi
}

m_wifi() {
	local wlan ster sieci ssid syg pr brama straty
	zapisz "dmesg brcmfmac" sh -c "dmesg | grep -i brcmf"
	wlan=$(ls /sys/class/net | grep -E '^wl' | head -1)
	if [[ -z "${wlan}" ]]; then wynik FAIL Wi-Fi "interface" "no wireless interface"; return; fi
	ster=$(basename "$(readlink -f /sys/class/net/${wlan}/device/driver)" 2> /dev/null)
	wynik PASS Wi-Fi "interface" "${wlan}, driver ${ster:-?}"
	ip link set "${wlan}" up 2> /dev/null
	sieci=""
	if ma nmcli; then
		sieci=$(nmcli -t -f SSID dev wifi list --rescan yes 2> /dev/null | grep -c .)
	elif ma iw; then
		sieci=$(iw dev "${wlan}" scan 2> /dev/null | grep -c 'SSID:')
	fi
	if [[ -z "${sieci}" ]]; then wynik SKIP Wi-Fi "scan" "no nmcli or iw"
	elif [[ "${sieci}" -gt 0 ]]; then wynik PASS Wi-Fi "scan" "${sieci} networks found"
	else wynik FAIL Wi-Fi "scan" "no networks found"; fi
	# CO: polaczenie ustawia tester (kreator pierwszego uruchomienia albo armbian-config),
	# skrypt tylko sprawdza, czy dziala.
	if ! ma iw || ! iw dev "${wlan}" link 2> /dev/null | grep -q '^Connected'; then
		wynik SKIP Wi-Fi "connection" "not connected; connect with armbian-config (Network) or nmtui and run the test again"
		return
	fi
	zapisz "iw link" iw dev "${wlan}" link
	ssid=$(iw dev "${wlan}" link | awk -F': ' '/SSID/ {print $2}')
	syg=$(iw dev "${wlan}" link | awk '/signal/ {print $2}')
	pr=$(iw dev "${wlan}" link | awk -F': ' '/tx bitrate/ {print $2}' | awk '{print $1, $2}')
	wynik PASS Wi-Fi "connection" "${ssid}, signal ${syg} dBm, link ${pr}"
	brama=$(ip route show dev "${wlan}" | awk '/^default/ {print $3; exit}')
	if [[ -n "${brama}" ]]; then
		straty=$(ping -I "${wlan}" -c 20 -i 0.2 -W 2 "${brama}" 2> /dev/null | grep -oE '[0-9.]+% packet loss' | cut -d% -f1)
		if [[ "${straty%.*}" == "0" ]]; then wynik PASS Wi-Fi "ping gateway" "20 packets over ${wlan}, 0% loss"
		elif [[ -n "${straty}" && ${straty%.*} -le 10 ]]; then wynik WARN Wi-Fi "ping gateway" "${straty}% loss over ${wlan}"
		else wynik FAIL Wi-Fi "ping gateway" "${straty:-100}% loss over ${wlan}"; fi
	else
		wynik WARN Wi-Fi "ping gateway" "no default route over ${wlan}"
	fi
}

m_siec() {
	local brama
	brama=$(ip route | awk '/^default/ {print $3; exit}')
	if [[ -n "${brama}" ]] && ping -c 3 -W 2 "${brama}" > /dev/null 2>&1; then
		wynik PASS Network "gateway" "${brama} answers"
	else
		wynik FAIL Network "gateway" "no default route or no answer"
	fi
	if getent hosts apt.armbian.com > /dev/null 2>&1; then wynik PASS Network "DNS" "apt.armbian.com resolves"; else wynik FAIL Network "DNS" "apt.armbian.com does not resolve"; fi
}

m_obraz() {
	local c n st tryb
	HDMI_POL=0
	for c in /sys/class/drm/card*-*; do
		[[ -e "$c/status" ]] || continue
		n=$(basename "$c" | sed 's/^card[0-9]*-//')
		st=$(cat "$c/status"); tryb=$(head -1 "$c/modes" 2> /dev/null)
		zapisz "drm ${n} modes" cat "$c/modes"
		case "${n}" in
			HDMI*)
				if [[ "${st}" == "connected" ]]; then HDMI_POL=1; wynik PASS Display "${n}" "connected, ${tryb:-no modes}"
				else wynik SKIP Display "${n}" "no monitor connected"; fi ;;
			Writeback*) ;;
			*)
				if [[ "${st}" == "connected" ]]; then wynik PASS Display "${n}" "connected, ${tryb:-no modes}"
				else wynik SKIP Display "${n}" "${st}"; fi ;;
		esac
	done
	[[ ${HDMI_POL} -eq 1 ]] && pytanie Display "HDMI picture" "Czy obraz na monitorze HDMI jest poprawny (bez migania, ostry)?"
}

# CO: testy ekranu LeMaker, ktory jest ustawiony teraz. Uzywany tez w trybie --ekrany.
m_lcd() {
	local lcd panel bl stary maks zdarz stuk bledy
	lcd=$(echo "${OVERLAYS}" | grep -oE 'lemaker-lcd[0-9a-z-]*' | head -1)
	if [[ -z "${lcd}" ]]; then wynik SKIP LCD "LeMaker panel" "no lemaker-lcd overlay enabled"; return; fi
	panel=$(dt /proc/device-tree/lemaker-lcd-panel/compatible)
	if [[ -n "${panel}" ]]; then wynik PASS LCD "overlay ${lcd}" "panel node: ${panel}"
	else wynik FAIL LCD "overlay ${lcd}" "no lemaker-lcd-panel node in the device tree"; return; fi
	pytanie LCD "LCD picture" "Czy obraz na ekranie LeMaker jest poprawny (kolory, bez szumu i migania)?"

	bl=$(ls -d /sys/class/backlight/* 2> /dev/null | head -1)
	if [[ -n "${bl}" ]]; then
		stary=$(cat "${bl}/brightness"); maks=$(cat "${bl}/max_brightness")
		wynik PASS LCD "backlight" "$(basename "${bl}") ${stary}/${maks}"
		if [[ ${PYTANIA} -eq 1 ]]; then
			echo $((maks * 20 / 100)) > "${bl}/brightness"; sleep 2
			echo "${maks}" > "${bl}/brightness"; sleep 2
			echo "${stary}" > "${bl}/brightness"
			pytanie LCD "brightness" "Czy ekran przygasl, potem rozjasnil sie na maksimum i wrocil do poprzedniej jasnosci?"
		fi
	else
		wynik FAIL LCD "backlight" "no backlight device"
	fi

	if dmesg | grep -q 'input: generic ft5x06'; then
		wynik PASS LCD "touch driver" "$(dmesg | grep -o 'input: generic ft5x06.*' | tail -1 | cut -c1-40)"
	else
		wynik FAIL LCD "touch driver" "no 'input: generic ft5x06' in dmesg"
	fi
	if ls /proc/device-tree/soc/i2c@*/touchscreen@38/vcc-supply > /dev/null 2>&1; then
		wynik PASS LCD "touch supply (wake by touch)" "vcc-supply set (#11337)"
	else
		wynik WARN LCD "touch supply (wake by touch)" "no vcc-supply, touch cannot wake a blanked screen"
	fi
	bledy=$(dmesg | grep -c 'edt_ft5x06.*Unable to fetch data')
	[[ ${bledy} -gt 0 ]] && wynik WARN LCD "touch errors" "${bledy} 'Unable to fetch data' in dmesg"

	zdarz=$(urzadzenie_wejscia ft5x06)
	if [[ ${PYTANIA} -eq 1 && -n "${zdarz}" ]]; then
		czekaj "Test dotyku: po potwierdzeniu masz 15 sekund, stuknij w ekran LCD dokladnie 5 razy, spokojnie"
		stuk=$(licz_zdarzenia "${zdarz}" 15 1 330 1 | cut -d';' -f1)
		if [[ "${stuk}" == "5" ]]; then wynik PASS LCD "touch taps" "5 taps, 5 touches reported"
		elif [[ "${stuk}" == "0" ]]; then wynik FAIL LCD "touch taps" "5 taps, no touch reported"
		else wynik WARN LCD "touch taps" "5 taps, ${stuk} touches reported (phantom or missed touches)"; fi
		pytanie LCD "touch area" "Czy dotyk reaguje w calym obszarze ekranu, takze w rogach (np. w menu pulpitu)?"
	fi

	# CO: budzenie dotykiem, tylko z pulpitem (wygaszenie przez X jako uzytkownik pulpitu).
	if [[ ${PYTANIA} -eq 1 ]] && systemctl is-active --quiet display-manager 2> /dev/null; then
		if sudo -u "${UZYTKOWNIK}" env DISPLAY=:0 xset dpms force off 2> /dev/null; then
			czekaj "Ekran zgasl. Odczekaj 5 sekund, dotknij ekranu LCD i potwierdz"
			pytanie LCD "wake by touch" "Czy dotyk obudzil ekran?"
		else
			pytanie LCD "wake by touch" "Wygas ekran w terminalu pulpitu (xset dpms force off) i dotknij go. Czy dotyk obudzil ekran?"
		fi
	fi
}

# CO: 3 s tonu 440 Hz na karcie $1. Zwraca 0 = zagrane, 2 = karta zajeta, 1 = blad.
# DLACZEGO: na pulpicie serwer dzwieku (PipeWire/PulseAudio) trzyma karte; wtedy
# test wprost na karcie nie jest mozliwy, a to nie jest blad plytki.
graj() {
	local w
	w=$(timeout 4 speaker-test -D "plughw:CARD=$1" -c 2 -t sine -f 440 -l 1 2>&1)
	[[ "${w}" == *busy* ]] && return 2
	[[ "${w}" == *"Playback open error"* ]] && return 1
	return 0
}

m_dzwiek() {
	local karty analog hdmi_k plik rms r
	zapisz "asound cards" cat /proc/asound/cards
	karty=$(awk -F'[][]' '/^ *[0-9]+ \[/ {gsub(/ +$/,"",$2); print $2}' /proc/asound/cards 2> /dev/null | paste -sd, | sed 's/,/, /g')
	if [[ -n "${karty}" ]]; then wynik PASS Audio "sound cards" "${karty}"; else wynik FAIL Audio "sound cards" "no ALSA cards"; return; fi
	[[ ${PYTANIA} -eq 1 ]] || return
	if ! ma speaker-test || ! ma arecord; then wynik SKIP Audio "sound tests" "no alsa-utils (sudo ./test-bananapipro.sh --przygotuj)"; return; fi
	analog=$(awk -F'[][]' '/^ *[0-9]+ \[/ && tolower($0) ~ /codec|audio/ && tolower($0) !~ /hdmi/ {gsub(/ +$/,"",$2); print $2; exit}' /proc/asound/cards)
	hdmi_k=$(awk -F'[][]' '/^ *[0-9]+ \[/ && tolower($0) ~ /hdmi/ {gsub(/ +$/,"",$2); print $2; exit}' /proc/asound/cards)
	if [[ -n "${analog}" ]]; then
		czekaj "Za chwile 3 sekundy dzwieku na wyjsciu jack (${analog}). Podlacz sluchawki albo glosnik"
		amixer -c "${analog}" sset 'Power Amplifier' 80% unmute > /dev/null 2>&1
		amixer -c "${analog}" sset 'Power Amplifier DAC' on > /dev/null 2>&1
		amixer -c "${analog}" sset 'Power Amplifier Mute' on > /dev/null 2>&1
		graj "${analog}"; r=$?
		if [[ ${r} -eq 2 ]]; then
			wynik SKIP Audio "analog output" "card busy (sound server of the desktop); test it in the desktop sound settings"
			return
		fi
		pytanie Audio "analog output" "Czy slychac bylo dzwiek w obu kanalach?"
		# CO: mikrofon na plytce: nagranie 3 s, glosnosc liczona automatycznie, potem odtworzenie.
		czekaj "Test mikrofonu na plytce: po potwierdzeniu mow cos przez 3 sekundy blisko plytki"
		amixer -c "${analog}" sset 'Mic1' cap 80% > /dev/null 2>&1
		amixer -c "${analog}" sset 'Mic1 Boost' 50% > /dev/null 2>&1
		amixer -c "${analog}" sset 'ADC Gain' 80% > /dev/null 2>&1
		amixer -c "${analog}" sset 'Mic1 Capture Switch' on > /dev/null 2>&1
		plik=/tmp/test-mikrofon.$$.wav
		arecord -D "plughw:CARD=${analog}" -f S16_LE -r 44100 -c 1 -d 3 "${plik}" > /dev/null 2>&1
		zapisz "amixer ${analog}" amixer -c "${analog}"
		rms=$(python3 -c '
import array, sys, wave
w = wave.open(sys.argv[1]); d = array.array("h", w.readframes(w.getnframes()))
print(int((sum(x * x for x in d) / max(len(d), 1)) ** 0.5))' "${plik}" 2> /dev/null)
		if [[ -z "${rms}" ]]; then wynik FAIL Audio "microphone level" "recording failed"
		elif [[ ${rms} -lt 30 ]]; then wynik WARN Audio "microphone level" "RMS ${rms}: silence (mixer settings or no microphone)"
		else wynik PASS Audio "microphone level" "RMS ${rms}"; fi
		info "Odtwarzam nagranie na wyjsciu jack..."
		aplay -D "plughw:CARD=${analog}" "${plik}" > /dev/null 2>&1
		rm -f "${plik}"
		pytanie Audio "microphone" "Czy w nagraniu bylo slychac Twoj glos?"
	else
		wynik SKIP Audio "analog output" "no analog card"
	fi
	if [[ -n "${hdmi_k}" && ${HDMI_POL:-0} -eq 1 ]]; then
		czekaj "Za chwile 3 sekundy dzwieku przez HDMI (${hdmi_k}). Wlacz glosnik monitora"
		graj "${hdmi_k}"; r=$?
		if [[ ${r} -eq 2 ]]; then wynik SKIP Audio "HDMI audio" "card busy (sound server of the desktop); test it in the desktop sound settings"
		else pytanie Audio "HDMI audio" "Czy z monitora HDMI bylo slychac dzwiek?"; fi
	else
		wynik SKIP Audio "HDMI audio" "no HDMI monitor or no HDMI sound card"
	fi
}

m_diody() {
	local d nazwa trig jasn i
	local diody=()
	for d in /sys/class/leds/*; do
		[[ -e "${d}/trigger" ]] || continue
		nazwa=$(basename "${d}")
		[[ "${nazwa}" == *mmc* || "${nazwa}" == *input* ]] && continue
		diody+=("${d}")
	done
	if [[ ${#diody[@]} -eq 0 ]]; then wynik FAIL LED "board LEDs" "no LEDs in /sys/class/leds"; return; fi
	wynik PASS LED "board LEDs" "found: $(for d in "${diody[@]}"; do basename "$d"; done | paste -sd, | sed 's/,/, /g')"
	for d in "${diody[@]}"; do
		nazwa=$(basename "${d}")
		trig=$(grep -o '\[[^]]*\]' "${d}/trigger" | tr -d '[]')
		jasn=$(cat "${d}/brightness")
		# CO: dioda miga w tle; z pytaniami az do odpowiedzi, bez pytan przez 3 s.
		# DLACZEGO reczne miganie: jadro nie zawsze ma wyzwalacz "timer".
		echo none > "${d}/trigger"
		( while true; do echo 1 > "${d}/brightness"; sleep 0.2; echo 0 > "${d}/brightness"; sleep 0.2; done ) &
		local miganie=$!
		if [[ ${PYTANIA} -eq 1 ]]; then
			pytanie LED "${nazwa}" "Dioda ${nazwa} na plytce powinna teraz szybko migac. Czy miga?"
		else
			info "Dioda ${nazwa} miga przez 3 sekundy..."
			sleep 3
			wynik SKIP LED "${nazwa}" "blinked for 3 s, not confirmed (no questions)"
		fi
		kill "${miganie}" 2> /dev/null; wait "${miganie}" 2> /dev/null
		echo "${trig:-none}" > "${d}/trigger" 2> /dev/null
		echo "${jasn}" > "${d}/brightness" 2> /dev/null
	done
}

m_ir() {
	local rc wej proto w n kody
	rc=$(ls -d /sys/class/rc/rc* 2> /dev/null | head -1)
	if [[ -z "${rc}" ]]; then wynik FAIL IR "receiver" "no remote controller device in /sys/class/rc"; return; fi
	wynik PASS IR "receiver" "found: $(basename "${rc}"), $(grep -o 'DRV_NAME=.*' "${rc}/uevent" | cut -d= -f2)"
	# CO: wlacza wszystkie dekodery pilotow, zeby kazdy pilot dal kody (scancode).
	proto=$(tr -d '[]' < "${rc}/protocols")
	for w in ${proto}; do echo "+${w}" > "${rc}/protocols" 2> /dev/null; done
	wej=$(ls -d "${rc}"/input*/event* 2> /dev/null | head -1)
	if [[ -z "${wej}" ]]; then wynik FAIL IR "remote" "no input device for $(basename "${rc}")"; return; fi
	if [[ ${PYTANIA} -eq 1 ]]; then
		czekaj "Test pilota: po potwierdzeniu masz 10 sekund, naciskaj rozne przyciski pilota skierowanego na plytke"
	else
		info "Test pilota: przez 10 sekund naciskaj przyciski pilota skierowanego na plytke"
	fi
	w=$(licz_zdarzenia "/dev/input/$(basename "${wej}")" 10 4 4)
	n=${w%%;*}; kody=${w#*;}
	if [[ ${n} -gt 0 ]]; then wynik PASS IR "remote" "${n} codes received (${kody})"
	elif [[ ${PYTANIA} -eq 1 ]]; then wynik FAIL IR "remote" "no codes received"
	else wynik SKIP IR "remote" "no codes in 10 s (nobody pressed?)"; fi
}

m_przycisk() {
	local wej n
	wej=$(urzadzenie_wejscia axp20x-pek)
	if [[ -z "${wej}" ]]; then wynik FAIL Button "power button" "no axp20x-pek input device"; return; fi
	if [[ ${PYTANIA} -eq 1 ]]; then
		czekaj "Test przycisku zasilania: po potwierdzeniu masz 10 sekund, nacisnij KROTKO przycisk POWER na plytce (test przejmuje przycisk, system sie nie wylaczy)"
	else
		info "Test przycisku zasilania: przez 10 sekund mozesz nacisnac KROTKO przycisk POWER (system sie nie wylaczy)"
	fi
	# DLACZEGO systemd-inhibit: bez tego logind wylaczylby plytke po nacisnieciu.
	systemd-inhibit --what=handle-power-key --who=test-bananapipro --why="power button test" --mode=block sleep 13 &
	local blokada=$!
	sleep 0.5
	n=$(licz_zdarzenia "${wej}" 10 1 116 1 wylacznie | cut -d';' -f1)
	kill "${blokada}" 2> /dev/null; wait "${blokada}" 2> /dev/null
	if [[ ${n:-0} -gt 0 ]]; then wynik PASS Button "power button" "${n} presses reported (KEY_POWER)"
	elif [[ ${PYTANIA} -eq 1 ]]; then wynik FAIL Button "power button" "no KEY_POWER event"
	else wynik SKIP Button "power button" "no press in 10 s (nobody pressed?)"; fi
}

# ---------------------------------------------------------------------- GPIO
# CO: piny zlacza 40-pin Banana Pro: "pin:GPIO jadra:nazwa".
# DLACZEGO bez pinu 40 (PB8): to wlacznik zasilania 5 V dysku SATA.
PINY_GPIO=(3:53:PB21 5:52:PB20 7:226:PH2 8:228:PH4 10:229:PH5 11:275:PI19 12:259:PI3 13:274:PI18
	15:273:PI17 16:244:PH20 18:245:PH21 19:268:PI12 21:269:PI13 22:272:PI16 23:267:PI11 24:266:PI10
	26:270:PI14 27:257:PI1 28:256:PI0 29:35:PB3 31:277:PI21 32:276:PI20 33:45:PB13 35:39:PB7 36:38:PB6
	37:37:PB5 38:44:PB12)

# CO: odczyt linii z wlaczonym podciaganiem (pull-up / pull-down). Wypisuje 0, 1 albo "zajety".
# DLACZEGO dwie skladnie: Debian 13 ma libgpiod 2.x, Ubuntu 24.04 ma 1.6.
gpio_odczyt() {
	local linia=$1 bias=$2 w
	if [[ ${GPIOD_V2} -eq 1 ]]; then
		w=$(gpioget -c gpiochip0 -b "${bias}" --numeric "${linia}" 2>&1)
	else
		w=$(gpioget -B "${bias}" gpiochip0 "${linia}" 2>&1)
	fi
	case "${w}" in 0 | 1) echo "${w}" ;; *busy*) echo zajety ;; *) echo blad ;; esac
}
gpio_ustaw() {
	if [[ ${GPIOD_V2} -eq 1 ]]; then gpioset -c gpiochip0 -t 0 "$1=$2"; else gpioset gpiochip0 "$1=$2"; fi
}

# CO: urzadzenie (tty, i2c, pwm) po adresie kontrolera w drzewie urzadzen.
po_adresie() { for d in $1; do [[ "$(readlink -f "$d/device" 2> /dev/null)" == *"$2"* ]] && { basename "$d"; return; }; done; }

m_gpio() {
	local p pin lin naz gora dol ok=0 zle="" zajete="" n pwm uart spi i2c w
	if ! ma gpioget; then wynik SKIP GPIO "tools" "no gpiod (sudo ./test-bananapipro.sh --przygotuj)"; return; fi
	GPIOD_V2=0; gpioget --version 2>&1 | grep -q 'v2\.' && GPIOD_V2=1
	wynik PASS GPIO "tools" "$(gpioget --version 2>&1 | head -1)"

	# --- A: wolne piny, bez kabli: podciaganie w gore = 1, w dol = 0
	# DLACZEGO tylko piny "MUX UNCLAIMED": sterownik pinow A20 pozwala pobrac jako
	# GPIO takze pin pracujacy w innej funkcji i przestawia go na wejscie; to
	# psuje I2C (dotyk LCD), UART i SPI az do restartu. Piny z funkcja pomijamy.
	local pinmux=/sys/kernel/debug/pinctrl/1c20800.pinctrl/pinmux-pins
	[[ -r "${pinmux}" ]] || mount -t debugfs none /sys/kernel/debug 2> /dev/null
	if [[ ! -r "${pinmux}" ]]; then
		wynik SKIP GPIO "free pins, pull-up/down" "cannot read ${pinmux} (debugfs), pins not touched"
	else
	[[ ${PYTANIA} -eq 1 ]] && czekaj "Test pinow GPIO bez kabli: ODLACZ wszystko od zlacza 40-pin i potwierdz"
	for p in "${PINY_GPIO[@]}"; do
		IFS=: read -r pin lin naz <<< "${p}"
		if ! grep -q "^pin ${lin} (${naz}): (MUX UNCLAIMED)" "${pinmux}"; then
			zajete+="${pin} "
			continue
		fi
		gora=$(gpio_odczyt "${lin}" pull-up); dol=$(gpio_odczyt "${lin}" pull-down)
		if [[ "${gora}" == zajety || "${dol}" == zajety ]]; then zajete+="${pin} "
		elif [[ "${gora}" == 1 && "${dol}" == 0 ]]; then ok=$((ok + 1))
		else zle+="${pin}(${naz}:${gora}/${dol}) "; fi
	done
	if [[ -z "${zle}" ]]; then wynik PASS GPIO "free pins, pull-up/down" "${ok} pins OK; not touched (used by I2C/UART/SPI/LCD...): ${zajete:-none}"
	else wynik FAIL GPIO "free pins, pull-up/down" "${ok} OK, wrong: ${zle}; not touched: ${zajete:-none}"; fi
	fi

	[[ ${PYTANIA} -eq 1 ]] || return
	# --- B: dioda na pinie 11
	if zapytaj "Masz diode z opornikiem (np. 330 om) miedzy pinem 11 a GND (pin 9)?"; then
		for n in 1 2 3 4 5; do gpio_ustaw 275 1; sleep 0.3; gpio_ustaw 275 0; sleep 0.3; done
		pytanie GPIO "output (LED on pin 11)" "Czy dioda na pinie 11 mrugnela 5 razy?"
	else
		wynik SKIP GPIO "output (LED on pin 11)" "no LED connected"
	fi
	# --- C: sprzetowe PWM na pinie 12 (kanal 1 kontrolera 1c20e00)
	pwm=$(po_adresie "/sys/class/pwm/pwmchip*" 1c20e00)
	if [[ -n "${pwm}" ]] && grep -qw pwm "${ENV}" 2> /dev/null && zapytaj "Masz diode z opornikiem miedzy pinem 12 a GND (pin 14)?"; then
		w=/sys/class/pwm/${pwm}
		[[ -d ${w}/pwm1 ]] || echo 1 > "${w}/export"; sleep 0.2
		echo 1000000 > "${w}/pwm1/period"; echo 0 > "${w}/pwm1/duty_cycle"; echo 1 > "${w}/pwm1/enable"
		for n in 1 2; do
			for p in 0 10 20 30 40 50 60 70 80 90 100 90 80 70 60 50 40 30 20 10 0; do echo $((p * 10000)) > "${w}/pwm1/duty_cycle"; sleep 0.08; done
		done
		echo 0 > "${w}/pwm1/enable"; echo 1 > "${w}/unexport"
		pytanie GPIO "hardware PWM (pin 12)" "Czy dioda na pinie 12 dwa razy plynnie sie rozjasnila i zgasla?"
	else
		wynik SKIP GPIO "hardware PWM (pin 12)" "no 'pwm' overlay (--przygotuj) or no LED"
	fi
	# --- D: przycisk na pinie 13 (do GND), wejscie z przerwaniem
	if zapytaj "Masz przycisk miedzy pinem 13 a GND (pin 14)?"; then
		czekaj "Po potwierdzeniu masz 15 sekund: nacisnij przycisk dokladnie 3 razy"
		if [[ ${GPIOD_V2} -eq 1 ]]; then
			n=$(timeout 15 gpiomon -c gpiochip0 -b pull-up -e falling -p 30ms -n 3 274 2> /dev/null | grep -c .)
		else
			n=$(timeout 15 gpiomon -B pull-up -f -n 3 gpiochip0 274 2> /dev/null | grep -c .)
		fi
		if [[ ${n} -eq 3 ]]; then wynik PASS GPIO "input interrupt (button on pin 13)" "3 presses, 3 falling edges"
		else wynik FAIL GPIO "input interrupt (button on pin 13)" "3 presses, ${n} falling edges"; fi
	else
		wynik SKIP GPIO "input interrupt (button on pin 13)" "no button connected"
	fi
	# --- E: UART4 na pinach 8 (TX) i 10 (RX), mostek
	uart=$(po_adresie "/sys/class/tty/ttyS*" 1c29000)
	if [[ -n "${uart}" ]] && zapytaj "Polacz kabelkiem pin 8 z pinem 10 (UART). Gotowe?"; then
		w=$(python3 - "/dev/${uart}" << 'PY'
import os, sys, termios, time, select
fd = os.open(sys.argv[1], os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
a = termios.tcgetattr(fd)
a[0] = 0; a[1] = 0; a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL; a[3] = 0
a[4] = a[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, a); termios.tcflush(fd, termios.TCIOFLUSH)
dane = b"BananaPro UART loopback 0123456789"
os.write(fd, dane); odb = b""; koniec = time.time() + 2
while len(odb) < len(dane) and time.time() < koniec:
    if select.select([fd], [], [], 0.2)[0]:
        odb += os.read(fd, 64)
print("ok" if odb == dane else "zle:%r" % odb[:20])
PY
)
		if [[ "${w}" == ok ]]; then wynik PASS GPIO "UART loopback (pins 8-10)" "/dev/${uart} 115200, data matches"
		else wynik FAIL GPIO "UART loopback (pins 8-10)" "/dev/${uart}: ${w}"; fi
	else
		wynik SKIP GPIO "UART loopback (pins 8-10)" "no UART4 device or no wire"
	fi
	# --- F: SPI0 na pinach 19 (MOSI) i 21 (MISO), mostek
	spi=$(ls /dev/spidev0.* 2> /dev/null | head -1)
	if [[ -n "${spi}" ]] && zapytaj "Polacz kabelkiem pin 19 z pinem 21 (SPI). Gotowe?"; then
		w=$(python3 - "${spi}" << 'PY'
import array, fcntl, os, struct, sys
fd = os.open(sys.argv[1], os.O_RDWR)
tx = bytes(range(0x30, 0x50)); rx = array.array("B", bytes(len(tx))); txb = array.array("B", tx)
# struct spi_ioc_transfer (32 bajty): tx_buf, rx_buf, len, speed_hz, delay_usecs, bits_per_word, ...
tr = struct.pack("QQIIHBBBBBB", txb.buffer_info()[0], rx.buffer_info()[0], len(tx), 500000, 0, 8, 0, 0, 0, 0, 0)
SPI_IOC_MESSAGE_1 = 0x40206b00
fcntl.ioctl(fd, SPI_IOC_MESSAGE_1, tr)
print("ok" if rx.tobytes() == tx else "zle:%s" % rx.tobytes()[:8].hex())
PY
)
		if [[ "${w}" == ok ]]; then wynik PASS GPIO "SPI loopback (pins 19-21)" "${spi} 500 kHz, data matches"
		else wynik FAIL GPIO "SPI loopback (pins 19-21)" "${spi}: ${w}"; fi
	else
		wynik SKIP GPIO "SPI loopback (pins 19-21)" "no /dev/spidev0.x ('spi-spidev' overlay, --przygotuj) or no wire"
	fi
	# --- G: I2C2 na pinach 3 i 5: magistrala i urzadzenia
	i2c=$(po_adresie "/sys/class/i2c-dev/i2c-*" 1c2b400)
	if [[ -n "${i2c}" ]] && ma i2cdetect; then
		zapisz "i2cdetect ${i2c}" i2cdetect -y "${i2c#i2c-}"
		w=$(i2cdetect -y "${i2c#i2c-}" 2> /dev/null | awk 'NR>1 {for (i=2; i<=NF; i++) if ($i ~ /^[0-9a-f][0-9a-f]$|^UU$/) printf "%s ", $i}')
		wynik PASS GPIO "I2C bus (pins 3-5)" "/dev/${i2c}, devices: ${w:-none}"
	else
		wynik SKIP GPIO "I2C bus (pins 3-5)" "no I2C2 device or no i2c-tools (--przygotuj)"
	fi
}

m_obciazenie() {
	local czas=60 i t tmax=0 f fmin=999999 u umin=99999999 zas prad pid bledy_przed bledy_po
	# CO: napiecie wejscia z przetwornika AXP209 (kanal 0 = gniazdo zasilania, 1 = VBUS).
	# DLACZEGO nie /sys/class/power_supply: w drzewie Banana Pro jest tam tylko bateria.
	zas=$(for d in /sys/bus/iio/devices/iio:device*; do grep -q 'pmic@34/adc' "$d/uevent" 2> /dev/null && { echo "$d"; break; }; done)
	bledy_przed=$(dmesg -l err,crit,alert,emerg 2> /dev/null | wc -l)
	info "Obciazenie obu rdzeni przez ${czas} sekund..."
	local pidy=()
	for i in $(seq "$(nproc)"); do sha256sum /dev/zero > /dev/null 2>&1 & pidy+=($!); done
	for i in $(seq $((czas / 2))); do
		sleep 2
		t=$(($(cat /sys/class/thermal/thermal_zone0/temp 2> /dev/null || echo 0) / 1000)); [[ ${t} -gt ${tmax} ]] && tmax=${t}
		f=$(($(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2> /dev/null || echo 0) / 1000)); [[ ${f} -lt ${fmin} ]] && fmin=${f}
		# CO: postep co 10 s, zeby okno nie wygladalo na zawieszone.
		(( i % 5 == 0 )) && info "Obciazenie: $((i * 2)) s z ${czas}, ${t} C, ${f} MHz"
		if [[ -n "${zas}" ]]; then
			u=$(awk -v a="$(cat "${zas}/in_voltage0_raw")" -v b="$(cat "${zas}/in_voltage1_raw")" -v s="$(cat "${zas}/in_voltage0_scale")" 'BEGIN {printf "%d", (a > b ? a : b) * s}')
			[[ ${u} -gt 0 && ${u} -lt ${umin} ]] && umin=${u}
		fi
	done
	kill "${pidy[@]}" 2> /dev/null; wait 2> /dev/null
	bledy_po=$(dmesg -l err,crit,alert,emerg 2> /dev/null | wc -l)
	if [[ ${tmax} -lt 80 ]]; then wynik PASS Load "temperature" "max ${tmax} C after ${czas} s on $(nproc) cores"
	else wynik WARN Load "temperature" "max ${tmax} C after ${czas} s (heatsink?)"; fi
	wynik PASS Load "CPU frequency" "lowest ${fmin} MHz under load"
	if [[ -n "${zas}" && ${umin} -lt 99999999 ]]; then
		if [[ ${umin} -ge 4750 ]]; then wynik PASS Load "supply voltage" "lowest ${umin} mV under load (AXP209 ADC)"
		else wynik WARN Load "supply voltage" "lowest ${umin} mV under load (AXP209 ADC): weak power supply or cable"; fi
	else
		wynik SKIP Load "supply voltage" "no AXP209 ADC"
	fi
	if [[ ${bledy_po} -gt ${bledy_przed} ]]; then wynik WARN Load "kernel errors" "$((bledy_po - bledy_przed)) new lines during the load"
	else wynik PASS Load "kernel errors" "none during the load"; fi
}

m_pakiety() {
	local jadro audyt wstrz
	zapisz "kernel packages" dpkg-query -W -f '${Package} ${Version}\n' 'linux-image-*' 'linux-dtb-*' 'linux-u-boot-*' 'armbian-*'
	# DLACZEGO db:Status-Abbrev: wzorzec pasuje tez do pakietow niezainstalowanych (bez wersji).
	jadro=$(dpkg-query -W -f '${db:Status-Abbrev}|${Package} ${Version}\n' 'linux-image-*' 2> /dev/null | awk -F'|' '$1 ~ /^ii/ {print $2}' | head -1)
	wynik PASS Packages "kernel package" "${jadro:-?}"
	audyt=$(dpkg --audit 2>&1)
	if [[ -z "${audyt}" ]] && apt-get check > /dev/null 2>&1; then wynik PASS Packages "dpkg/apt state" "consistent"
	else wynik FAIL Packages "dpkg/apt state" "dpkg --audit or apt-get check reports problems"; zapisz "dpkg --audit" echo "${audyt}"; fi
	wstrz=$(apt-mark showhold 2> /dev/null | tr '\n' ' ')
	[[ -n "${wstrz// /}" ]] && wynik WARN Packages "held packages" "${wstrz}"
}

# ======================================================================
# Raport
# ======================================================================
raport() {
	local tytul="$1" plik_wynikow="${2:-}" w st ob te op z p f u s
	local lista=("${WYNIKI[@]}")
	[[ -n "${plik_wynikow}" && -r "${plik_wynikow}" ]] && mapfile -t lista < "${plik_wynikow}"
	LICZ() { printf '%s\n' "${lista[@]}" | grep -c "^$1|"; }
	p=$(LICZ PASS); f=$(LICZ FAIL); u=$(LICZ WARN); s=$(LICZ SKIP)
	{
		echo "## ${tytul}"
		echo
		echo "- Date: $(date -u '+%Y-%m-%d %H:%M UTC')"
		echo "- Image: Armbian ${OBRAZ}"
		echo "- Kernel: ${JADRO}"
		echo "- Board: ${MODEL}"
		echo "- Overlays: ${OVERLAYS:-none}"
		[[ ${MINIMALNY} -eq 1 ]] && echo "- Mode: minimal, automatic checks only (release checklist; LCD panels and GPIO tested separately)"
		[[ -n "${LINK_LOGU:-}" ]] && echo "- armbianmonitor: ${LINK_LOGU}"
		echo "- Result: ${p} pass, ${f} fail, ${u} warning, ${s} skipped"
		echo
		echo "| Result | Area | Test | Details |"
		echo "|---|---|---|---|"
		for w in "${lista[@]}"; do
			IFS='|' read -r st ob te op <<< "${w}"
			case "${st}" in PASS) z="✅ pass" ;; FAIL) z="❌ fail" ;; WARN) z="⚠️ warning" ;; *) z="➖ skipped" ;; esac
			echo "| ${z} | ${ob} | ${te} | ${op} |"
		done
		echo
		echo "Generated by test-bananapipro.sh ${WERSJA_TESTU} (https://github.com/cyryllo/banana-a20/tree/master/testy)"
	} > "${RAPORT}"
	chown "${UZYTKOWNIK}:" "${RAPORT}" "${SZCZEGOLY}" 2> /dev/null
	if [[ ${MASZ} -eq 1 ]]; then
		echo "KONIEC|${RAPORT}|${SZCZEGOLY}|${p}|${f}|${u}|${s}"
	else
		echo
		echo "Wynik: ${p} OK, ${f} bledow, ${u} uwag, ${s} pominietych."
		echo "Raport (po angielsku, do forum albo zgloszenia): ${RAPORT}"
		echo "Szczegoly (dmesg, urzadzenia):                   ${SZCZEGOLY}"
	fi
	[[ ${f} -eq 0 ]]
}

# CO: podstawowe dane o obrazie do raportu (bez wynikow).
dane_obrazu() {
	. /etc/armbian-release 2> /dev/null || true
	. /etc/os-release 2> /dev/null || true
	MODEL=$(dt /proc/device-tree/model)
	JADRO=$(uname -r)
	OBRAZ="${IMAGE_TYPE:-?} ${VERSION:-?} ${BRANCH:-?}, ${PRETTY_NAME:-?}"
	OVERLAYS=$(grep -E '^(overlays|user_overlays|extraargs)=' "${ENV}" 2> /dev/null | tr '\n' ' ')
}

uruchom_ponownie() {
	if zapytaj "$1"; then
		info "Uruchamiam ponownie..."
		sync; systemctl reboot
		exit 0
	fi
	info "Uruchom ponownie pozniej: sudo reboot, potem znow: sudo $0 --ekrany"
	exit 0
}

# ======================================================================
# Tryb --przygotuj: narzedzia i nakladki do testow GPIO
# ======================================================================
if [[ "${TRYB}" == "przygotuj" ]]; then
	: > /dev/null
	info "Instaluje narzedzia: gpiod, i2c-tools, alsa-utils, iw..."
	if apt-get update > /dev/null 2>&1 && DEBIAN_FRONTEND=noninteractive apt-get install -y gpiod i2c-tools alsa-utils iw > /dev/null 2>&1; then
		info "Narzedzia zainstalowane."
	else
		info "BLAD: apt-get install nie powiodl sie (siec?)."
	fi
	[[ -e "${ENV}.przed-testem" ]] || cp -p "${ENV}" "${ENV}.przed-testem"
	ZMIANA=$(python3 - "${ENV}" << 'PY'
import os, sys
plik = sys.argv[1]
linie = open(plik).read().splitlines()
stare = list(linie)
def slowa(k):
    for l in linie:
        if l.startswith(k + "="):
            return l.split("=", 1)[1].split()
    return []
ov = slowa("overlays")
for n in ("pwm", "spi-spidev"):
    if n not in ov:
        ov.append(n)
nowe = [l for l in linie if not l.startswith("overlays=")] + ["overlays=" + " ".join(ov)]
if not any(l.startswith("param_spidev_spi_bus=") for l in nowe):
    nowe.append("param_spidev_spi_bus=0")
if sorted(nowe) != sorted(stare):
    open(plik + ".tmp", "w").write("\n".join(nowe) + "\n")
    os.replace(plik + ".tmp", plik)
    print("tak")
PY
)
	if [[ "${ZMIANA}" == tak ]]; then
		info "Dopisane do ${ENV}: nakladki pwm i spi-spidev, param_spidev_spi_bus=0 (kopia: ${ENV}.przed-testem)."
		uruchom_ponownie "Nakladki dzialaja po restarcie. Uruchomic ponownie teraz?"
	fi
	info "Nakladki pwm i spi-spidev byly juz wlaczone. Mozna testowac: sudo $0"
	exit 0
fi

# ======================================================================
# Tryb --ekrany: ekrany LeMaker po kolei, z restartami
# DLACZEGO stan w /var/lib: skrypt konczy sie przed kazdym restartem, a po nim
# tester uruchamia go znowu; kolejne etapy i wyniki sa zapisane miedzy restartami.
# ======================================================================
if [[ "${TRYB}" == "ekrany" ]]; then
	dane_obrazu
	PLIK_WYNIKOW="${STAN_EKRANOW}/wyniki"
	SZCZEGOLY="${STAN_EKRANOW}/szczegoly.txt"
	PYTANIA=1
	if [[ ! -f "${STAN_EKRANOW}/etapy" ]]; then
		info "Test ekranow LeMaker: skrypt ustawia kolejno kazdy ekran, a Ty po kazdym restarcie uruchamiasz go znowu (sudo $0 --ekrany)."
		info "Na koniec przywraca obecne ustawienia z kopii."
		ETAPY=""
		zapytaj "Masz ekran 7\" LeMaker?" && ETAPY+="7 7-hdmi "
		zapytaj "Masz ekran 5\" LeMaker?" && ETAPY+="5 "
		ETAPY+="off"
		mkdir -p "${STAN_EKRANOW}"
		cp -p "${ENV}" "${STAN_EKRANOW}/armbianEnv.txt.oryginal"
		: > "${PLIK_WYNIKOW}"
		echo "${ETAPY}" > "${STAN_EKRANOW}/etapy"
		PIERWSZY=${ETAPY%% *}
		ustaw_ekran "${PIERWSZY}"
		echo "${PIERWSZY}" > "${STAN_EKRANOW}/panel"
		if [[ "${PIERWSZY}" == off ]]; then
			uruchom_ponownie "Ustawiony: $(opis_ekranu off). Uruchomic ponownie teraz?"
		else
			czekaj "WYLACZ plytke (sudo poweroff), podlacz ekran ${PIERWSZY%%-*}\" i wlacz ja; potem uruchom: sudo $0 --ekrany. Potwierdz, zeby wylaczyc"
			sync; systemctl poweroff; exit 0
		fi
	fi
	read -r -a ETAPY < "${STAN_EKRANOW}/etapy"
	ETAP=${ETAPY[0]}
	DZIALA=$(ekran_dzialajacy)
	info "Etap: $(opis_ekranu "${ETAP}") (dziala teraz: $(opis_ekranu "${DZIALA}"))"
	naglowek lcd
	if [[ "${DZIALA}" != "${ETAP}" ]]; then
		wynik FAIL "LCD ${ETAP}" "overlay active" "expected ${ETAP}, the device tree shows ${DZIALA}"
	else
		wynik PASS "LCD ${ETAP}" "overlay active" "$(opis_ekranu "${ETAP}"), ${OVERLAYS}"
	fi
	if [[ "${ETAP}" != off ]]; then
		m_lcd
		# DLACZEGO nazwy z etapem: w raporcie ekranow kazdy wiersz mowi, ktorego ekranu dotyczy.
		sed -i "s/^\([A-Z]*\)|LCD|/\1|LCD ${ETAP}|/" "${PLIK_WYNIKOW}"
	fi
	if [[ "${ETAP}" == 7-hdmi || "${ETAP}" == 5 || "${ETAP}" == off ]]; then
		m_obraz
		sed -i "s/^\([A-Z]*\)|Display|/\1|LCD ${ETAP}|HDMI: /" "${PLIK_WYNIKOW}"
		[[ "${ETAP}" != off ]] && pytanie "LCD ${ETAP}" "LCD and HDMI together" "Czy LCD i HDMI pokazuja obraz jednoczesnie, a LCD nie miga?"
	fi
	# CO: nastepny etap albo koniec.
	ETAPY=("${ETAPY[@]:1}")
	if [[ ${#ETAPY[@]} -eq 0 ]]; then
		cp -p "${STAN_EKRANOW}/armbianEnv.txt.oryginal" "${ENV}"
		WYNIKI=()
		mv "${SZCZEGOLY}" "${PRZEDROSTEK}-${CZAS}-szczegoly.txt" 2> /dev/null || : > "${PRZEDROSTEK}-${CZAS}-szczegoly.txt"
		SZCZEGOLY="${PRZEDROSTEK}-${CZAS}-szczegoly.txt"
		raport "Banana Pi Pro LeMaker panels test report" "${PLIK_WYNIKOW}"
		rm -rf "${STAN_EKRANOW}"
		info "Test ekranow zakonczony, ustawienia ekranu przywrocone z kopii."
		uruchom_ponownie "Uruchomic ponownie z przywroconymi ustawieniami?"
	fi
	echo "${ETAPY[*]}" > "${STAN_EKRANOW}/etapy"
	NAST=${ETAPY[0]}
	ustaw_ekran "${NAST}"
	PANEL=$(cat "${STAN_EKRANOW}/panel")
	if [[ "${NAST}" != off && "${NAST%%-*}" != "${PANEL%%-*}" ]]; then
		echo "${NAST}" > "${STAN_EKRANOW}/panel"
		czekaj "Nastepny: $(opis_ekranu "${NAST}"). WYLACZE plytke: podlacz ekran ${NAST%%-*}\", wlacz ja i uruchom: sudo $0 --ekrany. Potwierdz"
		sync; systemctl poweroff; exit 0
	fi
	[[ "${NAST}" == 7-hdmi || "${NAST}" == 5 ]] && info "Podlacz monitor HDMI przed restartem."
	uruchom_ponownie "Nastepny: $(opis_ekranu "${NAST}"). Uruchomic ponownie teraz?"
fi

# ======================================================================
# Zwykly test
# ======================================================================
: > "${SZCZEGOLY}"
info "Test obrazu Armbian na Banana Pi Pro (skrypt ${WERSJA_TESTU})"
info "Raport: ${RAPORT}"
[[ -d "${STAN_EKRANOW}" ]] && info "UWAGA: trwa test ekranow (--ekrany); ten test go nie przerywa."

if [[ ${AKTUALIZACJA} -eq 1 ]]; then
	info "apt update && apt full-upgrade..."
	if apt-get update >> "${SZCZEGOLY}" 2>&1 \
		&& DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade >> "${SZCZEGOLY}" 2>&1; then
		wynik PASS Update "apt full-upgrade" "finished without errors, reboot and run the test again"
	else
		wynik FAIL Update "apt full-upgrade" "errors, see the details file"
	fi
fi

dane_obrazu
HDMI_POL=0
for m in "${MODULY[@]}"; do
	chce "${m}" || continue
	naglowek "${m}"
	"m_${m}"
done

LINK_LOGU=""
if [[ ${PYTANIA} -eq 1 && -z "${WYBRANE}" ]] && ma armbianmonitor; then
	info "armbianmonitor -u wysyla dziennik systemu na paste.armbian.com (publiczny link)."
	if zapytaj "Wyslac dziennik i dodac link do raportu?"; then
		LINK_LOGU=$(armbianmonitor -u 2>&1 | grep -oE 'https?://[^ ]+' | tail -1)
	fi
fi

raport "Banana Pi Pro test report"
