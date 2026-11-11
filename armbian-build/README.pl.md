[English](README.md) | **Polski**

# Budowanie obrazu Armbiana dla Banana Pro z obsługą ekranów LeMaker

Ten katalog pozwala zbudować własny obraz Armbiana (Debian 13 trixie, pulpit XFCE) dla LeMaker Banana Pro, w którym ekrany LeMakera działają od pierwszego uruchomienia. Jeden obraz obsługuje wszystkie ekrany, wybierasz go na płytce. Później nic nie trzeba doinstalowywać.

W porównaniu z gotowym obrazem z armbian.com:

- sterownik dotyku `edt-ft5x06` jest włączony w jądrze (Armbian domyślnie go nie budował),
- skompilowane nakładki dla wszystkich ekranów (3,5", 5", 7") są już w `/boot/overlay-user/`,
- domyślnie włączony jest ekran 7", inne przełącza się poleceniem `sudo lemaker-lcd 5` (albo `35`, `7`, `7-hdmi`, `off`) albo odkomentowaniem jednej linii w `/boot/armbianEnv.txt`,
- jądro ma małą poprawkę `edt-ft5x06`, która raz ponawia rozpoznanie układu dotyku (pierwsza transmisja I2C po starcie zawsze się nie udaje), dzięki czemu dotyk działa od razu po starcie,
- zainstalowane są `evtest` i `i2c-tools` do sprawdzania dotyku,
- źródła nakładek `.dts` są w `/usr/local/share/lemaker-lcd/` (do poprawek na płytce).

Budowanie opiera się na oficjalnym [systemie budowania Armbiana](https://docs.armbian.com/build-framework/getting-started/) i na tym samym poleceniu, którego Armbian używa do swoich gotowych obrazów:

```bash
./compile.sh BOARD=bananapipro RELEASE=trixie BUILD_DESKTOP=no BUILD_MINIMAL=yes KERNEL_CONFIGURE=no
```

## Zawartość

| Plik | Do czego służy |
|---|---|
| `zbuduj-obraz-pr.sh` | Buduje obrazy od v0.6 z oficjalnego systemu budowania Armbiana, który od listopada 2026 ma obsługę LeMakera ([#11293](https://github.com/armbian/build/pull/11293), [#11294](https://github.com/armbian/build/pull/11294), [#11296](https://github.com/armbian/build/pull/11296), wszystkie przyjęte). Ekran włącza się linią `overlays=lemaker-lcd7` (`lcd5`, `lcd7-hdmi`), tak jak w oficjalnym Armbianie. Buduje też obraz konsoli [Arkada20](../arkada20/README.pl.md) (`--konsola`). |
| `zbuduj-obraz.sh` | Skrypt, który robi wszystko: pobiera system budowania Armbiana, kopiuje pliki, uruchamia budowanie. |
| `lemaker-lcd` | Skrypt do przełączania ekranów, instalowany na płytce jako `/usr/local/sbin/lemaker-lcd`. |
| `userpatches/kernel/archive/sunxi-6.18/edt-ft5x06-retry-identify-after-bus-recovery.patch` | Poprawka jądra: sterownik dotyku raz ponawia rozpoznanie po odzyskaniu magistrali I2C przy starcie. |
| `lemaker-touch-retry`, `lemaker-touch-retry.service` | Nieużywane w obrazach. Tylko dla jąder bez powyższej poprawki (np. moduł zbudowany ręcznie), zobacz [overlays/README.pl.md](../overlays/README.pl.md#ręczna-instalacja-na-istniejącym-armbianie). |
| `userpatches/config-bananapro-lcd.conf` | Ustawienia budowania (płytka, Debian 13, jądro) i włączenie sterownika dotyku. |
| `userpatches/customize-image.sh` | Uruchamiany przez Armbiana wewnątrz obrazu: kompiluje nakładki, instaluje `lemaker-lcd` i włącza domyślny ekran. |

## Obrazy z oficjalnymi nakładkami (od v0.6)

```bash
git clone https://github.com/cyryllo/banana-a20.git
cd banana-a20/armbian-build
./zbuduj-obraz-pr.sh --ekran 7          # XFCE, overlays=lemaker-lcd7
./zbuduj-obraz-pr.sh --pulpit brak      # minimal, LCD wyłączony
```

Skrypt pobiera oficjalny [armbian/build](https://github.com/armbian/build) (domyślnie gałąź `main`) do lokalnej gałęzi `zbuduj-obraz-pr` w `~/armbian-build`, sprawdza, czy ta wersja ma już obsługę LeMakera (sterownik dotyku i nakładki `lemaker-lcd`, przyjęte 2026-11-10), i buduje z osobnym katalogiem `userpatches-lemaker-pr`, więc pliki `zbuduj-obraz.sh` z `userpatches/` nie są używane. Na koniec przywraca poprzedni commit. Nazwa kończy się na `-pr`, bo na początku skrypt budował z gałęzi PR, zanim zostały przyjęte.

| Opcja | Znaczenie |
|---|---|
| `--ekran N` | ekran włączony przy pierwszym starcie: `brak` (domyślnie, LCD wyłączony), `7`, `7-hdmi` albo `5`; dla `5` i `7-hdmi` dopisuje też `extraargs=video=HDMI-A-1:1920x1080@60` |
| `--pulpit NAZWA` | `xfce` (domyślnie) albo `brak` (obraz minimal bez pulpitu) |
| `--konsola` | konsola do gier [Arkada20](../arkada20/README.pl.md) (tylko z `--pulpit brak`) |
| `--armbian REF` | gałąź, tag albo commit armbian/build (domyślnie `main`); stały commit daje ponownie ten sam obraz, np. do wydania |
| `--repo URL` | inne repozytorium armbian/build, np. fork ze zmianą jeszcze nieprzyjętą (domyślnie `https://github.com/armbian/build.git`) |
| `--katalog KATALOG` | katalog armbian/build (domyślnie `~/armbian-build`) |

Wymagania są takie same jak niżej. Cotygodniowe oficjalne obrazy Armbiana dla Banana Pro (minimal, jądro `current`) mają tę samą obsługę ekranów, gdy są zbudowane z wersji po 2026-11-10; ten skrypt służy do obrazu z XFCE, ekranu włączonego od pierwszego startu, Arkady20 albo konkretnej wersji Armbiana.

Dalsza część tej strony opisuje `zbuduj-obraz.sh` (obrazy do v0.5, przełączanie ekranów poleceniem `lemaker-lcd`).

## Wymagania (komputer, na którym budujesz)

- Linux x86_64 albo arm64 (najlepiej Debian 13),
- co najmniej 8 GB RAM i ok. 50 GB wolnego miejsca na dysku,
- Docker, git i emulator ARM (QEMU), bez którego Armbian nie przygotuje obrazu armhf na komputerze x86:

```bash
sudo apt install -y git docker.io docker-buildx qemu-user-binfmt
sudo usermod -aG docker $USER    # potem wyloguj się i zaloguj ponownie
```

Ścieżka do katalogu budowania nie może zawierać spacji (wymóg Armbiana). Domyślnie skrypt używa `~/armbian-build`.

## Szybki sposób: skrypt

```bash
git clone https://github.com/cyryllo/banana-a20.git
cd banana-a20/armbian-build
./zbuduj-obraz.sh
```

Powstaje obraz z pulpitem XFCE i włączonym ekranem 7". Opcje:

| Opcja | Znaczenie |
|---|---|
| `--ekran 5` | Ekran włączony domyślnie: `7` (domyślnie), `7-hdmi` (7" do pracy z HDMI), `5`, `35` albo `brak` (tylko HDMI). Wszystkie nakładki i tak są w obrazie. |
| `--pulpit brak` | Obraz bez pulpitu (Armbian minimal) zamiast XFCE. |
| `--jadro edge` | Nowsze jądro (7.3) zamiast `current` (6.18). Nakładki były sprawdzane na `current`. |
| `--katalog /ścieżka` | Inny katalog na system budowania Armbiana (bez spacji). |
| `--aktualizuj` | Przed budowaniem pobiera najnowszy system budowania Armbiana (`git pull`). |
| `-- OPCJE` | Wszystko po `--` trafia do `compile.sh`, np. `-- KERNEL_CONFIGURE=yes`. |

Gotowy obraz jest w `~/armbian-build/output/images/`, z nazwą w rodzaju `Armbian-unofficial_..._Bananapipro_trixie_current_6.18.x_xfce_desktop.img` (albo `..._minimal.img` bez pulpitu).

Wariant XFCE używa poziomu pulpitu `minimal` (pulpit i ekran logowania, ok. 500 MB), bo A20 ma tylko 1 GB RAM. Więcej programów można doinstalować później przez `armbian-config`.

**Czas:** pierwsze budowanie trwa długo (od ok. 20 minut do kilku godzin, zależnie od komputera), bo jądro jest kompilowane od zera. Nie da się użyć gotowego jądra z serwerów Armbiana, bo zmieniamy jego konfigurację (dotyk). Kolejne budowania korzystają z pamięci podręcznej i trwają kilka minut.

## Sposób ręczny (bez skryptu)

Te same kroki, które wykonuje skrypt:

```bash
# 1. System budowania Armbiana
git clone --depth 1 https://github.com/armbian/build.git ~/armbian-build

# 2. Nasze pliki do userpatches
cd ~/banana-a20          # tam, gdzie sklonowano to repozytorium
mkdir -p ~/armbian-build/userpatches/overlay/lemaker-lcd
cp armbian-build/userpatches/config-bananapro-lcd.conf ~/armbian-build/userpatches/
cp armbian-build/userpatches/customize-image.sh        ~/armbian-build/userpatches/
cp overlays/bananapro-lemaker-lcd*.dts armbian-build/lemaker-lcd ~/armbian-build/userpatches/overlay/lemaker-lcd/
cp -r armbian-build/userpatches/kernel ~/armbian-build/userpatches/
echo 7 > ~/armbian-build/userpatches/overlay/lemaker-lcd/ekran     # domyślny ekran: 7, 5, 35 albo brak

# 3. Budowanie
cd ~/armbian-build
./compile.sh bananapro-lcd BUILD_DESKTOP=yes BUILD_MINIMAL=no DESKTOP_ENVIRONMENT=xfce DESKTOP_TIER=minimal
```

`./compile.sh bananapro-lcd` wczytuje `userpatches/config-bananapro-lcd.conf`. Ustawia on `BRANCH=current` (inaczej compile.sh pyta o jądro) i włącza moduł dotyku. Bez opcji pulpitu powstaje obraz minimal, jak z polecenia armbian.com.

## Jak to działa

1. **Dotyk.** `config-bananapro-lcd.conf` zawiera funkcję `custom_kernel_config__lemaker_lcd_touch`, która dopisuje `CONFIG_TOUCHSCREEN_EDT_FT5X06=m` do konfiguracji jądra. To oficjalny mechanizm Armbiana (hook `custom_kernel_config`). Moduł ładuje się sam, gdy nakładka ekranu opisuje układ dotyku. Armbian nakłada na jądro każdy plik `.patch` z `userpatches/kernel/archive/sunxi-6.18/`, tutaj poprawkę `edt-ft5x06`: przy starcie pierwsza transmisja I2C do układu kończy się błędem magistrali (`mv64xxx ... Ctlr Error ... status: 0x0`), sterownik I2C odzyskuje magistralę i zwraca `-EAGAIN`, a poprawiony sterownik próbuje jeszcze raz (`identification failed, retrying` w `dmesg`).
2. **Nakładki.** Armbian udostępnia `userpatches/overlay/` wewnątrz obrazu jako `/tmp/overlay` i tam uruchamia `customize-image.sh`. Skrypt kompiluje każdy plik `.dts` poleceniem `dtc -@` (tak samo jak `armbian-add-overlay`) i zapisuje wynik w `/boot/overlay-user/`.
3. **Wybór ekranu.** Skrypt instaluje `lemaker-lcd` i uruchamia go z domyślnym ekranem. Na końcu `/boot/armbianEnv.txt` zapisuje blok z jedną aktywną linią `user_overlays=` i zakomentowanymi liniami dla pozostałych ekranów. U-Boot pomija linie zaczynające się od `#`, gdy czyta ten plik.

## Nagrywanie obrazu na kartę SD

Najprościej programem [USBImager](https://gitlab.com/bztsrc/usbimager) albo balenaEtcher. Z wiersza poleceń (dwa razy sprawdź nazwę karty w `lsblk`, `dd` bez pytania nadpisuje podany dysk):

```bash
lsblk
sudo dd if=~/armbian-build/output/images/NAZWA_OBRAZU.img of=/dev/sdX bs=4M status=progress conv=fsync
```

Dla skompresowanego obrazu z Releases:

```bash
xz -dc NAZWA_OBRAZU.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

Włóż kartę do Banana Pro i podłącz ekran przed włączeniem zasilania. Komunikaty programu rozruchowego (U-Boot) są tylko na HDMI, obraz na LCD pojawia się dopiero, gdy wystartuje jądro. To normalne.

## Pierwsze uruchomienie i sprawdzenie

Po pierwszym zalogowaniu (kreator Armbiana pyta o hasło roota i nowego użytkownika):

```bash
cat /boot/armbianEnv.txt | grep user_overlays    # powinna tu być wybrana nakładka
lsmod | grep edt                                  # moduł dotyku załadowany
ls /sys/class/backlight/                          # podświetlenie
dmesg | grep -iE "sun4i|lvds|panel|edt"
```

Więcej poleceń diagnostycznych i tabela problemów są w [głównym README](../README.pl.md#problemy).

## Wybór ekranu

Wszystkie nakładki są już w obrazie. Domyślnie włączony jest ekran 7". Inny ekran włączysz skryptem:

```bash
sudo lemaker-lcd          # pokazuje, który ekran jest włączony
sudo lemaker-lcd 5        # włącza ekran 5" (albo 35, 7, 7-hdmi)
sudo lemaker-lcd off      # wyłącza LCD, tylko HDMI
sudo reboot
```

Albo zmień plik ręcznie i odkomentuj dokładnie jedną linię:

```bash
sudo nano /boot/armbianEnv.txt
```

```
# >>> lemaker-lcd
# LeMaker LCD: uncomment ONE line below (or run: sudo lemaker-lcd 35|5|7|7-hdmi|off)
#user_overlays=bananapro-lemaker-lcd35
user_overlays=bananapro-lemaker-lcd5
#user_overlays=bananapro-lemaker-lcd7
# <<< lemaker-lcd
```

Jeśli odkomentujesz dwie linie, liczy się tylko ostatnia. Skrypt nie rusza innych nakładek (nie LeMakera) w linii `user_overlays=`.

**Z podłączonym monitorem HDMI** użyj `7-hdmi` zamiast `7` (ekran 5" działa bez zmian), inaczej LCD miga. `lemaker-lcd 5` i `lemaker-lcd 7-hdmi` dopisują też `extraargs=video=HDMI-A-1:1920x1080@60`, bo tylko tryby 1080p i 720p korzystają z tego samego zegara co LCD. Bez HDMI możesz zamiast tego dopisać `bananapro-disable-hdmi` do linii `user_overlays=`. Szczegóły w [głównym README](../README.pl.md#lcd-i-hdmi-jednocześnie).

Uwaga: Armbian trzyma `/boot` na tej samej partycji ext4 co system, więc przed pierwszym startem nie da się zmienić tego pliku z Windowsa. Jeśli Twój ekran to nie 7", uruchom płytkę raz z HDMI (albo przez SSH), przełącz ekran i zrestartuj. Na Linuksie możesz zamontować kartę i zmienić `boot/armbianEnv.txt` bezpośrednio.

## Sprawdzanie dotyku

Na pulpicie XFCE po prostu dotknij ekranu, kursor powinien iść za palcem. Bez pulpitu (albo żeby zobaczyć szczegóły) użyj `evtest`:

```bash
sudo evtest      # wybierz urządzenie EDT-FT5x06 i dotknij ekranu, powinny pojawić się wartości X/Y
```

Jeśli osie są odwrócone albo zamienione, zobacz [Zmiany w nakładce](../overlays/README.pl.md#zmiany-w-nakładce).

## Poprawianie nakładki na płytce

Źródła są w `/usr/local/share/lemaker-lcd/`. Po zmianie (np. polaryzacji podświetlenia, osi dotyku) zainstaluj plik ponownie:

```bash
sudo nano /usr/local/share/lemaker-lcd/bananapro-lemaker-lcd7.dts
sudo armbian-add-overlay /usr/local/share/lemaker-lcd/bananapro-lemaker-lcd7.dts
sudo reboot
```

Gdy poprawka się sprawdzi, przenieś ją do repozytorium, żeby trafiła do kolejnych obrazów.

## Aktualizacje jądra

Obraz korzysta z repozytorium Armbiana, więc `apt upgrade` może zainstalować oficjalne jądro **bez** modułu dotyku. Obraz i podświetlenie dalej będą działać, dotyk przestanie. Są dwie możliwości:

- wstrzymać aktualizacje jądra: `sudo apt-mark hold linux-image-current-sunxi linux-dtb-current-sunxi`
- albo zbudować moduł na płytce po aktualizacji (zobacz [Ręczna instalacja](../overlays/README.pl.md#ręczna-instalacja-na-istniejącym-armbianie), sterownik dotyku).

Nowsze jądro z dotykiem dostaniesz, budując obraz ponownie z `--aktualizuj`. Same pakiety jądra (`.deb`, do instalacji przez `dpkg -i`) są po budowaniu w `~/armbian-build/output/debs/`.

## Problemy przy budowaniu

| Objaw | Co zrobić |
|---|---|
| `permission denied` od Dockera | Dodaj się do grupy `docker` (zobacz Wymagania) i zaloguj ponownie. |
| `armhf: not supported on this machine/kernel` albo `Failed to update binfmts` | Na komputerze brakuje emulatora ARM: `sudo apt install qemu-user-binfmt`, potem `ls /proc/sys/fs/binfmt_misc/` powinno pokazać `qemu-arm`. |
| Brak miejsca na dysku | Armbian potrzebuje ok. 50 GB. Pamięć podręczna jest w `~/armbian-build/cache/`. |
| `customize-image.sh exited with error` | Szczegóły są w `~/armbian-build/output/logs/`. Najczęściej błąd składni w którymś pliku `.dts`. |
| Skrypt przeniósł mój `customize-image.sh` do `.bak` | Robi tak, gdy w `userpatches/` był już inny skrypt. Dopisz własne polecenia na końcu naszego. |
| Budowanie zadaje pytania w menu | Upewnij się, że uruchamiasz `./compile.sh bananapro-lcd` (z nazwą konfiguracji). |

## Źródła

- System budowania Armbiana, pierwsze kroki: <https://docs.armbian.com/build-framework/getting-started/>
- Pliki użytkownika (userpatches, customize-image.sh): <https://docs.armbian.com/build-framework/user-configurations/>
- Hooki, w tym `custom_kernel_config`: <https://docs.armbian.com/build-framework/extensions/hooks/>
- Repozytorium systemu budowania Armbiana: <https://github.com/armbian/build>
