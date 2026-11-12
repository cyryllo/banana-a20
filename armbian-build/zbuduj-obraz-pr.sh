#!/bin/bash
# Buduje obraz Armbian dla Banana Pro z oficjalnego armbian/build (domyslnie
# galaz main). Obsluga ekranow LeMaker jest tam od 2026-11-10 (nasze PR-y,
# wszystkie scalone):
#   #11293 sunxi: enable the EDT FT5x06 touchscreen driver
#   #11294 sunxi: edt-ft5x06: retry identification after I2C bus recovery
#   #11296 sunxi: add overlays for the LeMaker 5" and 7" LCD panels (A20)
#
# Ekran wlacza sie jak w oficjalnym Armbian: linia overlays=lemaker-lcd7
# (lcd5, lcd7-hdmi) w /boot/armbianEnv.txt, bez skryptu lemaker-lcd i bez
# user_overlays (do tego jest starszy zbuduj-obraz.sh).
# Nazwa "-pr" zostala z czasow, gdy skrypt laczyl galezie PR z forka.
#
# Przyklady:
#   ./zbuduj-obraz-pr.sh                     # XFCE, LCD wylaczony
#   ./zbuduj-obraz-pr.sh --ekran 7           # XFCE, overlays=lemaker-lcd7
#   ./zbuduj-obraz-pr.sh --pulpit brak       # minimal bez pulpitu, LCD wylaczony
#   ./zbuduj-obraz-pr.sh --pulpit brak --ekran 7 --konsola   # konsola do gier (RetroArch)
#   ./zbuduj-obraz-pr.sh --armbian 4ebf24f5fe ...  # konkretny commit armbian/build
#   ./zbuduj-obraz-pr.sh --repo https://github.com/cyryllo/build-armbian.git \
#       --armbian sunxi-lemaker-lcd-touch-supply ...  # galaz z forka (zmiana przed scaleniem)

set -euo pipefail

EKRAN="brak"
PULPIT="xfce"
KONSOLA="no"
KLIPPER="no"
GRY=""
SKRYPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# CO: pliki konsoli Arkada20 (katalog arkada20/ w glownym katalogu repozytorium).
KONSOLA_DIR="$(dirname "${SKRYPT_DIR}")/arkada20"
# CO: pliki hosta drukarki Bosman20 (katalog bosman20/).
BOSMAN_DIR="$(dirname "${SKRYPT_DIR}")/bosman20"
BUILD_DIR="${HOME}/armbian-build"
ARMBIAN_REPO="https://github.com/armbian/build.git"
# DLACZEGO mozliwosc podania commita: main sie zmienia, a przypiety commit
# pozwala odtworzyc dokladnie ten sam obraz (np. dla wydania).
ARMBIAN_REF="main"

pomoc() {
	cat <<- EOF
		Uzycie: $0 [opcje] [-- dodatkowe opcje compile.sh]

		  -e, --ekran N       ekran wlaczony od pierwszego startu: brak (domyslnie), 7, 7-hdmi albo 5
		  -p, --pulpit NAZWA  xfce (domyslnie) albo brak (obraz minimal bez pulpitu)
		  -g, --konsola       konsola do gier: RetroArch na ekranie od startu, jak Lakka
		                      (tylko z --pulpit brak; najpierw ../arkada20/zbuduj-rdzenie.sh)
		      --klipper       Bosman20: Klipper, Moonraker, Mainsail, KlipperScreen przez KIAUH
		                      (tylko z --pulpit brak; najpierw ../bosman20/zbuduj-pakiety-python.sh)
		      --gry DIR       gry dolaczone do obrazu konsoli, DIR/<system>/plik (np. DIR/mame2003/gra.zip);
		                      obrazu z grami nie publikuj (prawa autorskie)
		  -a, --armbian REF   galaz, tag albo commit armbian/build (domyslnie main)
		  -r, --repo URL      inne repozytorium armbian/build, np. fork z galezia przed scaleniem
		                      (domyslnie ${ARMBIAN_REPO})
		  -k, --katalog DIR   katalog armbian/build (domyslnie ${BUILD_DIR})
		  -h, --pomoc         ta pomoc
	EOF
}

