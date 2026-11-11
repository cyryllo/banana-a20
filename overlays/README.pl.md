[English](README.md) | **Polski**

# Ekrany LCD LeMaker: szczegóły techniczne

Jak ekrany LCD LeMakera działają na jądrze mainline, jak powstały nakładki i jak je ręcznie zainstalować lub zmienić. Zwykłe użycie opisuje [główne README](../README.pl.md#ekrany-lcd-lemaker).

## Pliki

| Plik | Ekran | Złącze | Rozdzielczość | Sterownik ekranu w jądrze |
|---|---|---|---|---|
| `bananapro-lemaker-lcd35.dts` | 3,5" BL035-RGB-002 | RGB | 320x240 | `lemaker,bl035-rgb-002` (panel-simple) |
| `bananapro-lemaker-lcd5.dts` | 5" | RGB | 800x480 | `panel-dpi`, timingi w nakładce |
| `bananapro-lemaker-lcd7.dts` | 7" | LVDS | 1024x600 | `panel-lvds`, `vesa-24` |
| `bananapro-lemaker-lcd7-hdmi.dts` | 7" do pracy z HDMI | LVDS | 1024x600 | jak wyżej, 42,429 MHz |
| `bananapro-disable-hdmi.dts` | wyłącza HDMI | | | |

To źródła nakładek `lemaker-lcd...`, które są teraz w Armbianie (`sun7i-a20-lemaker-lcd5/lcd7/lcd7-hdmi`, [armbian/build#11296](https://github.com/armbian/build/pull/11296)). Nakładka 3,5" jest tylko tutaj i nigdy nie była sprawdzona (brak sprzętu). Naraz może działać tylko jedna nakładka ekranu (wszystkie korzystają z TCON0, tych samych pinów i tego samego adresu dotyku).

## Jak to działa

- **Obraz:** wszystkie ekrany korzystają z TCON0 (`&tcon0_out`, endpoint 0), zasilanie matrycy na PH12, podświetlenie przez PWM0 (PB2), włącznik podświetlenia PH8.
- **7" LVDS:** TCON w A20 przełącza się w tryb LVDS tylko wtedy, gdy ekran ma `compatible = "panel-lvds"` (`vesa-24`, 55 MHz, 1024x600; `lcd7-hdmi`: 42,429 MHz).
- **5" RGB:** ogólny `panel-dpi` z timingami w nakładce (29,7 MHz, 800x480; w pliku fex było 30 MHz).
- **3,5" RGB:** `lemaker,bl035-rgb-002` z `panel-simple` w jądrze, bez timingów w nakładce.
- **Dotyk:** FocalTech FT5x06 na I2C3 (PI0/PI1, adres 0x38, przerwanie PH9), rozpoznawany jako `generic ft5x06 (79)`. Pin `ctp_wakeup` z fex (PH7) to linia RESET aktywna stanem niskim, stąd `reset-gpios = <&pio 7 7 1>` (sterownik czeka wtedy 300 ms na układ). Przy starcie pierwsza transmisja I2C do układu zawsze kończy się błędem magistrali (`mv64xxx ... Ctlr Error status 0x0`), sterownik I2C odzyskuje magistralę i zwraca -EAGAIN. Na to nie pomaga ani zasilanie układu z PH12 (`vcc-supply`), ani trzymanie PH7 w stanie wysokim od wczesnego startu (`gpio-hog`). Mała poprawka jądra sprawia, że `edt-ft5x06` ponawia rozpoznanie raz (`identification failed, retrying` w `dmesg`), przyjęta do Armbiana jako [armbian/build#11294](https://github.com/armbian/build/pull/11294). Bez niej sterownik trzeba podłączyć ponownie ręcznie: `echo 2-0038 | sudo tee /sys/bus/i2c/drivers/edt_ft5x06/bind`.
- **Zasilanie dotyku:** układ dotyku jest zasilany z linii panelu PH12, więc węzeł dotyku ma `vcc-supply` wskazujące regulator panelu. Bez tego sterownik panelu wyłącza PH12 przy wygaszaniu ekranu (DPMS), układ traci zasilanie (`Unable to fetch data, error: -6`) i dotyk nie może obudzić ekranu. Z `vcc-supply` sterownik dotyku trzyma PH12 włączone, gasną tylko obraz i podświetlenie.
- **LCD + HDMI:** wyjścia nie mają wspólnych pinów, ale w `ccu-sun4i-a10.c` zegary `tcon0-ch0-sclk`, `tcon1-ch1-sclk2` i `hdmi` mają te same źródła (najpierw PLL3 `pll-video0`) i flagę `CLK_SET_RATE_PARENT`. Przy starcie z HDMI najpierw LCD ustawia PLL3 dla siebie, potem HDMI przestawia go na 297 MHz, a dzielnik LCD zostaje stary, więc zegar pikseli LCD wychodzi zły (`clk_rate_exclusive_get` w `sun4i_tcon.c` blokuje częstotliwość dopiero przy włączaniu kanału, czyli za późno). Rozwiązanie: zegar LCD wyprowadzony z tych samych 297 MHz. 5": 29,7 MHz = 297 / 10 (`sun4i_tcon_dclk` bierze pierwszy dokładny dzielnik, od 4 w górę, dla 29,7 MHz to 10); 7" LVDS ma stały dzielnik 7, więc 42,429 MHz × 7 = 297,003 MHz, co `ccu_mult` zaokrągla w dół do 297 MHz. HDMI używa 297 MHz tylko w trybach 1080p i 720p. Czystszym rozwiązaniem na przyszłość byłoby przypięcie TCON0 na stałe do `pll-video1`.
- **Przełączanie ekranów w starszych obrazach (do v0.5):** U-Boot pomija linie zaczynające się od `#` w `armbianEnv.txt`; `lemaker-lcd` trzyma jedną aktywną linię `user_overlays=` i nie rusza nakładek innych niż LeMaker.

## Przeliczanie timingów z fex na Device Tree

Parametry pochodzą z oryginalnych plików `fex` LeMakera (w [`stare jądro sunxi 3.4/`](../stare%20jądro%20sunxi%203.4/)).

- `hback-porch = lcd_hbp - lcd_hspw`, `vback-porch = lcd_vbp - lcd_vspw` (w fex back porch zawiera impuls synchronizacji)
- `vtotal = lcd_vt / 2` (fex trzyma podwojoną wartość)
- `hfront-porch = lcd_ht - lcd_x - lcd_hbp`, `vfront-porch = lcd_vt/2 - lcd_y - lcd_vbp`

| Ekran | Zegar pikseli | Poziomo (aktywne/front/back/sync) | Pionowo | Odświeżanie |
|---|---|---|---|---|
| 5" | 29,7 MHz | 800/40/48/40 | 480/13/3/29 | ok. 61 Hz |
| 7" | 55 MHz | 1024/170/50/100 | 600/15/10/10 | ok. 64 Hz |
| 3,5" | 7 MHz (panel-simple) | htotal 408 | vtotal 262 | |

Obliczenia dla każdego ekranu są w komentarzach plików nakładek.

## Ręczna instalacja na istniejącym Armbianie

Potrzebna tylko dla ekranu 3,5", dla jądra Armbiana bez obsługi LeMakera albo do sprawdzenia zmienionych nakładek. Wymaga Armbiana `current` (6.18) dla Banana Pro (`bananapipro`, DTB `sun7i-a20-bananapro.dtb`) i pakietu `device-tree-compiler`.

```bash
git clone https://github.com/cyryllo/banana-a20.git
cd banana-a20

# nakładki dla wszystkich ekranów + polecenie do przełączania
for f in overlays/bananapro-*.dts; do sudo armbian-add-overlay "$f"; done
sudo install -m 0755 armbian-build/lemaker-lcd /usr/local/sbin/
sudo lemaker-lcd 7        # Twój ekran; usuwa też pozostałe nakładki dodane wyżej

sudo reboot
```

**Sterownik dotyku:** starsze jądra Armbiana nie budują `edt-ft5x06` (`CONFIG_TOUCHSCREEN_EDT_FT5X06`, włączony przez [armbian/build#11293](https://github.com/armbian/build/pull/11293)). Zbuduj go jako moduł zewnętrzny:

```bash
sudo apt install build-essential linux-headers-current-sunxi
mkdir ~/ft5x06 && cd ~/ft5x06
wget https://raw.githubusercontent.com/torvalds/linux/v6.18/drivers/input/touchscreen/edt-ft5x06.c
echo 'obj-m += edt-ft5x06.o' > Makefile
make -C /lib/modules/$(uname -r)/build M=$PWD modules
sudo make -C /lib/modules/$(uname -r)/build M=$PWD modules_install
sudo depmod -a
```

Moduł trzeba zbudować ponownie po każdej aktualizacji jądra. Jeśli masz inną wersję jądra, zamień `v6.18` na swoją.

Sterownik bez poprawki zawodzi przy starcie (zobacz [Jak to działa](#jak-to-działa)). Albo nałóż poprawkę z tego repozytorium na `edt-ft5x06.c` przed `make`:

```bash
patch -p4 < ~/banana-a20/armbian-build/userpatches/kernel/archive/sunxi-6.18/edt-ft5x06-retry-identify-after-bus-recovery.patch
```

albo zainstaluj usługę, która po starcie ponownie podłącza sterownik:

```bash
sudo install -m 0755 armbian-build/lemaker-touch-retry /usr/local/sbin/
sudo install -m 0644 armbian-build/lemaker-touch-retry.service /etc/systemd/system/
sudo systemctl enable lemaker-touch-retry.service
```

## Zmiany w nakładce

Weź źródło z tego katalogu (te same ustawienia co `lemaker-lcd...`), zmień je, uruchom `sudo armbian-add-overlay <plik>.dts`, usuń wartość `lemaker-lcd...` z linii `overlays=` w `/boot/armbianEnv.txt` i zrestartuj płytkę. Typowe zmiany:

| Objaw | Zmiana w nakładce |
|---|---|
| podświetlenie działa odwrotnie (0 = najjaśniej) | `pwms = <&pwm 0 50000 0>;` → `... 1>;` |
| 5"/3,5": kolorowy szum | dopisz `pixelclk-active = <0>;` albo `<1>;` w `panel-timing` |
| dotyk odwrócony albo zamienione osie | dopisz `touchscreen-inverted-x;`, `touchscreen-inverted-y;` albo `touchscreen-swapped-x-y;` w `touchscreen@38` |

## Sprawdzanie nakładek bez płytki

```bash
# Źródła Device Tree z mainline (tylko potrzebne katalogi)
git clone --depth 1 --filter=blob:none --sparse https://github.com/torvalds/linux.git lnx
cd lnx && git sparse-checkout set --no-cone '/arch/arm/boot/dts/allwinner/' '/include/dt-bindings/'

# Bazowe DTB z symbolami (-@)
D=arch/arm/boot/dts/allwinner
cpp -nostdinc -I include -I $D -undef -x assembler-with-cpp $D/sun7i-a20-bananapro.dts > /tmp/bp.pre
dtc -@ -I dts -O dtb -o /tmp/bp.dtb /tmp/bp.pre

# Kompilacja i nałożenie nakładki (ostrzeżenia graph_port / graph_child_address są niegroźne)
dtc -@ -I dts -O dtb -o /tmp/lcd5.dtbo ../overlays/bananapro-lemaker-lcd5.dts
fdtoverlay -i /tmp/bp.dtb -o /tmp/bp_lcd5.dtb /tmp/lcd5.dtbo && echo OK
```

Nakładki nie używają `#include` ani makr, bo `armbian-add-overlay` kompiluje je samym `dtc -@`.

## Źródła

- Oryginalne repozytorium LeMakera: <https://github.com/LeMaker/fex_configuration>
- Nakładki w Armbianie: <https://docs.armbian.com/User-Guide_Armbian_overlays/>
- System budowania Armbiana: <https://docs.armbian.com/build-framework/getting-started/>
