[English](README.md) | **Polski**

# banana-a20: LeMaker Banana Pro na współczesnym Linuksie

Projekty, które przywracają do życia **LeMaker Banana Pro** (i zwykłe Banana Pi, oba z procesorem Allwinner A20) na współczesnym systemie: Armbian z Debianem 13 i jądrem mainline.

LeMaker produkował Banana Pro, ekrany LCD i płytki rozszerzeń w latach 2014-2015. Firmy już nie ma, a jej oprogramowanie (pliki `script.bin`, sterownik dotyku, biblioteki GPIO) działało tylko ze starym jądrem sunxi 3.4. To repozytorium zbiera wszystko, czego potrzeba, żeby dziś używać tych płytek i ekranów.

| Projekt | Co to jest | Stan |
|---|---|---|
| [Ekrany LCD LeMaker](#ekrany-lcd-lemaker) | ekrany dotykowe 5" i 7" na jądrze mainline, gotowe obrazy | gotowe, przyjęte do oficjalnego Armbiana |
| [Arkada20](arkada20/README.pl.md) | konsola do gier retro: płytka od razu uruchamia RetroArch, jak Lakka | v1.1, sprawdzona z ekranem 7" |
| [Bosman20](bosman20/README.pl.md) | host drukarki 3D: Klipper, Moonraker, Mainsail i KlipperScreen na ekranie dotykowym, instalowane przez KIAUH | pierwszy obraz, w testach |
| [GPIO](gpio/README.pl.md) | grafika pinów, WiringBP (C, `gpio readall`) i LMK.GPIO (Python, API RPi.GPIO) poprawione pod obecne jądro, lg (lgpio/rgpio) zamiast pigpio, przykłady | gotowe, sprawdzone na płytce |

Gotowe obrazy są na stronie [Releases](https://github.com/cyryllo/banana-a20/releases): `v0.x-...` to obrazy z ekranami LCD, `arkada20-...` to konsola do gier, `bosman20-...` to host drukarki 3D.

## Ekrany LCD LeMaker

LeMaker zrobił trzy ekrany dotykowe dla Banana Pi/Pro: 3,5" (320x240), 5" (800x480) i 7" (1024x600), podłączane taśmą, z dotykiem w zestawie.

| Ekran | Obraz | Dotyk |
|---|---|---|
| 7" LVDS 1024x600 | ✅ działa, także razem z HDMI | ✅ działa |
| 5" RGB 800x480 | ✅ działa, także razem z HDMI | sterownik sprawdzony, pełny test czeka (testowy ekran ma pękniętą szybę dotyku) |
| 3,5" RGB 320x240 | nie sprawdzony (brak sprzętu) | ten sam układ co w 7" |

Wszystko działa też na zwykłym Banana Pi (bez „Pro”).

### Co zostało zrobione

Na jądrze mainline ekrany były czarne: jądro nie czyta pliku `script.bin`. Ustawienia ekranów ze starych plików `fex` LeMakera zostały przepisane na nakładki Device Tree (overlay), a po drodze trzeba było rozwiązać trzy problemy:

- **dotyk nie startował:** pierwsza transmisja I2C do układu dotyku po włączeniu zasilania zawsze kończy się błędem; mała poprawka jądra sprawia, że sterownik próbuje jeszcze raz i dotyk działa od razu po starcie,
- **LCD migał przy podłączonym monitorze HDMI:** LCD i HDMI korzystają z jednego zegara; częstotliwości ekranów dobrano tak, żeby oba mogły z niego działać jednocześnie,
- **ekran 7" wymaga trybu LVDS,** który jądro włącza tylko dla ekranu opisanego jako `panel-lvds`.

Ta praca jest teraz częścią **oficjalnego Armbiana** (wszystkie trzy zmiany przyjęte w listopadzie 2026):

- [armbian/build#11293](https://github.com/armbian/build/pull/11293): sterownik dotyku `edt-ft5x06` włączony w jądrze,
- [armbian/build#11294](https://github.com/armbian/build/pull/11294): poprawka ponawiająca rozpoznanie dotyku,
- [armbian/build#11296](https://github.com/armbian/build/pull/11296): nakładki `lemaker-lcd5`, `lemaker-lcd7` i `lemaker-lcd7-hdmi`.

Szczegóły techniczne (jak to działa, timingi, ręczna instalacja, zmiany w nakładce): [overlays/README.pl.md](overlays/README.pl.md).

### Szybki start

1. Pobierz obraz ze strony [Releases](https://github.com/cyryllo/banana-a20/releases) (najnowsze wydanie z ekranami: `v0.6`):
   - **`..._xfce_desktop.img.xz`**: pulpit XFCE, włączony ekran 7",
   - **`..._minimal.img.xz`**: bez pulpitu, LCD wyłączony (tylko HDMI), baza do własnej konfiguracji.
2. Nagraj go na kartę SD programem [USBImager](https://gitlab.com/bztsrc/usbimager) albo balenaEtcher.
3. Podłącz ekran, włóż kartę, włącz zasilanie. Obraz na LCD pojawia się, gdy wystartuje jądro (pierwsze komunikaty startowe są tylko na HDMI).

Oficjalne obrazy i jądra Armbiana zbudowane z przyjętymi zmianami działają tak samo. Oficjalny pakiet jądra dostępny w listopadzie 2026 (`linux-image-current-sunxi` 26.8.3) jeszcze ich nie zawiera, zobacz [Problemy](#problemy), punkt o aktualizacji jądra.

### Wybór ekranu

Ekran wybiera linia `overlays=` w pliku `/boot/armbianEnv.txt` (`sudo nano /boot/armbianEnv.txt`, potem `sudo reboot`):

```
overlays=lemaker-lcd7
```

| Wartość | Ekran |
|---|---|
| `lemaker-lcd5` | 5" RGB, także razem z HDMI |
| `lemaker-lcd7` | 7" LVDS bez HDMI (64 Hz) |
| `lemaker-lcd7-hdmi` | 7" LVDS do pracy z HDMI (ok. 50 Hz) |

Używaj tylko jednej wartości `lemaker-lcd...` naraz. Inne nakładki mogą zostać w tej samej linii, oddzielone spacjami. Żeby wyłączyć LCD, usuń wartość `lemaker-lcd...`. Nakładki można też przełączać w `sudo armbian-config`.

`/boot` jest na partycji linuksowej (ext4), więc nie da się go edytować z Windowsa: uruchom płytkę raz z monitorem HDMI albo zaloguj się przez SSH, żeby zmienić ekran.

### LCD i HDMI jednocześnie

- **7":** użyj `overlays=lemaker-lcd7-hdmi`. Ekran 5" (`lemaker-lcd5`) działa z HDMI bez zmian.
- HDMI musi pracować w trybie **1920x1080 albo 1280x720**: dopisz `extraargs=video=HDMI-A-1:1920x1080@60` w `/boot/armbianEnv.txt`, a na pulpicie też wybierz dla HDMI jeden z tych dwóch trybów.
- Bez tego LCD działa, ale miga, gdy podłączony jest monitor HDMI.

### Ustawienia ekranu

**Jasność** (0 = wyłączone, 255 = maksimum, 200 po pierwszym starcie):

```bash
cat /sys/class/backlight/*/brightness                 # obecna wartość
echo 120 | sudo tee /sys/class/backlight/*/brightness  # ustawienie
```

Ostatnia wartość wraca przy kolejnym starcie. Na pulpicie XFCE działa też suwak jasności w menedżerze zasilania.

**Wyłączenie HDMI** (tylko LCD): `sudo armbian-add-overlay overlays/bananapro-disable-hdmi.dts` z kopii tego repozytorium, potem restart. Polecenie dopisuje `user_overlays=bananapro-disable-hdmi`, usuń tę linię, żeby z powrotem włączyć HDMI.

### Problemy

| Objaw | Co zrobić |
|---|---|
| LCD miga tylko przy podłączonym HDMI | zobacz [LCD i HDMI jednocześnie](#lcd-i-hdmi-jednocześnie) |
| dotyk albo ekran przestał działać po `apt upgrade` | oficjalny pakiet jądra nie ma jeszcze obsługi LeMakera; zostaw jądro z obrazu: `sudo apt-mark hold linux-image-current-sunxi linux-dtb-current-sunxi` (cofnij przez `apt-mark unhold`, gdy wyjdzie nowsze oficjalne jądro) |
| podświetlenie działa odwrotnie, kolorowy szum, odwrócony dotyk | drobne zmiany w nakładce, zobacz [Zmiany w nakładce](overlays/README.pl.md#zmiany-w-nakładce) |

Zgłoszenia mile widziane jako issue na GitHubie albo w [wątku na forum Armbiana](https://forum.armbian.com/topic/7233-bananapi-pro-7-touchlcd-with-debian-buster-and-mainline-kernel-5xxxx/). Dołącz wynik:

```bash
dmesg | grep -iE "sun4i|lvds|panel|edt|pwm|i2c-2"
grep -A1 -i edt /proc/bus/input/devices
```

## Arkada20

System konsoli do gier retro dla Banana Pro z ekranem LeMakera: przenośna konsolka z ekranem 5" albo automat do gier z ekranem 7". Płytka od razu uruchamia RetroArch (NES, SNES, Game Boy, GBA, Mega Drive, PlayStation, automaty z MAME 2003-Plus i FBNeo...), Wi-Fi ustawia się w menu, gry kopiuje się przez sieć. Gier nie ma w zestawie.

Więcej: [arkada20/README.pl.md](arkada20/README.pl.md).

## GPIO

Złącze 40 pinów Banana Pro i dwie biblioteki LeMakera znowu działające na obecnym jądrze: **WiringBP** (WiringPi dla C, z `gpio readall`) i **LMK.GPIO** (RPi.GPIO dla Pythona). pigpio nie ruszy na A20, zamiast niego działa jego następca **lg** (lgpio, rgpio): programowy PWM i serwa na dowolnym pinie, powiadomienia o zmianach stanu, sterowanie przez sieć. Do tego standardowe narzędzia Linuksa (libgpiod), kolorowa grafika pinów i sprawdzone przykłady.

Więcej: [gpio/README.pl.md](gpio/README.pl.md).

## Zawartość repozytorium

| Katalog | Zawartość |
|---|---|
| [`overlays/`](overlays/README.pl.md) | nakładki Device Tree dla ekranów LCD i ich opis techniczny |
| [`armbian-build/`](armbian-build/README.pl.md) | skrypty do samodzielnego budowania obrazów |
| [`arkada20/`](arkada20/README.pl.md) | konsola do gier Arkada20 |
| [`bosman20/`](bosman20/README.pl.md) | host drukarki 3D Bosman20 |
| [`gpio/`](gpio/README.pl.md) | biblioteki GPIO, grafika pinów, przykłady |
| `stare jądro sunxi 3.4/` | oryginalne pliki `fex`/`bin` LeMakera dla starego jądra 3.4, zostawione jako źródło parametrów ekranów |

To repozytorium zaczęło się jako fork [LeMaker/fex_configuration](https://github.com/LeMaker/fex_configuration).

Historia projektu: [Banana Pro po latach: ekrany LeMaker w Armbianie, konsola Arkada20 i GPIO](https://cyryllo.pl/blog/banana-pro-po-latach-ekrany-lemaker-arkada20-gpio/).
