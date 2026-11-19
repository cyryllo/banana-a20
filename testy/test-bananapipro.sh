#!/bin/bash
# Test obrazu Armbian na Banana Pi Pro (LeMaker Banana Pro, Allwinner A20) przed
# wydaniem: lista kontrolna opiekuna plytki. Wiekszosc sprawdzen jest
# automatyczna, o reszte (obraz na ekranie, dzwiek, dotyk palcem) skrypt pyta.
# Na koncu zapisuje raport po angielsku (do forum Armbiana albo zgloszenia na
# GitHubie) i plik ze szczegolami (dmesg, listy urzadzen).
#
# Uzycie (na plytce):
#   sudo ./test-bananapipro.sh                  pelny test z pytaniami
#   sudo ./test-bananapipro.sh --bez-pytan      tylko sprawdzenia automatyczne
#   sudo ./test-bananapipro.sh --aktualizacja   najpierw apt full-upgrade, potem test
#
# DLACZEGO nic nie zapisuje na dyskach SATA i USB: na nich moga byc dane
# uzytkownika; testy szybkosci tylko czytaja. Zapis jest tylko na karcie SD
# (plik tymczasowy, usuwany od razu).

set -u
export LC_ALL=C

WERSJA_TESTU="1.0"
PYTANIA=1
AKTUALIZACJA=0
for a in "$@"; do
	case "${a}" in
		--bez-pytan) PYTANIA=0 ;;
		--aktualizacja) AKTUALIZACJA=1 ;;
		-h | --pomoc) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "Nieznana opcja: ${a} (--pomoc)" >&2; exit 1 ;;
	esac
done

if [[ ${EUID} -ne 0 ]]; then
	exec sudo "$0" "$@"
fi

# CO: raport i szczegoly w katalogu domowym uzytkownika, ktory uruchomil sudo.
DOM=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)
CZAS=$(date +%Y%m%d-%H%M)
RAPORT="${DOM}/raport-bananapipro-${CZAS}.md"
SZCZEGOLY="${DOM}/raport-bananapipro-${CZAS}-szczegoly.txt"
: > "${SZCZEGOLY}"

WYNIKI=()   # "STATUS|obszar|test|szczegoly"
if [[ -t 1 ]]; then
	K_OK=$'\e[32m'; K_BLAD=$'\e[31m'; K_UWAGA=$'\e[33m'; K_POMIN=$'\e[90m'; K_0=$'\e[0m'
else
	K_OK=""; K_BLAD=""; K_UWAGA=""; K_POMIN=""; K_0=""
fi

# CO: zapisuje wynik jednego testu. STATUS: PASS, FAIL, WARN, SKIP.
wynik() {
	local status="$1" obszar="$2" test="$3" opis="${4:-}"
	WYNIKI+=("${status}|${obszar}|${test}|${opis}")
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
		read -r -p ">>> $1 [t]ak / [n]ie / [p]omin: " odp < /dev/tty || return 2
		case "${odp,,}" in t | tak | y | yes) return 0 ;; n | nie | no) return 1 ;; p | pomin | s | skip) return 2 ;; esac
	done
}

# CO: pytanie, ktorego wynik od razu trafia do raportu.
pytanie() {
	local obszar="$1" test="$2" tresc="$3"
	if [[ ${PYTANIA} -eq 0 ]]; then
		wynik SKIP "${obszar}" "${test}" "not asked (--bez-pytan)"
		return
	fi
	zapytaj "${tresc}"
	case $? in
		0) wynik PASS "${obszar}" "${test}" "confirmed by the tester" ;;
		1) wynik FAIL "${obszar}" "${test}" "reported as not working by the tester" ;;
		*) wynik SKIP "${obszar}" "${test}" "skipped by the tester" ;;
	esac
}

ma() { command -v "$1" > /dev/null 2>&1; }

# CO: tekst z drzewa urzadzen (/proc/device-tree) bez bajtow zerowych.
# DLACZEGO funkcja: przy braku pliku "tr < plik 2>/dev/null" i tak wypisuje blad,
# bo przekierowanie wejscia jest wykonywane przed przekierowaniem bledow.
dt() { [[ -r "$1" ]] && tr -d '\0' < "$1"; }