blad() {
	echo "BLAD: $*" >&2
	exit 1
}

EXTRA=()
while [[ $# -gt 0 ]]; do
	case "$1" in
		-e | --ekran) EKRAN="${2:-}"; shift 2 ;;
		-p | --pulpit) PULPIT="${2:-}"; shift 2 ;;
		-g | --konsola) KONSOLA="yes"; shift ;;
		--klipper) KLIPPER="yes"; shift ;;
		--gry) GRY="${2:-}"; shift 2 ;;
		-a | --armbian) ARMBIAN_REF="${2:-}"; shift 2 ;;
		-r | --repo) ARMBIAN_REPO="${2:-}"; shift 2 ;;
		-k | --katalog) BUILD_DIR="${2:-}"; shift 2 ;;
		-h | --pomoc) pomoc; exit 0 ;;
		--) shift; EXTRA=("$@"); break ;;
		*) pomoc; blad "nieznana opcja: $1" ;;
	esac
done

case "${EKRAN}" in
	brak | 7 | 7-hdmi | 5) ;;
	*) blad "nieznany ekran: ${EKRAN} (brak, 7, 7-hdmi albo 5)" ;;
esac
case "${PULPIT}" in
	xfce) PULPIT_OPCJE=(BUILD_DESKTOP=yes BUILD_MINIMAL=no DESKTOP_ENVIRONMENT=xfce DESKTOP_TIER=minimal) ;;
	brak) PULPIT_OPCJE=(BUILD_DESKTOP=no BUILD_MINIMAL=yes) ;;
	*) blad "pulpit musi byc xfce albo brak" ;;
esac

# DLACZEGO konsola tylko bez pulpitu: RetroArch dziala na ekranie bez X,
# a XFCE zajmowalby ten sam ekran i pamiec.
if [[ "${KONSOLA}" == "yes" ]]; then
	[[ "${PULPIT}" == "brak" ]] || blad "--konsola dziala tylko z --pulpit brak"
	compgen -G "${KONSOLA_DIR}/rdzenie/*_libretro.so" > /dev/null ||
		blad "brak rdzeni, uruchom najpierw: ${KONSOLA_DIR}/zbuduj-rdzenie.sh"
	[[ -x "${KONSOLA_DIR}/retroarch-bin/retroarch" ]] ||
		blad "brak RetroArch, uruchom najpierw: ${KONSOLA_DIR}/zbuduj-retroarch.sh"
fi
# DLACZEGO Bosman20 tylko bez pulpitu: KlipperScreen uruchamia wlasny serwer X na ekranie.
if [[ "${KLIPPER}" == "yes" ]]; then
	[[ "${PULPIT}" == "brak" ]] || blad "--klipper dziala tylko z --pulpit brak"
	[[ "${KONSOLA}" == "no" ]] || blad "--klipper i --konsola to dwa rozne systemy, wybierz jeden"
	compgen -G "${BOSMAN_DIR}/wheels/*.whl" > /dev/null ||
		blad "brak pakietow Pythona, uruchom najpierw: ${BOSMAN_DIR}/zbuduj-pakiety-python.sh"
	# DLACZEGO: Armbian domyslnie nie przenosi /home do obrazu, a KIAUH instaluje
	# wszystko w katalogu domowym uzytkownika (/home/bosman).
	EXTRA=(INCLUDE_HOME_DIR=yes "${EXTRA[@]}")
fi
if [[ -n "${GRY}" ]]; then
	[[ "${KONSOLA}" == "yes" ]] || blad "--gry dziala tylko z --konsola"
	[[ -d "${GRY}" ]] || blad "nie ma katalogu z grami: ${GRY}"
	GRY=$(realpath "${GRY}")
fi

command -v git > /dev/null || blad "brak git (sudo apt install git)"
command -v docker > /dev/null || blad "brak dockera (sudo apt install docker.io docker-buildx)"
[[ "${BUILD_DIR}" != *" "* ]] || blad "sciezka katalogu budowania nie moze zawierac spacji: ${BUILD_DIR}"

