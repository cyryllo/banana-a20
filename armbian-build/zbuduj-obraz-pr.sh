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

set -euo pipefail

EKRAN="brak"
PULPIT="xfce"
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
if [[ "${EKRAN}" != "brak" ]]; then
	# CO: dopisuje overlays=lemaker-lcdN, a dla wariantow z HDMI tez tryb 1080p.
	# DLACZEGO 1080p: LCD i HDMI dziela zegar PLL3, zegar LCD pasuje tylko do 1080p/720p.
	HDMI=""
	[[ "${EKRAN}" == "5" || "${EKRAN}" == "7-hdmi" ]] && HDMI="video=HDMI-A-1:1920x1080@60"
	cat > "${UP}/customize-image.sh" <<- EOF
		#!/bin/bash
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
	chmod +x "${UP}/customize-image.sh"
fi

echo ">> Buduje: pulpit=${PULPIT}, ekran=${EKRAN}, jadro current, Debian 13 trixie"
./compile.sh build USERPATCHES_PATH="${UP}" BOARD=bananapipro BRANCH=current RELEASE=trixie \
	KERNEL_CONFIGURE=no "${PULPIT_OPCJE[@]}" "${EXTRA[@]}"

echo
echo ">> Gotowe. Obrazy:"
ls -1t "${BUILD_DIR}"/output/images/*Bananapipro*trixie*.img 2> /dev/null | head -3 || true