# CO: szybkosc odczytu urzadzenia blokowego (MB/s), tylko odczyt.
odczyt_mbs() {
	dd if="$1" of=/dev/null bs=1M count="${2:-200}" iflag=direct 2>&1 | awk '/copied/ {print $(NF-1), $NF}'
}

echo "Test obrazu Armbian na Banana Pi Pro (skrypt ${WERSJA_TESTU})"
echo "Raport: ${RAPORT}"
echo

# ------------------------------------------------------------ aktualizacja
if [[ ${AKTUALIZACJA} -eq 1 ]]; then
	echo "== apt update && apt full-upgrade"
	if apt-get update >> "${SZCZEGOLY}" 2>&1 \
		&& DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade >> "${SZCZEGOLY}" 2>&1; then
		wynik PASS Update "apt full-upgrade" "finished without errors, reboot and run the test again"
	else
		wynik FAIL Update "apt full-upgrade" "errors, see the details file"
	fi
fi

# ------------------------------------------------------------ system
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
OVERLAYS=$(grep -E '^(overlays|user_overlays)=' /boot/armbianEnv.txt 2> /dev/null | tr '\n' ' ')
wynik PASS System "overlays" "${OVERLAYS:-none}"

STAN=$(systemctl is-system-running 2> /dev/null)
NIEUDANE=$(systemctl --failed --no-legend --plain 2> /dev/null | awk '{print $1}' | tr '\n' ' ')
zapisz "systemctl --failed" systemctl --failed
if [[ -z "${NIEUDANE// /}" ]]; then
	wynik PASS System "services" "${STAN}, no failed units"
else
	wynik FAIL System "services" "failed units: ${NIEUDANE}"
fi
ma systemd-analyze && wynik PASS System "boot time" "$(systemd-analyze 2> /dev/null | head -1 | sed 's/Startup finished in //')"

zapisz "dmesg (err and worse)" dmesg -l err,crit,alert,emerg
zapisz "dmesg (full)" dmesg
BLEDY_JADRA=$(dmesg -l err,crit,alert,emerg 2> /dev/null | wc -l)
if [[ ${BLEDY_JADRA} -eq 0 ]]; then
	wynik PASS System "kernel errors" "none in dmesg"
else
	wynik WARN System "kernel errors" "${BLEDY_JADRA} lines in dmesg (err and worse), see details"
fi

