[English](README.md) | **Polski**

# Bosman20: host drukarki 3D na Banana Pro (Allwinner A20)

Bosman20 zamienia LeMaker Banana Pro (Banana Pi Pro) z ekranem LCD LeMakera w gotowy host drukarki 3D: **Klipper**, **Moonraker**, **Mainsail** w przeglądarce i **KlipperScreen** na ekranie dotykowym. Nagrywasz obraz na kartę SD, podłączasz płytkę drukarki przez USB, ustawiasz Wi-Fi palcem i drukujesz.

System jest zbudowany na Armbianie (Debian 13 trixie, jądro mainline) z obsługą ekranów LeMakera z tego repozytorium. Wszystko instaluje [KIAUH](https://github.com/dw-0/kiauh), tak samo jak przy instalacji ręcznej, więc później KIAUH może to aktualizować i nim zarządzać.

| Co | Stan |
|---|---|
| Klipper, Moonraker, Mainsail | instalowane przez KIAUH; ten sam zestaw działa u autora na drukarkach z Banana Pro |
| KlipperScreen na ekranie 7" | sprawdzony: obraz i dotyk |
| ekran 5" | działa z tą samą nakładką (`lemaker-lcd5`), mniejszy układ |
| budzenie ekranu dotykiem | zobacz [Znane problemy](#znane-problemy) |

## Pierwsze uruchomienie

1. Nagraj obraz na kartę SD ([USBImager](https://gitlab.com/bztsrc/usbimager) albo balenaEtcher), podłącz ekran 7", włącz zasilanie.
2. Na ekranie uruchamia się KlipperScreen. Dopóki drukarka nie jest skonfigurowana, pokazuje, że Klipper nie jest gotowy.
3. Wi-Fi: w KlipperScreen otwórz **Network** i wybierz sieć (albo podłącz kabel sieciowy).
4. Otwórz Mainsail w przeglądarce: **http://bosman20.local** (albo adres IP pokazany w KlipperScreen).
5. Podłącz płytkę drukarki przez USB i popraw `printer.cfg` w Mainsail (**Machine**), zobacz [Konfiguracja drukarki](#konfiguracja-drukarki).

Nie ma kreatora pierwszego uruchomienia. Konto do SSH:

| Użytkownik | Hasło |
|---|---|
| `bosman` | `bosman` |

Przy pierwszym logowaniu przez SSH (`ssh bosman@bosman20.local`) trzeba ustawić nowe hasło. Konto `root` nie ma logowania hasłem, używaj `sudo`.

## Konfiguracja drukarki

Obraz zawiera przykładowy `printer.cfg`, który ma tylko część dotyczącą hosta. Dla Twojej drukarki:

1. Weź konfigurację swojej drukarki albo płytki z Klippera (`~/klipper/config/printer-*.cfg` albo `generic-*.cfg`) i skopiuj ją do `printer.cfg` w Mainsail.
2. Znajdź port szeregowy płytki: `ls /dev/serial/by-id/` przez SSH, wpisz go w `[mcu] serial:`.
3. Zbuduj i wgraj firmware Klippera na płytkę: `cd ~/klipper && make menuconfig && make` (kompilatory ARM i AVR są już zainstalowane), potem postępuj według instrukcji dla swojej płytki.
4. Zrestartuj Klippera z Mainsail.

`printer.cfg` dołącza już `mainsail.cfg` (makra dla Mainsail).

## Aktualizacje

- Z Mainsail: **Machine → Update Manager** (Klipper, Moonraker, Mainsail, KlipperScreen).
- Przez SSH: `~/kiauh/kiauh.sh` (menu) albo `~/kiauh/kiauh.sh update klipper` itd.
- Pakiety systemowe: `sudo apt update && sudo apt upgrade`.

## Ekran

Włączony jest ekran 7". Dla ekranu 5" zmień `overlays=lemaker-lcd7` na `overlays=lemaker-lcd5` w `/boot/armbianEnv.txt` (`sudo nano /boot/armbianEnv.txt`) i zrestartuj. KlipperScreen wyłącza ekran po godzinie bezczynności; czas zmienisz w ustawieniach KlipperScreen (czas wyłączenia ekranu).

## Bezpieczeństwo

Mainsail i Moonraker nie mają hasła. Każdy w Twojej sieci lokalnej może sterować drukarką, tak samo jak w innych obrazach z Klipperem. Nie udostępniaj drukarki w internecie; do dostępu z zewnątrz użyj VPN albo ustaw `[authorization]` w `moonraker.conf`.

## Znane problemy

- **Dotyk nie budzi wygaszonego ekranu.** Gdy KlipperScreen wyłącza ekran, jądro odcina też zasilanie układu dotyku (ma wspólne zasilanie z panelem), więc dotyk nie może go obudzić. Obejście: dłuższy czas wygaszania albo „nigdy” w KlipperScreen. Poprawka (`vcc-supply` w węźle dotyku) jest sprawdzona i jest już w nakładkach tego repozytorium; trafi do następnego obrazu Bosman20 i jest zgłaszana do Armbiana.
- **Aktualizacje jądra:** dopóki nie wyjdzie oficjalne jądro Armbiana ze zmianami dla LeMakera, `apt upgrade` może zainstalować jądro bez obsługi ekranu. Zostaw jądro z obrazu: `sudo apt-mark hold linux-image-current-sunxi linux-dtb-current-sunxi`.

## Budowanie obrazu

Na komputerze z Linuksem x86 i Dockerem (wymagania: [../armbian-build/README.pl.md](../armbian-build/README.pl.md#wymagania-komputer-na-którym-budujesz)), z głównego katalogu repozytorium:

```bash
bosman20/zbuduj-pakiety-python.sh          # pakiety Pythona dla armhf (ok. 20 min, raz)
armbian-build/zbuduj-obraz-pr.sh --pulpit brak --ekran 7 --klipper
```

Obraz to `~/armbian-build/output/images/Bosman20_<data>_bananapipro_trixie_<jądro>.img`.

### Jak działa budowanie

| Plik | Co robi |
|---|---|
| `zbuduj-pakiety-python.sh` | buduje pakiety Pythona (wheels) Klippera, Moonrakera i KlipperScreen dla armhf w kontenerze ARM; na armhf wiele z nich nie ma gotowych pakietów, a piwheels nie zawsze jest osiągalny |
| `customize-bosman20.sh` | uruchamiany wewnątrz obrazu przy budowaniu: konto, instalacja przez KIAUH, NetworkManager, nazwa `bosman20` |
| `instaluj-stos.sh` | polecenia KIAUH (`install klipper`, `moonraker`, `mainsail`) i instalator KlipperScreen |
| `systemctl-budowanie` | zastępczy `systemctl` tylko na czas budowania: uruchomić usług bez systemd się nie da, włączyć można |

Przy budowaniu obrazu programy ARM działają przez emulację QEMU, w której `sudo` nie podnosi uprawnień zwykłego użytkownika. Instalatory działają więc jako root z `HOME`, `USER` i `LOGNAME` użytkownika `bosman`, a na koniec pliki dostają właściciela `bosman`. Wynik jest taki sam jak przy instalacji ręcznej.

## Licencje

Klipper (GPL v3), Moonraker (GPL v3), Mainsail (GPL v3), KlipperScreen (AGPL v3), KIAUH (GPL v3): obraz instaluje je z oficjalnych repozytoriów, dokładne wersje są w `/usr/local/share/bosman20-wersje.txt`.
