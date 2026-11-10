#!/bin/bash
# Buduje obraz Armbian dla Banana Pro z oficjalnego armbian/build plus nasze
# PR-y z obsluga ekranow LeMaker (jeszcze nie scalone):
#   #11293 sunxi: enable the EDT FT5x06 touchscreen driver
#   #11294 sunxi: edt-ft5x06: retry identification after I2C bus recovery
#   #11296 sunxi: add overlays for the LeMaker 5" and 7" LCD panels (A20)
#
# Wynik odpowiada oficjalnemu Armbian po scaleniu PR-ow: ekran wlacza sie
# linia overlays=lemaker-lcd7 (lcd5, lcd7-hdmi) w /boot/armbianEnv.txt,
# bez skryptu lemaker-lcd i bez user_overlays (do tego jest zbuduj-obraz.sh).
#
# Przyklady:
#   ./zbuduj-obraz-pr.sh                     # XFCE, LCD wylaczony
#   ./zbuduj-obraz-pr.sh --ekran 7           # XFCE, overlays=lemaker-lcd7
#   ./zbuduj-obraz-pr.sh --pulpit brak       # minimal bez pulpitu, LCD wylaczony
#   ./zbuduj-obraz-pr.sh --pulpit brak --ekran 7 --konsola   # konsola do gier (RetroArch)

set -euo pipefail

EKRAN="brak"
PULPIT="xfce"
KONSOLA="no"
GRY=""
SKRYPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BUILD_DIR="${HOME}/armbian-build"
FORK="https://github.com/cyryllo/build-armbian.git"
# DLACZEGO te trzy galezie, a nie numery PR: galezie zawieraja dokladnie to,
# co jest w PR-ach, a baza (armbian/build 23cdcc2) jest ta sama dla wszystkich.
GALEZIE=(sunxi-edt-ft5x06 sunxi-edt-ft5x06-retry-identify sunxi-lemaker-lcd-overlays)

pomoc() {
	cat <<- EOF
		Uzycie: $0 [opcje] [-- dodatkowe opcje compile.sh]

		  -e, --ekran N       ekran wlaczony od pierwszego startu: brak (domyslnie), 7, 7-hdmi albo 5
		  -p, --pulpit NAZWA  xfce (domyslnie) albo brak (obraz minimal bez pulpitu)
		  -g, --konsola       konsola do gier: RetroArch na ekranie od startu, jak Lakka
		                      (tylko z --pulpit brak; najpierw konsola/zbuduj-rdzenie.sh)
		      --gry DIR       gry dolaczone do obrazu konsoli, DIR/<system>/plik (np. DIR/mame2003/gra.zip);
		                      obrazu z grami nie publikuj (prawa autorskie)
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
		--gry) GRY="${2:-}"; shift 2 ;;
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
	compgen -G "${SKRYPT_DIR}/konsola/rdzenie/*_libretro.so" > /dev/null ||
		blad "brak rdzeni, uruchom najpierw: ${SKRYPT_DIR}/konsola/zbuduj-rdzenie.sh"
	[[ -x "${SKRYPT_DIR}/konsola/retroarch-bin/retroarch" ]] ||
		blad "brak RetroArch, uruchom najpierw: ${SKRYPT_DIR}/konsola/zbuduj-retroarch.sh"
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

# CO: polaczenie trzech galezi PR w lokalna galaz lemaker-prs.
echo ">> Pobieram galezie PR z ${FORK}"
git fetch -q "${FORK}" "${GALEZIE[@]}"
# DLACZEGO FETCH_HEAD: git zapisuje tam pobrane galezie w kolejnosci z polecenia.
mapfile -t SHA < <(awk '{print $1}' .git/FETCH_HEAD)
[[ ${#SHA[@]} -eq ${#GALEZIE[@]} ]] || blad "nie udalo sie pobrac wszystkich galezi PR"
git checkout -q -B lemaker-prs "${SHA[0]}"
git -c user.name=zbuduj-obraz-pr -c user.email=zbuduj-obraz-pr@localhost merge -q --no-edit "${SHA[@]:1}"
echo ">> Armbian: $(git log -1 --format=%h HEAD) = armbian/build $(git merge-base "${SHA[0]}" "${SHA[1]}" | cut -c1-9) + PR-y"

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
	cp -r "${SKRYPT_DIR}"/konsola/autoconfig "${SKRYPT_DIR}"/konsola/retroarch-bin "${UP}/overlay/konsola/"
	cp "${SKRYPT_DIR}"/konsola/{customize-konsola.sh,retroarch.cfg,retroarch-konsola.service,konsola-listy,konsola-listy.service,konsola-listy.path,avahi-samba.service} "${UP}/overlay/konsola/"
	cp "${SKRYPT_DIR}"/konsola/rdzenie/{*_libretro.so,WERSJE.txt} "${UP}/overlay/konsola/rdzenie/"
	if [[ -n "${GRY}" ]]; then
		mkdir -p "${UP}/overlay/konsola/gry"
		cp -r "${GRY}/." "${UP}/overlay/konsola/gry/"
		echo ">> Gry startowe: $(find "${GRY}" -type f | wc -l) plikow (obrazu z grami nie publikuj)"
	fi
	echo 'bash /tmp/overlay/konsola/customize-konsola.sh' >> "${UP}/customize-image.sh"
fi

echo ">> Buduje: pulpit=${PULPIT}, ekran=${EKRAN}, konsola=${KONSOLA}, jadro current, Debian 13 trixie"
START=$(date +%s)
./compile.sh build USERPATCHES_PATH="${UP}" BOARD=bananapipro BRANCH=current RELEASE=trixie \
	KERNEL_CONFIGURE=no "${PULPIT_OPCJE[@]}" "${EXTRA[@]}"

# CO: obraz konsoli dostaje nazwe projektu: Arkada20_<data>_bananapipro_trixie_<jadro>.img
# DLACZEGO: to osobny system (Arkada20), a Armbian nazywa go tak samo jak zwykly
# obraz minimal (Armbian-unofficial_..._minimal.img) i nastepne budowanie by go nadpisalo.
if [[ "${KONSOLA}" == "yes" ]]; then
	img=$(ls -1t "${BUILD_DIR}"/output/images/*Bananapipro*trixie*_minimal.img 2> /dev/null | head -1)
	if [[ -n "${img}" && $(stat -c %Y "${img}") -ge ${START} ]]; then
		jadro=$(basename "${img}" | sed -E 's/.*_current_([0-9.]+)_minimal\.img/\1/')
		nowy="$(dirname "${img}")/Arkada20_$(date +%F)_bananapipro_trixie_${jadro}.img"
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