PAMIEC=$(awk '/MemTotal/ {printf "%d MB", $2/1024}' /proc/meminfo)
wynik PASS System "memory" "${PAMIEC}"
if [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
	T=$(($(cat /sys/class/thermal/thermal_zone0/temp) / 1000))
	if [[ ${T} -lt 75 ]]; then wynik PASS System "temperature" "${T} C"; else wynik WARN System "temperature" "${T} C"; fi
else
	wynik SKIP System "temperature" "no thermal zone"
fi
if [[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq ]]; then
	F=/sys/devices/system/cpu/cpu0/cpufreq
	wynik PASS System "cpufreq" "$(cat ${F}/scaling_governor), $(($(cat ${F}/scaling_min_freq) / 1000))-$(($(cat ${F}/scaling_max_freq) / 1000)) MHz, $(nproc) cores"
else
	wynik WARN System "cpufreq" "no cpufreq"
fi

# ------------------------------------------------------------ karta SD
ROOT_DEV=$(findmnt -no SOURCE /)
wynik PASS Storage "root filesystem" "${ROOT_DEV}, $(df -h / | awk 'NR==2 {print $4 " free of " $2}')"
PLIK_TEST=/var/tmp/test-bananapipro.$$
ZAPIS=$(dd if=/dev/zero of="${PLIK_TEST}" bs=1M count=64 conv=fsync 2>&1 | awk '/copied/ {print $(NF-1), $NF}')
sync; echo 3 > /proc/sys/vm/drop_caches
CZYT=$(dd if="${PLIK_TEST}" of=/dev/null bs=1M 2>&1 | awk '/copied/ {print $(NF-1), $NF}')
rm -f "${PLIK_TEST}"
if [[ -n "${ZAPIS}" && -n "${CZYT}" ]]; then
	wynik PASS Storage "SD card speed" "write ${ZAPIS}, read ${CZYT} (64 MB file)"
else
	wynik FAIL Storage "SD card speed" "write or read test failed"
fi
MMC_BLEDY=$(dmesg | grep -ciE 'mmc[0-9].*(error|timeout|fail)')
if [[ ${MMC_BLEDY} -eq 0 ]]; then wynik PASS Storage "SD card errors" "none in dmesg"; else wynik WARN Storage "SD card errors" "${MMC_BLEDY} mmc error lines in dmesg"; fi

# ------------------------------------------------------------ SATA
zapisz "lsblk" lsblk -o NAME,TRAN,SIZE,MODEL,MOUNTPOINT
SATA=$(lsblk -dno NAME,TRAN | awk '$2=="sata" {print $1}' | head -1)
if [[ -n "${SATA}" ]]; then
	MODEL_DYSKU=$(lsblk -dno MODEL "/dev/${SATA}" | xargs)
	wynik PASS SATA "disk detected" "/dev/${SATA} ${MODEL_DYSKU} $(lsblk -dno SIZE "/dev/${SATA}")"
	S=$(odczyt_mbs "/dev/${SATA}" 300)
	if [[ -n "${S}" ]]; then wynik PASS SATA "read speed" "${S} (300 MB, read only)"; else wynik FAIL SATA "read speed" "read failed"; fi
else
	if dmesg | grep -qi 'ahci'; then
		wynik SKIP SATA "disk detected" "AHCI driver loaded, no disk connected"
	else
		wynik WARN SATA "disk detected" "no AHCI messages in dmesg"
	fi
fi

# ------------------------------------------------------------ USB
if ma lsusb; then zapisz "lsusb" lsusb; fi
USB_URZ=$(find /sys/bus/usb/devices -maxdepth 1 -name '[0-9]*-[0-9]*' ! -name '*:*' | wc -l)
USB_NAZWY=$(for d in /sys/bus/usb/devices/[0-9]*-[0-9]*; do [[ "$d" == *:* ]] && continue; [[ -r "$d/product" ]] && cat "$d/product"; done 2> /dev/null | tr '\n' ',' | sed 's/,$//; s/,/, /g')
if [[ ${USB_URZ} -gt 0 ]]; then
	wynik PASS USB "devices" "${USB_URZ}: ${USB_NAZWY}"
else
	wynik WARN USB "devices" "no USB device connected, connect a USB stick or keyboard to test the ports"
fi
USB_DYSK=$(lsblk -dno NAME,TRAN | awk '$2=="usb" {print $1}' | head -1)
if [[ -n "${USB_DYSK}" ]]; then
	S=$(odczyt_mbs "/dev/${USB_DYSK}" 100)
	if [[ -n "${S}" ]]; then wynik PASS USB "storage read speed" "/dev/${USB_DYSK}: ${S} (100 MB, read only)"; else wynik FAIL USB "storage read speed" "read failed"; fi
else
	wynik SKIP USB "storage read speed" "no USB storage connected"
fi

# ------------------------------------------------------------ Ethernet
ETH=$(ls /sys/class/net | grep -E '^(end|eth)' | head -1)
if [[ -n "${ETH}" ]]; then
	if [[ "$(cat /sys/class/net/${ETH}/carrier 2> /dev/null)" == "1" ]]; then
		PR=$(cat /sys/class/net/${ETH}/speed 2> /dev/null)
		IP4=$(ip -4 -br addr show "${ETH}" | awk '{print $3}')
		if [[ "${PR}" == "1000" ]]; then wynik PASS Ethernet "link" "${ETH} ${PR} Mb/s ${IP4}"
		else wynik WARN Ethernet "link" "${ETH} ${PR} Mb/s ${IP4} (expected 1000, check the cable or switch)"; fi
	else
		wynik SKIP Ethernet "link" "${ETH} present, no cable connected"
	fi
else
	wynik FAIL Ethernet "interface" "no Ethernet interface"
fi

# ------------------------------------------------------------ Wi-Fi
WLAN=$(ls /sys/class/net | grep -E '^wl' | head -1)
if [[ -n "${WLAN}" ]]; then
	STER=$(basename "$(readlink -f /sys/class/net/${WLAN}/device/driver)" 2> /dev/null)
	wynik PASS Wi-Fi "interface" "${WLAN}, driver ${STER:-?}"
	ip link set "${WLAN}" up 2> /dev/null
	SIECI=""
	if ma nmcli; then
		SIECI=$(nmcli -t -f SSID dev wifi list --rescan yes 2> /dev/null | grep -c .)
	elif ma iw; then
		SIECI=$(iw dev "${WLAN}" scan 2> /dev/null | grep -c 'SSID:')
	fi
	if [[ -z "${SIECI}" ]]; then wynik SKIP Wi-Fi "scan" "no nmcli or iw"
	elif [[ "${SIECI}" -gt 0 ]]; then wynik PASS Wi-Fi "scan" "${SIECI} networks found"
	else wynik FAIL Wi-Fi "scan" "no networks found"; fi
else
	wynik FAIL Wi-Fi "interface" "no wireless interface"
fi
zapisz "dmesg brcmfmac" sh -c "dmesg | grep -i brcmf"

# ------------------------------------------------------------ Internet
BRAMA=$(ip route | awk '/^default/ {print $3; exit}')
if [[ -n "${BRAMA}" ]] && ping -c 3 -W 2 "${BRAMA}" > /dev/null 2>&1; then
	wynik PASS Network "gateway" "${BRAMA} answers"
else
	wynik FAIL Network "gateway" "no default route or no answer"
fi
if getent hosts apt.armbian.com > /dev/null 2>&1; then wynik PASS Network "DNS" "apt.armbian.com resolves"; else wynik FAIL Network "DNS" "apt.armbian.com does not resolve"; fi

# ------------------------------------------------------------ obraz: HDMI i LCD
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

# ------------------------------------------------------------ ekrany LeMaker
LCD=$(echo "${OVERLAYS}" | grep -oE 'lemaker-lcd[0-9a-z-]*' | head -1)
if [[ -n "${LCD}" ]]; then
	PANEL=$(dt /proc/device-tree/lemaker-lcd-panel/compatible)
	if [[ -n "${PANEL}" ]]; then wynik PASS LCD "overlay ${LCD}" "panel node: ${PANEL}"
	else wynik FAIL LCD "overlay ${LCD}" "no lemaker-lcd-panel node in the device tree"; fi
	BL=$(ls -d /sys/class/backlight/* 2> /dev/null | head -1)
	if [[ -n "${BL}" ]]; then wynik PASS LCD "backlight" "$(basename "${BL}") $(cat "${BL}/brightness")/$(cat "${BL}/max_brightness")"
	else wynik FAIL LCD "backlight" "no backlight device"; fi
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
	BLEDY_DOTYKU=$(dmesg | grep -c 'edt_ft5x06.*Unable to fetch data')
	[[ ${BLEDY_DOTYKU} -gt 0 ]] && wynik WARN LCD "touch errors" "${BLEDY_DOTYKU} 'Unable to fetch data' in dmesg"
else
	wynik SKIP LCD "LeMaker panel" "no lemaker-lcd overlay enabled"
fi

# ------------------------------------------------------------ dzwiek
zapisz "asound cards" cat /proc/asound/cards
KARTY=$(awk -F'[][]' '/^ *[0-9]+ \[/ {gsub(/ +$/,"",$2); print $2}' /proc/asound/cards 2> /dev/null | paste -sd, | sed 's/,/, /g')
if [[ -n "${KARTY}" ]]; then wynik PASS Audio "sound cards" "${KARTY}"; else wynik FAIL Audio "sound cards" "no ALSA cards"; fi

# ------------------------------------------------------------ pakiety
zapisz "kernel packages" dpkg-query -W -f '${Package} ${Version}\n' 'linux-image-*' 'linux-dtb-*' 'linux-u-boot-*' 'armbian-*'
JADRO_PAK=$(dpkg-query -W -f '${Package} ${Version}\n' 'linux-image-*' 2> /dev/null | grep -v '^$' | head -1)
wynik PASS Packages "kernel package" "${JADRO_PAK:-?}"
AUDYT=$(dpkg --audit 2>&1)
if [[ -z "${AUDYT}" ]] && apt-get check > /dev/null 2>&1; then wynik PASS Packages "dpkg/apt state" "consistent"
else wynik FAIL Packages "dpkg/apt state" "dpkg --audit or apt-get check reports problems"; zapisz "dpkg --audit" echo "${AUDYT}"; fi
WSTRZYMANE=$(apt-mark showhold 2> /dev/null | tr '\n' ' ')
[[ -n "${WSTRZYMANE// /}" ]] && wynik WARN Packages "held packages" "${WSTRZYMANE}"

# ------------------------------------------------------------ pytania
if [[ ${PYTANIA} -eq 1 ]]; then
	echo
	echo "== Teraz kilka pytan (t = dziala, n = nie dziala, p = pomin)."
fi
if [[ ${HDMI_POL} -eq 1 ]]; then
	pytanie Display "HDMI picture" "Czy obraz na monitorze HDMI jest poprawny (bez migania, ostry)?"
fi
if [[ -n "${LCD}" ]]; then
	pytanie LCD "LCD picture" "Czy obraz na ekranie LeMaker jest poprawny (kolory, bez szumu i migania)?"
	# CO: liczy stukniecia prosto z urzadzenia wejscia (bez evtest).
	ZDARZ=$(awk '/^N: Name=.*ft5x06/ {f=1} f && /^H: Handlers=/ {match($0, /event[0-9]+/); print substr($0, RSTART, RLENGTH); exit}' /proc/bus/input/devices)
	if [[ ${PYTANIA} -eq 1 && -n "${ZDARZ}" ]] && ma python3; then
		echo ">>> Test dotyku: w ciagu 15 sekund stuknij w ekran LCD dokladnie 5 razy, spokojnie."
		read -r -p ">>> Enter, gdy gotowe do startu... " _ < /dev/tty
		STUK=$(python3 - "/dev/input/${ZDARZ}" << 'PY'
import os, select, struct, sys, time
fmt = "llHHi"
size = struct.calcsize(fmt)
fd = os.open(sys.argv[1], os.O_RDONLY)
koniec = time.time() + 15
dotkniecia = 0
while time.time() < koniec:
    r, _, _ = select.select([fd], [], [], max(0, koniec - time.time()))
    if not r:
        break
    dane = os.read(fd, size * 64)
    for i in range(0, len(dane) - size + 1, size):
        _, _, typ, kod, wartosc = struct.unpack(fmt, dane[i:i + size])
        if typ == 1 and kod == 330 and wartosc == 1:   # EV_KEY, BTN_TOUCH, wcisniety
            dotkniecia += 1
print(dotkniecia)
PY
)
		if [[ "${STUK}" == "5" ]]; then wynik PASS LCD "touch taps" "5 taps, 5 touches reported"
		elif [[ "${STUK}" == "0" ]]; then wynik FAIL LCD "touch taps" "5 taps, no touch reported"
		else wynik WARN LCD "touch taps" "5 taps, ${STUK} touches reported (phantom or missed touches)"; fi
	elif [[ ${PYTANIA} -eq 1 ]]; then
		pytanie LCD "touch" "Czy dotyk reaguje poprawnie w calym obszarze ekranu?"
	fi
fi
if systemctl is-active --quiet display-manager 2> /dev/null; then
	pytanie Desktop "desktop usable" "Czy pulpit dziala plynnie (menu, okna, przegladarka plikow)?"
	[[ -n "${LCD}" ]] && pytanie LCD "wake by touch" "Czy dotyk budzi wygaszony ekran? (wygaszenie: xset dpms force off w terminalu pulpitu)"
fi
if [[ ${PYTANIA} -eq 1 ]]; then
	pytanie USB "keyboard and mouse" "Czy klawiatura i mysz USB dzialaja (jesli podlaczone)?"
	ANALOG=$(awk -F'[][]' '/^ *[0-9]+ \[/ && tolower($0) ~ /codec|audio/ && tolower($0) !~ /hdmi/ {gsub(/ +$/,"",$2); print $2; exit}' /proc/asound/cards)
	if [[ -n "${ANALOG}" ]] && ma speaker-test; then
		echo ">>> Za chwile 3 sekundy dzwieku testowego na wyjsciu jack (${ANALOG}). Podlacz sluchawki albo glosnik."
		read -r -p ">>> Enter, gdy gotowe... " _ < /dev/tty
		timeout 4 speaker-test -D "plughw:CARD=${ANALOG}" -c 2 -t sine -f 440 -l 1 > /dev/null 2>&1
		pytanie Audio "analog output" "Czy slychac bylo dzwiek w obu kanalach?"
	else
		wynik SKIP Audio "analog output" "no analog card or no speaker-test (alsa-utils)"
	fi
	[[ ${HDMI_POL} -eq 1 ]] && pytanie Audio "HDMI audio" "Czy dzwiek przez HDMI dziala (jesli monitor ma glosniki)?"
fi

# ------------------------------------------------------------ armbianmonitor
LINK_LOGU=""
if [[ ${PYTANIA} -eq 1 ]] && ma armbianmonitor; then
	echo ">>> armbianmonitor -u wysyla dziennik systemu na paste.armbian.com (publiczny link)."
	if zapytaj "Wyslac dziennik i dodac link do raportu?"; then
		LINK_LOGU=$(armbianmonitor -u 2>&1 | grep -oE 'https?://[^ ]+' | tail -1)
	fi
fi

# ------------------------------------------------------------ raport
LICZ() { printf '%s\n' "${WYNIKI[@]}" | grep -c "^$1|"; }
P=$(LICZ PASS); F=$(LICZ FAIL); W=$(LICZ WARN); S=$(LICZ SKIP)
{
	echo "## Banana Pi Pro test report"
	echo
	echo "- Date: $(date -u '+%Y-%m-%d %H:%M UTC')"
	echo "- Image: Armbian ${OBRAZ}"
	echo "- Kernel: ${JADRO}"
	echo "- Board: ${MODEL}"
	echo "- Overlays: ${OVERLAYS:-none}"
	[[ -n "${LINK_LOGU}" ]] && echo "- armbianmonitor: ${LINK_LOGU}"
	echo "- Result: ${P} pass, ${F} fail, ${W} warning, ${S} skipped"
	echo
	echo "| Result | Area | Test | Details |"
	echo "|---|---|---|---|"
	for w in "${WYNIKI[@]}"; do
		IFS='|' read -r st ob te op <<< "${w}"
		case "${st}" in PASS) z="✅ pass" ;; FAIL) z="❌ fail" ;; WARN) z="⚠️ warning" ;; *) z="➖ skipped" ;; esac
		echo "| ${z} | ${ob} | ${te} | ${op} |"
	done
	echo
	echo "Generated by test-bananapipro.sh ${WERSJA_TESTU} (https://github.com/cyryllo/banana-a20/tree/master/testy)"
} > "${RAPORT}"
chown "${SUDO_USER:-root}:" "${RAPORT}" "${SZCZEGOLY}" 2> /dev/null

echo
echo "Wynik: ${P} OK, ${F} bledow, ${W} uwag, ${S} pominietych."
echo "Raport (po angielsku, do forum albo zgloszenia): ${RAPORT}"
echo "Szczegoly (dmesg, urzadzenia):                   ${SZCZEGOLY}"
[[ ${F} -eq 0 ]]