if [[ ! -d "${BUILD_DIR}/.git" ]]; then
	echo ">> Pobieram armbian/build do ${BUILD_DIR}"
	git clone --depth 50 https://github.com/armbian/build.git "${BUILD_DIR}"
fi
cd "${BUILD_DIR}"
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || blad "w ${BUILD_DIR} sa niezapisane zmiany w plikach git"

# CO: zapamietanie obecnego stanu katalogu i powrot do niego na koncu.
# DLACZEGO: ten sam katalog sluzy tez zbuduj-obraz.sh, ktory buduje
# ze starszego armbian/build.
POPRZEDNI=$(git rev-parse HEAD)
wroc() {
	cd "${BUILD_DIR}" && git checkout -q "${POPRZEDNI}" && echo ">> ${BUILD_DIR} z powrotem na ${POPRZEDNI:0:9}"
}
trap wroc EXIT

# CO: pobranie oficjalnego armbian/build (ARMBIAN_REF) do lokalnej galezi zbuduj-obraz-pr.
echo ">> Pobieram ${ARMBIAN_REPO} ${ARMBIAN_REF}"
git fetch -q "${ARMBIAN_REPO}" "${ARMBIAN_REF}" || blad "nie udalo sie pobrac ${ARMBIAN_REPO} ${ARMBIAN_REF}"
git checkout -q -B zbuduj-obraz-pr FETCH_HEAD
# CO: kontrola, czy ta wersja Armbiana ma juz obsluge ekranow LeMaker.
# DLACZEGO: ze starszego commita (sprzed 2026-11-10) wyszedlby obraz bez dotyku i nakladek.
grep -q '^CONFIG_TOUCHSCREEN_EDT_FT5X06=m' config/kernel/linux-sunxi-current.config &&
	compgen -G "patch/kernel/archive/sunxi-*/overlay_32/sun7i-a20-lemaker-lcd7.dtso" > /dev/null ||
	blad "armbian/build ${ARMBIAN_REF} nie ma jeszcze obslugi ekranow LeMaker (PR #11293, #11296)"
echo ">> Armbian: armbian/build $(git log -1 --format='%h z %cs' HEAD)"

# CO: osobny katalog userpatches tylko dla tego obrazu.
# DLACZEGO: w domyslnym userpatches/ leza pliki zbuduj-obraz.sh (customize-image.sh
# z lemaker-lcd, latka dotyku), ktore zdublowalyby to, co jest juz w PR-ach.
UP="${BUILD_DIR}/userpatches-lemaker-pr"
rm -rf "${UP}"
mkdir -p "${UP}"
# CO: customize-image.sh skladany z czesci: ekran i konsola.
echo '#!/bin/bash' > "${UP}/customize-image.sh"
chmod +x "${UP}/customize-image.sh"
if [[ "${EKRAN}" != "brak" ]]; then
	# CO: dopisuje overlays=lemaker-lcdN, a dla wariantow z HDMI tez tryb 1080p.
	# DLACZEGO 1080p: LCD i HDMI dziela zegar PLL3, zegar LCD pasuje tylko do 1080p/720p.
	HDMI=""
	[[ "${EKRAN}" == "5" || "${EKRAN}" == "7-hdmi" ]] && HDMI="video=HDMI-A-1:1920x1080@60"
	cat >> "${UP}/customize-image.sh" <<- EOF
		ENV_FILE=/boot/armbianEnv.txt
		if grep -q '^overlays=' "\${ENV_FILE}"; then
			sed -i 's/^overlays=.*/& lemaker-lcd${EKRAN}/' "\${ENV_FILE}"
		else
			echo "overlays=lemaker-lcd${EKRAN}" >> "\${ENV_FILE}"
		fi
		if [[ -n "${HDMI}" ]] && ! grep -q '^extraargs=' "\${ENV_FILE}"; then
			echo "extraargs=${HDMI}" >> "\${ENV_FILE}"
		fi
		echo "lemaker: \$(grep -E '^(overlays|extraargs)=' "\${ENV_FILE}" | tr '\n' ' ')"
	EOF
