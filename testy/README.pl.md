[English](README.md) | **Polski**

# Test obrazów Armbiana na Banana Pi Pro

Lista kontrolna opiekuna płytki Banana Pi Pro (LeMaker Banana Pro, Allwinner A20) do testów obrazów Armbiana przed wydaniem, razem ze skryptem, który większość z niej sprawdza sam.

Armbian wymaga od opiekuna zatwierdzenia (sign-off), że płytka jest przetestowana i gotowa do wydania ([zasady dla opiekunów](https://docs.armbian.com/contribute/board-maintainer/)). Obrazy przygotowane do wydania są w https://fi.mirror.armbian.de/incoming/igorpecovnik/ i https://rsync.armbian.com/incoming/ . To, że coś nie działa, jest normalne: ważne, żeby było opisane i zgłoszone.

## Skrypt

Na płytce, z nagranym obrazem do testu:

```bash
wget https://raw.githubusercontent.com/cyryllo/banana-a20/master/testy/test-bananapipro.sh
chmod +x test-bananapipro.sh
sudo ./test-bananapipro.sh
```

| Opcja | Działanie |
|---|---|
| (bez opcji) | sprawdzenia automatyczne, potem kilka pytań (obraz, dotyk, dźwięk) |
| `--bez-pytan` | tylko sprawdzenia automatyczne, np. przez SSH bez ekranu |
| `--aktualizacja` | najpierw `apt update` i `apt full-upgrade`, potem test |

Wynik w katalogu domowym:

- `raport-bananapipro-<data>.md`: raport po angielsku w Markdown, gotowy do wklejenia na forum Armbiana albo do zgłoszenia na GitHubie,
- `raport-bananapipro-<data>-szczegoly.txt`: pełny `dmesg`, listy urządzeń, trybów ekranu i pakietów (do zgłoszeń błędów).

Na koniec skrypt pyta, czy wysłać dziennik przez `armbianmonitor -u` (publiczny link na paste.armbian.com, dopisywany do raportu). Skrypt niczego nie zapisuje na dyskach SATA i USB: testy szybkości tylko czytają. Na karcie SD zapisuje i od razu usuwa plik 64 MB.

## Lista kontrolna

A = sprawdza skrypt, P = skrypt pyta, R = ręcznie.

| Obszar | Co | Jak |
|---|---|---|
| Start | obraz minimal (CLI) uruchamia się | R: uruchom skrypt na tym obrazie |
| Start | obraz z pulpitem (XFCE) uruchamia się | R: uruchom skrypt na tym obrazie |
| System | płytka, wersja obrazu, jądro, nakładki | A |
| System | żadna usługa nie padła (`systemctl --failed`), czas startu | A |
| System | błędy jądra w `dmesg`, temperatura, taktowanie procesora | A |
| Karta SD | szybkość zapisu i odczytu, błędy `mmc` w `dmesg` | A |
| SATA | dysk wykryty, szybkość odczytu | A (gdy dysk podłączony) |
| USB | urządzenia na portach, szybkość odczytu pendrive'a | A (gdy podłączone) |
| USB | klawiatura i mysz działają | P |
| Ethernet | łącze 1000 Mb/s, adres IP | A |
| Wi-Fi | interfejs, sterownik, skanowanie sieci | A |
| Sieć | brama odpowiada, DNS działa | A |
| HDMI | monitor wykryty, tryb obrazu | A |
| HDMI | obraz poprawny | P |
| Ekrany LeMaker | nakładka, panel w drzewie urządzeń, podświetlenie, sterownik dotyku, zasilanie dotyku (`vcc-supply`) | A |
| Ekrany LeMaker | obraz poprawny | P |
| Ekrany LeMaker | dotyk: 5 stuknięć = 5 dotknięć (liczone z urządzenia wejścia) | A + P |
| Ekrany LeMaker | dotyk budzi wygaszony ekran (pulpit) | P |
| Ekrany LeMaker | każda nakładka: `lemaker-lcd5`, `lemaker-lcd7`, `lemaker-lcd7-hdmi` z monitorem HDMI | R: zmień `overlays=`, restart, skrypt jeszcze raz |
| Pulpit | menu, okna, przeglądarka plików działają płynnie | P |
| Dźwięk | karty dźwiękowe | A |
| Dźwięk | wyjście jack (ton testowy w obu kanałach), dźwięk przez HDMI | P |
| Pakiety | stan dpkg/apt, wersja jądra, wstrzymane pakiety | A |
| Aktualizacja | `apt full-upgrade` z poprzedniego wydania, restart, wszystko działa | R: `--aktualizacja`, restart, skrypt jeszcze raz |
| Wyłączanie | `sudo reboot` i `sudo poweroff` działają | R |

## Po teście

- Wszystko działa: zatwierdź płytkę w formularzu testów wydania (link w [zasadach dla opiekunów](https://docs.armbian.com/contribute/board-maintainer/)) albo napisz na forum, dołącz raport.
- Coś nie działa: zgłoś to jako issue w [armbian/build](https://github.com/armbian/build/issues), dołącz raport, plik ze szczegółami i link z `armbianmonitor -u`. Według Armbiana najważniejsze są: obraz się nie uruchamia, uszkodzone pakiety, karta SD lub eMMC działa źle. Wi-Fi, Bluetooth, GPIO i nakładki mają niższy priorytet.
