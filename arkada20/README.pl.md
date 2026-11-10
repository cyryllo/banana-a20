[English](README.md) | **Polski**

<p align="center"><img src="logo/arkada20-logo.svg" alt="Arkada20" width="520"></p>

# Arkada20: konsola do gier retro na Banana Pro (Allwinner A20)

Arkada20 zamienia LeMaker Banana Pro (Banana Pi Pro) z ekranem LCD LeMakera w konsolę do gier retro w stylu Lakki: płytka od razu uruchamia RetroArch, bez pulpitu i bez logowania. System jest zbudowany na Armbianie (Debian 13 trixie) z obsługą ekranów LeMakera z tego repozytorium.

Dwa zastosowania: przenośna konsolka z ekranem 5" i automat do gier z ekranem 7", oba sterowane padami USB albo joystickami arcade.

Nazwy w menu RetroArch są po angielsku (tak jak na ekranie konsoli), poza pozycją „Zamknij system”.

## Pobieranie

Gotowy obraz: [Releases](https://github.com/cyryllo/banana-a20/releases), tagi zaczynające się od `arkada20-` (pierwszy: [arkada20-v1.0-trixie-6.18.62](https://github.com/cyryllo/banana-a20/releases/tag/arkada20-v1.0-trixie-6.18.62)). Nagraj go na kartę SD programem [USBImager](https://gitlab.com/bztsrc/usbimager) albo balenaEtcher.

| Co | Stan |
|---|---|
| ekran 7" (automat) | sprawdzone: obraz, dźwięk, pady, Wi-Fi z menu |
| ekran 5" (konsolka) | ekran działa z tą samą nakładką, z Arkadą20 jeszcze nie sprawdzony |
| dotyk w menu | eksperymentalny, domyślnie wyłączony |
| Banana Pi (bez „Pro”) | powinno działać jak obrazy z ekranami, z Arkadą20 nie sprawdzone |

## Pierwsze uruchomienie

1. Nagraj obraz na kartę SD, podłącz ekran i pad USB, włącz zasilanie.
2. RetroArch uruchamia się na LCD (domyślnie włączony jest ekran 7", dla 5" zobacz [Ekran](#ekran)).
3. Połącz się z Wi-Fi w RetroArch: **Settings → Wi-Fi**. Hasło można wpisać klawiaturą USB albo klawiaturą ekranową.
4. Skopiuj gry przez sieć (zobacz [Gry](#gry)).

Nie ma kreatora pierwszego uruchomienia. Domyślne konto do SSH:

| Użytkownik | Hasło |
|---|---|
| `gracz` | `gracz` |

Przy pierwszym logowaniu przez SSH (`ssh gracz@arkada20`) trzeba ustawić nowe hasło. Konto `root` nie ma logowania hasłem, używaj `sudo` z konta `gracz`.

## Gry

Wrzuć gry do katalogu ich systemu. Z Windowsa albo Linuksa użyj udziału sieciowego `\\arkada20\roms` (w Linuksie też `smb://arkada20.local/roms`; jeśli nazwa nie działa, użyj adresu IP z RetroArch: **Information → Network Information**) albo skopiuj je przez SSH do `/home/roms/<system>/`.

Z Linuksa hasło nie jest potrzebne (wybierz „Anonimowo”, gdy menedżer plików zapyta). Windows 11 blokuje taki dostęp gościa, tam zaloguj się jako `gracz` z hasłem `gracz`. To hasło sieciowe jest osobne od hasła SSH, zmienisz je poleceniem `sudo smbpasswd gracz`.

Inne udziały sieciowe (są też wewnątrz `roms`): `\\arkada20\bios` (pliki BIOS), `\\arkada20\zapisy` (zapisy gier i stany, przydatne do kopii zapasowych) i `\\arkada20\zrzuty` (zrzuty ekranu z RetroArch).

| Katalog | System | Emulator (rdzeń) |
|---|---|---|
| `nes` | NES / Famicom (Pegasus) | FCEUmm |
| `snes` | Super Nintendo | Snes9x 2010 |
| `gb` | Game Boy, Game Boy Color | Gambatte |
| `gba` | Game Boy Advance | gpSP |
| `megadrive` | Mega Drive / Genesis, 32X | PicoDrive |
| `mastersystem` | Master System | PicoDrive |
| `gamegear` | Game Gear | Genesis Plus GX |
| `psx` | PlayStation (`.cue`, `.chd`, `.pbp`, `.m3u`) | PCSX ReARMed |
| `mame2003` | automaty, zestaw ROM MAME 2003-Plus | MAME 2003-Plus |
| `fbneo` | automaty, zestaw ROM FBNeo | FBNeo |
| `bios` | pliki BIOS (np. dla PlayStation) | |

Każdy katalog z grami dostaje w menu własną ikonę (listę gier), a listy odświeżają się same, gdy zmienią się pliki. Gry z automatów zachowują krótkie nazwy ROM-ów (np. `sf2`). Zestawy ROM-ów do automatów muszą pasować do wersji emulatora: MAME 2003-Plus i FBNeo potrzebują różnych zestawów.

Obraz nie zawiera gier. Używaj tylko gier, do których masz prawo.

## Sterowanie

- Menu w trakcie gry: **Start + Select** na padzie.
- Pady ustawiają się same dla większości znanych modeli (profile padów RetroArch). Nieznany pad: **Settings → Input → Port 1 Controls → Set All Controls**, potem **Save Controller Profile**.
- Wyłączanie konsoli z menu: **Main Menu → Zamknij system** albo **Restart**. Wyłączaj ją w ten sposób zamiast wyciągać zasilanie, żeby nie uszkodzić karty SD.

## Wygląd menu

Arkada20 domyślnie używa menu **XMB**. RetroArch ma cztery style menu, zmienia się je w **Settings → User Interface → Menu**, potem trzeba uruchomić RetroArch ponownie:

| Menu | Wygląd | Najlepsze do |
|---|---|---|
| **XMB** (domyślne) | poziomy rząd ikon z pionowymi listami, jak w PlayStation 3 i PSP; klasyczny wygląd Lakki | pad, joystick |
| **Ozone** | nowoczesne, lista konsol po lewej, gry po prawej | pad, joystick; polecany zamiennik XMB |
| **Material UI** (`glui`) | w stylu Androida, duże pozycje, zakładki | ekran dotykowy |
| **RGUI** | proste, retro, bardzo lekkie | wolne systemy, małe ekrany |

Wszystkie cztery działają z padem. Klawiatura ekranowa ma wszystkie klawisze specjalne (Backspace, Enter, Shift) w każdym menu.

## Ekran dotykowy (eksperymentalny)

Dotyk w menu jest **domyślnie wyłączony**. Układ dotyku ekranów LeMakera (FocalTech FT5x06) zgłasza „duchy”, czyli dodatkowe dotknięcia, których nie było, a przy dwóch punktach dotyku menu RetroArch potrafi się zaciąć. Żeby mimo to spróbować: **Settings → User Interface → Touch Support** (po polsku: *Ustawienia → Interfejs użytkownika → Obsługa dotyku*, ustawienie `menu_pointer_enable`). Zmiana działa od razu. Dotyk najlepiej działa w Material UI i Ozone; XMB jest zrobione pod pad (stuknięcie tylko przesuwa zaznaczenie).

## Ekran

Ekran wybierasz w `/boot/armbianEnv.txt` (przez SSH: `sudo nano /boot/armbianEnv.txt`, potem restart):

| Linia | Ekran |
|---|---|
| `overlays=lemaker-lcd5` | 5" RGB (konsolka), także razem z HDMI |
| `overlays=lemaker-lcd7` | 7" LVDS bez HDMI |
| `overlays=lemaker-lcd7-hdmi` | 7" LVDS razem z monitorem HDMI |

Jeśli podłączony jest też monitor HDMI, dopisz `extraargs=video=HDMI-A-1:1920x1080@60`, inaczej LCD miga. Nakładki można też włączyć w `sudo armbian-config`.

## Budowanie obrazu

Na komputerze z Linuksem x86 i Dockerem (wymagania: [../armbian-build/README.pl.md](../armbian-build/README.pl.md#wymagania-komputer-na-którym-budujesz)), z głównego katalogu repozytorium:

```bash
arkada20/zbuduj-rdzenie.sh       # emulatory (rdzenie libretro) dla A20, kompilacja krzyżowa
arkada20/zbuduj-retroarch.sh     # RetroArch z poprawkami z arkada20/latki-retroarch/
armbian-build/zbuduj-obraz-pr.sh --pulpit brak --ekran 7 --konsola
```

Obraz to `~/armbian-build/output/images/Arkada20_<data>_bananapipro_trixie_<jądro>.img`. `--gry KATALOG` dodaje gry z `KATALOG/<system>/` na własny użytek; nigdy nie publikuj obrazu z grami.

### Czym różni się od zwykłego RetroArch

RetroArch 1.20.0 jest kompilowany ze źródeł (bez X11, obraz przez KMS i OpenGL ES na sterowniku `lima` dla Mali-400, wejście przez udev, Wi-Fi przez NetworkManager) z tymi poprawkami:

| Poprawka | Co naprawia |
|---|---|
| 0001 | dotyk: puszczenie wskaźnika po zdjęciu ostatniego palca |
| 0002 | dotyk: przekazywanie pozycji i wciśnięcia wskaźnika (zbędne `break` zwracało 0) |
| 0003 | KMS: rozmiar ekranu i DPI, potrzebne do przeciągania i gestów przesunięcia |
| 0005 | menu: Restart i Wyłącz na Linuksie, nie tylko w Lakce |
| 0006 | polski napis „Zamknij system” dla wyłączania |
| 0007 | dotyk: pomijanie emulacji pojedynczego dotyku z jądra na ekranach wielodotykowych |

Debianowe czcionki menu (Roboto) nie mają symboli klawiatury ekranowej, więc obraz podmienia je na DejaVu Sans.

### Licencje

RetroArch i kilka emulatorów jest na licencji GPL: udostępniając zbudowany obraz, udostępnij też źródła (skrypty budujące pobierają konkretne wersje, wypisane w `/usr/lib/arm-linux-gnueabihf/libretro/WERSJE-konsola.txt` i `/usr/local/share/retroarch-konsola-wersja.txt`). MAME 2003-Plus, FBNeo, Genesis Plus GX i Snes9x 2010 mają licencje niekomercyjne: wolno je rozpowszechniać za darmo, ale obrazu ani urządzenia z nimi nie wolno sprzedawać.

### Pliki w tym katalogu

| Plik | Co to jest |
|---|---|
| `customize-konsola.sh` | uruchamiany wewnątrz obrazu przy budowaniu: pakiety, RetroArch, emulatory, konta, Samba, ustawienia |
| `retroarch.cfg` | ustawienia RetroArch w obrazie (tylko wartości inne niż domyślne) |
| `retroarch-konsola.service` | uruchamia RetroArch na ekranie przy starcie |
| `konsola-listy`, `konsola-listy.service`, `.path` | tworzy listy gier (jedna ikona na system) i odświeża je, gdy zmienią się pliki |
| `avahi-samba.service` | ogłasza udziały sieciowe w sieci lokalnej (`arkada20.local`) |
| `autoconfig/udev/` | dodatkowe profile padów |
| `zbuduj-rdzenie.sh` | kompiluje krzyżowo emulatory do `rdzenie/` |
| `zbuduj-retroarch.sh` | kompiluje krzyżowo RetroArch z poprawkami do `retroarch-bin/` |
| `latki-retroarch/` | poprawki RetroArch (zgłoszone twórcom jako [#20060](https://github.com/libretro/RetroArch/issues/20060) i [#20061](https://github.com/libretro/RetroArch/issues/20061)) |
| `logo/` | logo i jego generator |

`rdzenie/` i `retroarch-bin/` to wyniki budowania, nie ma ich w git.

## Logo

`logo/` zawiera logo Arkada20 (SVG i PNG, z tłem i bez, oraz kwadratową ikonę). Tworzy je skrypt `logo/generuj-logo.py`: litery są rysowane z pikseli, więc logo nie zależy od zainstalowanych czcionek.