fi
if [[ "${KONSOLA}" == "yes" ]]; then
	# CO: pliki konsoli trafiaja do obrazu jako /tmp/overlay/konsola (katalog overlay/ z userpatches).
	mkdir -p "${UP}/overlay/konsola/rdzenie"
	cp -r "${KONSOLA_DIR}"/autoconfig "${KONSOLA_DIR}"/retroarch-bin "${UP}/overlay/konsola/"
	cp "${KONSOLA_DIR}"/{customize-konsola.sh,retroarch.cfg,retroarch-konsola.service,konsola-reset-dotyku,konsola-listy,konsola-listy.service,konsola-listy.path,avahi-samba.service} "${UP}/overlay/konsola/"
	cp "${KONSOLA_DIR}"/rdzenie/{*_libretro.so,WERSJE.txt} "${UP}/overlay/konsola/rdzenie/"
	if [[ -n "${GRY}" ]]; then
		mkdir -p "${UP}/overlay/konsola/gry"
		cp -r "${GRY}/." "${UP}/overlay/konsola/gry/"
		echo ">> Gry startowe: $(find "${GRY}" -type f | wc -l) plikow (obrazu z grami nie publikuj)"
	fi
	echo 'bash /tmp/overlay/konsola/customize-konsola.sh' >> "${UP}/customize-image.sh"
fi
if [[ "${KLIPPER}" == "yes" ]]; then
	# CO: pliki Bosman20 i gotowe pakiety Pythona trafiaja do obrazu jako /tmp/overlay/bosman20.
	mkdir -p "${UP}/overlay/bosman20"
	cp -r "${BOSMAN_DIR}"/{customize-bosman20.sh,instaluj-stos.sh,systemctl-budowanie,wheels} "${UP}/overlay/bosman20/"
	echo 'bash /tmp/overlay/bosman20/customize-bosman20.sh' >> "${UP}/customize-image.sh"
fi

echo ">> Buduje: pulpit=${PULPIT}, ekran=${EKRAN}, konsola=${KONSOLA}, klipper=${KLIPPER}, jadro current, Debian 13 trixie"
START=$(date +%s)
./compile.sh build USERPATCHES_PATH="${UP}" BOARD=bananapipro BRANCH=current RELEASE=trixie \
	KERNEL_CONFIGURE=no "${PULPIT_OPCJE[@]}" "${EXTRA[@]}"

# CO: obraz konsoli albo hosta drukarki dostaje nazwe projektu:
# Arkada20_<data>_bananapipro_trixie_<jadro>.img albo Bosman20_...
# DLACZEGO: to osobne systemy, a Armbian nazywa je tak samo jak zwykly obraz
# minimal (Armbian-unofficial_..._minimal.img) i nastepne budowanie by go nadpisalo.
PROJEKT=""
[[ "${KONSOLA}" == "yes" ]] && PROJEKT="Arkada20"
[[ "${KLIPPER}" == "yes" ]] && PROJEKT="Bosman20"
if [[ -n "${PROJEKT}" ]]; then
	img=$(ls -1t "${BUILD_DIR}"/output/images/*Bananapipro*trixie*_minimal.img 2> /dev/null | head -1)
	if [[ -n "${img}" && $(stat -c %Y "${img}") -ge ${START} ]]; then
		jadro=$(basename "${img}" | sed -E 's/.*_current_([0-9.]+)_minimal\.img/\1/')
		nowy="$(dirname "${img}")/${PROJEKT}_$(date +%F)_bananapipro_trixie_${jadro}.img"
		mv "${img}" "${nowy}"
		[[ -f "${img}.txt" ]] && mv "${img}.txt" "${nowy}.txt"
		# DLACZEGO nowa suma: plik .sha Armbiana zawiera stara nazwe pliku.
		(cd "$(dirname "${nowy}")" && sha256sum "$(basename "${nowy}")" > "$(basename "${nowy}").sha")
		rm -f "${img}.sha"
	fi
fi

echo
echo ">> Gotowe. Obrazy:"
ls -1t "${BUILD_DIR}"/output/images/*Bananapipro*trixie*.img 2> /dev/null | head -3 || true
