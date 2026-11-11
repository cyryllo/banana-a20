#!/bin/bash
# Bosman20: instalacja Klipper, Moonraker, Mainsail (KIAUH) i KlipperScreen.
# Uruchamiany przez customize-bosman20.sh w chroot obrazu, jako root, ale z
# HOME, USER i LOGNAME ustawionymi na bosman (wlasciciel plikow zmieniany potem).
#
# DLACZEGO root: w chroot obrazu programy ARM dzialaja przez emulacje QEMU, w ktorej
#     sudo nie podnosi uprawnien zwyklego uzytkownika ("effective uid is not 0").
#     KIAUH bierze uzytkownika z USER/LOGNAME, a katalog z HOME, wiec instaluje
#     wszystko tak, jakby uruchomil go bosman.
# DLACZEGO main.py zamiast kiauh.sh: kiauh.sh odmawia pracy jako root; to jedyne
#     takie sprawdzenie w KIAUH.
# DLACZEGO TERM: KIAUH bez zmiennej TERM konczy sie od razu kodem 1.
# PIP_FIND_LINKS (ustawione przez wywolujacego): gotowe pakiety Pythona z
#     bosman20/wheels, zeby nie kompilowac ich w emulacji i nie zalezec od piwheels.

set -euo pipefail
cd "${HOME}"
git clone -q https://github.com/dw-0/kiauh.git
# DLACZEGO PYTHONPATH: KIAUH importuje sam siebie jako pakiet "kiauh"; kiauh.sh
# ustawia to tak samo przed uruchomieniem main.py.
export PYTHONPATH="${HOME}/kiauh"
python3 kiauh/kiauh/main.py install klipper --create-example-cfg
python3 kiauh/kiauh/main.py install moonraker --create-example-cfg
python3 kiauh/kiauh/main.py install mainsail --install-config
unset PYTHONPATH

# CO: reguly polkit dla Moonrakera (restart plytki i uslug z Mainsail/KlipperScreen).
# DLACZEGO osobno: KIAUH uruchamia ten skrypt bez --root, a skrypt jako root bez
# --root odmawia ("must not run as root"); USER=bosman wskazuje, komu dac uprawnienia.
bash moonraker/scripts/set-policykit-rules.sh --root --disable-systemctl

git clone -q https://github.com/KlipperScreen/KlipperScreen.git
# CO: kopia instalatora KlipperScreen bez sprawdzania roota (z tego samego powodu co wyzej).
# NETWORK=N: NetworkManagera instaluje customize-bosman20.sh, a instalator przy
# NETWORK=Y na koncu restartuje system.
sed 's/if \[ "\$EUID" == 0 \]/if false/' KlipperScreen/scripts/KlipperScreen-install.sh > /tmp/ks-install-budowanie.sh
grep -q 'if false' /tmp/ks-install-budowanie.sh || { echo "BLAD: nie udalo sie wylaczyc sprawdzania roota w instalatorze KlipperScreen" >&2; exit 1; }
cd KlipperScreen/scripts
# DLACZEGO kopia w scripts/: instalator szuka swoich plikow obok siebie (SCRIPTPATH).
cp /tmp/ks-install-budowanie.sh ./KlipperScreen-install-budowanie.sh
BACKEND=X NETWORK=N SERVICE=Y START=0 bash ./KlipperScreen-install-budowanie.sh
rm -f ./KlipperScreen-install-budowanie.sh /tmp/ks-install-budowanie.sh
