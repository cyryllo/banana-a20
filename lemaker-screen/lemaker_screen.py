#!/usr/bin/python3
"""lemaker-screen: ustawienia ekranow LeMaker (3.5"/5"/7") na Banana Pi / Banana Pro
z Armbianem: wybor ekranu, jasnosc, reset dotyku. Polecenia w konsoli; okienko
(lemaker-screen-gui) korzysta z tych samych funkcji.

Uzycie (pomoc: lemaker-screen --help):
  lemaker-screen                     stan
  lemaker-screen set 5|7|7-hdmi|off  wybor ekranu (root, dziala po restarcie)
  lemaker-screen brightness [N|+N|-N] jasnosc w procentach
  lemaker-screen touch-reset         reset ukladu dotyku (root)
  lemaker-screen hdmi-1080p on|off   tryb HDMI 1080p dla LCD + HDMI (root)

DLACZEGO nakladki z Armbiana (overlays=), a nie wlasne: od listopada 2026
nakladki lemaker-lcd5/lcd7/lcd7-hdmi sa w oficjalnym Armbianie (#11296, #11337).
"""

import glob
import os
import re
import shutil
import subprocess
import sys

WERSJA = "1.0.1"
NAZWA = "lemaker-screen"

# CO: katalog glowny systemu; zmienny tylko do testow (LEMAKER_SCREEN_ROOT).
ROOT = os.environ.get("LEMAKER_SCREEN_ROOT", "/")
ENV = os.path.join(ROOT, "boot/armbianEnv.txt")
HDMI_1080P = "video=HDMI-A-1:1920x1080@60"

# CO: ekrany: klucz polecenia -> (nakladka, opis). Kolejnosc = kolejnosc w okienku.
# DLACZEGO 5" i 7"-hdmi z trybem 1080p: LCD i HDMI dziela zegar PLL3, wiec HDMI
# musi pracowac w 1080p albo 720p, inaczej LCD miga (zegary ekranow dobrane pod 297 MHz).
EKRANY = {
    "off": (None, {"en": "No LCD (HDMI only)", "pl": "Bez LCD (tylko HDMI)"}),
    "5": ("lemaker-lcd5", {"en": '5" RGB 800x480', "pl": '5" RGB 800x480'}),
    "7": ("lemaker-lcd7", {"en": '7" LVDS 1024x600, without HDMI (64 Hz)',
                           "pl": '7" LVDS 1024x600, bez HDMI (64 Hz)'}),
    "7-hdmi": ("lemaker-lcd7-hdmi", {"en": '7" LVDS 1024x600 together with HDMI (50 Hz)',
                                     "pl": '7" LVDS 1024x600 razem z HDMI (50 Hz)'}),
}
Z_HDMI_1080P = {"5", "7-hdmi"}

# CO: jezyk komunikatow: domyslnie angielski, polski na zyczenie
# (LEMAKER_SCREEN_LANG=pl albo --lang=pl).
# DLACZEGO nie z LANG: narzedzie jest dla uzytkownikow Armbiana z calego swiata,
# angielski ma byc zawsze, niezaleznie od jezyka systemu.
JEZYK = "pl" if os.environ.get("LEMAKER_SCREEN_LANG", "en").startswith("pl") else "en"

TEKSTY = {
    "screen": ("Screen", "Ekran"),
    "configured": ("configured", "ustawiony"),
    "active": ("active now", "działa teraz"),
    "reboot_needed": ("reboot needed to apply", "wymaga restartu"),
    "brightness": ("Brightness", "Jasność"),
    "no_backlight": ("no backlight (no LCD active)", "brak podświetlenia (LCD nie działa)"),
    "hdmi": ("HDMI monitor", "Monitor HDMI"),
    "connected": ("connected", "podłączony"),
    "not_connected": ("not connected", "niepodłączony"),
    "hdmi_mode": ("HDMI 1080p mode", "Tryb HDMI 1080p"),
    "on": ("on", "włączony"),
    "off": ("off", "wyłączony"),
    "touch": ("Touch", "Dotyk"),
    "works": ("works", "działa"),
    "missing": ("not found", "nie znaleziono"),
    "need_root": ("This needs administrator rights, run with sudo.", "To wymaga uprawnień administratora, uruchom przez sudo."),
    "no_overlays": ("This kernel has no LeMaker overlays (sun7i-a20-lemaker-lcd*.dtbo). Update Armbian: sudo apt update && sudo apt full-upgrade",
                    "To jądro nie ma nakładek LeMaker (sun7i-a20-lemaker-lcd*.dtbo). Zaktualizuj Armbiana: sudo apt update && sudo apt full-upgrade"),
    "not_banana": ("This board is not a Banana Pi / Banana Pro: {}. Use --force to continue anyway.",
                   "To nie jest Banana Pi / Banana Pro: {}. Użyj --force, żeby mimo to kontynuować."),
    "saved": ("Saved {} (backup: {}).", "Zapisano {} (kopia: {})."),
    "reboot_now": ("Reboot to apply: sudo reboot", "Uruchom ponownie, żeby zadziałało: sudo reboot"),
    "unchanged": ("Nothing to change.", "Nic do zmiany."),
    "touch_reset_ok": ("Touch controller reset: {}", "Zresetowano układ dotyku: {}"),
    "touch_none": ("No LeMaker touch controller found.", "Nie znaleziono układu dotyku LeMaker."),
    "bad_value": ("Wrong value: {}", "Zła wartość: {}"),
    "unknown_cmd": ("Unknown command: {}", "Nieznane polecenie: {}"),
    "brightness_set": ("Brightness: {}%", "Jasność: {}%"),
    "brightness_sudo": ("Without a password brightness changes only in the session on the board's screen. Here (e.g. over SSH) use: sudo lemaker-screen brightness {}",
                        "Bez hasła jasność zmienia się tylko w sesji na ekranie płytki. Tutaj (np. przez SSH) użyj: sudo lemaker-screen brightness {}"),
    "no_env": ("No {} found, is this Armbian?", "Brak {}, czy to Armbian?"),
}


def t(klucz, *arg):
    tekst = TEKSTY[klucz][1 if JEZYK == "pl" else 0]
    return tekst.format(*arg) if arg else tekst


class Blad(Exception):
    pass


# ---------------------------------------------------------------- odczyt stanu

def czytaj_env():
    try:
        with open(ENV) as f:
            return f.read().splitlines()
    except FileNotFoundError:
        raise Blad(t("no_env", ENV))


def wartosc(linie, klucz):
    for l in linie:
        if l.startswith(klucz + "="):
            return l.split("=", 1)[1].split()
    return []


def ekran_ustawiony(linie=None):
    """CO: ekran z /boot/armbianEnv.txt (klucz EKRANY) albo 'off'."""
    linie = linie if linie is not None else czytaj_env()
    for klucz, (nakladka, _) in EKRANY.items():
        if nakladka and nakladka in wartosc(linie, "overlays"):
            return klucz
    # DLACZEGO tez user_overlays: starsze obrazy banana-a20 i reczne nakladki
    # (np. bananapro-lemaker-lcd7, lemaker-lcd7-vcc) wlaczaja ekran tam.
    for n in wartosc(linie, "user_overlays"):
        for wzor, klucz in (("lcd7-hdmi", "7-hdmi"), ("lcd7", "7"), ("lcd5", "5")):
            if czy_nakladka_ekranu(n) and wzor in n:
                return klucz
    return "off"


def czy_nakladka_ekranu(nazwa):
    """CO: czy nakladka uzytkownika to ekran LeMaker (dowolny wariant nazwy)."""
    return "lemaker-lcd" in nazwa


def dt(sciezka):
    try:
        with open(os.path.join(ROOT, "proc/device-tree", sciezka), "rb") as f:
            return f.read().rstrip(b"\0").decode(errors="replace")
    except OSError:
        return None


def ekran_dzialajacy():
    """CO: ekran, ktory naprawde dziala teraz (z drzewa urzadzen jadra).
    DLACZEGO z drzewa, a nie z pliku: po zmianie pliku do restartu dziala stary."""
    zgodny = dt("lemaker-lcd-panel/compatible")
    if not zgodny:
        return "off"
    if "panel-lvds" in zgodny:
        # 42,429 MHz = wariant z HDMI; zapisane jako 4 bajty big-endian
        try:
            with open(os.path.join(ROOT, "proc/device-tree/lemaker-lcd-panel/panel-timing/clock-frequency"), "rb") as f:
                hz = int.from_bytes(f.read()[:4], "big")
            return "7-hdmi" if hz < 50_000_000 else "7"
        except OSError:
            return "7"
    return "5"


def model_plytki():
    return dt("model") or "?"


def nakladki_dostepne():
    wzor = os.path.join(ROOT, "boot/dtb*/overlay/sun7i-a20-lemaker-lcd7.dtbo")
    return bool(glob.glob(wzor))


def podswietlenie():
    for d in sorted(glob.glob(os.path.join(ROOT, "sys/class/backlight/*"))):
        return d
    return None


def jasnosc_procent():
    d = podswietlenie()
    if not d:
        return None
    teraz = int(open(os.path.join(d, "brightness")).read())
    maks = int(open(os.path.join(d, "max_brightness")).read()) or 1
    return round(teraz * 100 / maks)


def hdmi_podlaczone():
    for s in glob.glob(os.path.join(ROOT, "sys/class/drm/card*-HDMI-A-*/status")):
        if open(s).read().strip() == "connected":
            return True
    return False


def dotyk():
    """CO: nazwa urzadzenia I2C ukladu dotyku (np. 2-0038) albo None."""
    for d in glob.glob(os.path.join(ROOT, "sys/bus/i2c/drivers/edt_ft5x06/*-0038")):
        return os.path.basename(d)
    return None


def stan():
    linie = czytaj_env()
    return {
        "model": model_plytki(),
        "ustawiony": ekran_ustawiony(linie),
        "dziala": ekran_dzialajacy(),
        "jasnosc": jasnosc_procent(),
        "hdmi": hdmi_podlaczone(),
        "hdmi_1080p": HDMI_1080P in wartosc(linie, "extraargs"),
        "dotyk": dotyk(),
        "nakladki": nakladki_dostepne(),
    }


# ---------------------------------------------------------------- zmiany (root)

def wymagaj_roota():
    if os.geteuid() != 0 and ROOT == "/":
        raise Blad(t("need_root"))


def ustaw_klucz(linie, klucz, slowa):
    """CO: ustawia linie klucz=slowa; pusta lista usuwa linie."""
    nowe, jest = [], False
    for l in linie:
        if l.startswith(klucz + "="):
            if slowa and not jest:
                nowe.append(f"{klucz}={' '.join(slowa)}")
            jest = True
        else:
            nowe.append(l)
    if slowa and not jest:
        nowe.append(f"{klucz}={' '.join(slowa)}")
    return nowe


def zapisz_env(linie, stare):
    if linie == stare:
        return None
    kopia = ENV + ".lemaker-screen.bak"
    shutil.copy2(ENV, kopia)
    tymczasowy = ENV + ".tmp"
    with open(tymczasowy, "w") as f:
        f.write("\n".join(linie) + "\n")
    os.replace(tymczasowy, ENV)
    return kopia


def ustaw_ekran(klucz, wymus=False):
    """CO: wybiera ekran w /boot/armbianEnv.txt. Zwraca sciezke kopii albo None.
    DLACZEGO usuwamy tez user_overlays z "lemaker-lcd" w nazwie: obrazy z
    repozytorium banana-a20 sprzed 2026-11 (bananapro-lemaker-lcd*) i reczne
    nakladki wlaczaly ekran w ten sposob, a dwie nakladki ekranu naraz psuja
    start (wspolny TCON0, piny, adres dotyku)."""
    if klucz not in EKRANY:
        raise Blad(t("bad_value", klucz))
    wymagaj_roota()
    if not wymus and not re.search(r"Banana P", model_plytki()):
        raise Blad(t("not_banana", model_plytki()))
    if klucz != "off" and not nakladki_dostepne():
        raise Blad(t("no_overlays"))
    stare = czytaj_env()
    linie = list(stare)
    nakladki = [n for n in wartosc(linie, "overlays") if not n.startswith("lemaker-lcd")]
    if EKRANY[klucz][0]:
        nakladki.append(EKRANY[klucz][0])
    linie = ustaw_klucz(linie, "overlays", nakladki)
    uzytkownika = [n for n in wartosc(linie, "user_overlays") if not czy_nakladka_ekranu(n)]
    linie = ustaw_klucz(linie, "user_overlays", uzytkownika)
    if klucz in Z_HDMI_1080P:
        linie = ustaw_hdmi_1080p(linie, True)
    return zapisz_env(linie, stare)


def ustaw_hdmi_1080p(linie, wlacz):
    slowa = [s for s in wartosc(linie, "extraargs") if not s.startswith("video=HDMI-A-1:")]
    if wlacz:
        slowa.append(HDMI_1080P)
    return ustaw_klucz(linie, "extraargs", slowa)


def ustaw_hdmi_1080p_w_pliku(wlacz):
    wymagaj_roota()
    stare = czytaj_env()
    return zapisz_env(ustaw_hdmi_1080p(list(stare), wlacz), stare)


def ustaw_jasnosc(procent):
    """CO: jasnosc 0-100 %. Bez roota przez logind (sesja na tym komputerze).
    DLACZEGO logind: pozwala zwyklemu uzytkownikowi pulpitu zmieniac
    podswietlenie bez hasla; root pisze prosto do /sys."""
    d = podswietlenie()
    if not d:
        raise Blad(t("no_backlight"))
    procent = max(0, min(100, int(procent)))
    maks = int(open(os.path.join(d, "max_brightness")).read())
    wartosc_bl = round(procent * maks / 100)
    if os.geteuid() == 0 or ROOT != "/":
        with open(os.path.join(d, "brightness"), "w") as f:
            f.write(str(wartosc_bl))
    else:
        # DLACZEGO osobny komunikat: logind odmawia sesjom bez stanowiska (SSH)
        # tekstem "Your session has no seat", niezrozumialym dla uzytkownika.
        p = subprocess.run(["busctl", "call", "org.freedesktop.login1",
                            "/org/freedesktop/login1/session/auto", "org.freedesktop.login1.Session",
                            "SetBrightness", "ssu", "backlight", os.path.basename(d), str(wartosc_bl)],
                           capture_output=True, text=True)
        if p.returncode != 0:
            raise Blad(t("brightness_sudo", procent))
    return procent


def reset_dotyku():
    """CO: odpina i podpina sterownik dotyku; przy podpieciu uklad dostaje
    impuls RESET i kalibruje sie od nowa.
    DLACZEGO: po kilku godzinach uklad FT5x06 potrafi sie rozkalibrowac i przy
    jednym palcu zglaszac wiele falszywych punktow."""
    wymagaj_roota()
    n = dotyk()
    if not n:
        raise Blad(t("touch_none"))
    sterownik = os.path.join(ROOT, "sys/bus/i2c/drivers/edt_ft5x06")
    with open(os.path.join(sterownik, "unbind"), "w") as f:
        f.write(n)
    import time
    time.sleep(0.5)
    with open(os.path.join(sterownik, "bind"), "w") as f:
        f.write(n)
    return n


# ---------------------------------------------------------------- konsola

def opis_ekranu(klucz):
    return EKRANY[klucz][1][JEZYK]


def wypisz_stan():
    s = stan()
    print(f"{model_plytki()}")
    print(f"{t('screen')}: {opis_ekranu(s['ustawiony'])} ({t('configured')})")
    if s["dziala"] != s["ustawiony"]:
        print(f"  {t('active')}: {opis_ekranu(s['dziala'])}, {t('reboot_needed')}")
    j = s["jasnosc"]
    print(f"{t('brightness')}: {str(j) + '%' if j is not None else t('no_backlight')}")
    print(f"{t('touch')}: {t('works') + ' (' + s['dotyk'] + ')' if s['dotyk'] else t('missing')}")
    print(f"{t('hdmi')}: {t('connected') if s['hdmi'] else t('not_connected')}, "
          f"{t('hdmi_mode')}: {t('on') if s['hdmi_1080p'] else t('off')}")
    if not s["nakladki"]:
        print(t("no_overlays"))


POMOC = {
    "en": """lemaker-screen {w}: LeMaker LCD settings on the Banana Pi / Banana Pro (Armbian)

  lemaker-screen                       show the current settings
  lemaker-screen set 5|7|7-hdmi|off    choose the screen (sudo, applies after reboot)
                                       5       5" RGB, works with HDMI too
                                       7       7" LVDS without HDMI
                                       7-hdmi  7" LVDS together with an HDMI monitor
                                       off     no LCD, HDMI only
  lemaker-screen brightness [N|+N|-N]  brightness in percent, e.g. 60, +10, -10
  lemaker-screen touch-reset           reset the touch controller (sudo), when touch misbehaves
  lemaker-screen hdmi-1080p on|off     force HDMI 1920x1080 (needed for LCD + HDMI) (sudo)
  lemaker-screen-gui                   the same in a window

Options: --reboot (with set: reboot right away), --force (other board), --lang=en|pl, --version""",
    "pl": """lemaker-screen {w}: ustawienia ekranów LeMaker na Banana Pi / Banana Pro (Armbian)

  lemaker-screen                       pokaż obecne ustawienia
  lemaker-screen set 5|7|7-hdmi|off    wybór ekranu (sudo, działa po restarcie)
                                       5       5" RGB, działa też z HDMI
                                       7       7" LVDS bez HDMI
                                       7-hdmi  7" LVDS razem z monitorem HDMI
                                       off     bez LCD, tylko HDMI
  lemaker-screen brightness [N|+N|-N]  jasność w procentach, np. 60, +10, -10
  lemaker-screen touch-reset           reset układu dotyku (sudo), gdy dotyk wariuje
  lemaker-screen hdmi-1080p on|off     wymuszenie HDMI 1920x1080 (potrzebne przy LCD + HDMI) (sudo)
  lemaker-screen-gui                   to samo w okienku

Opcje: --reboot (z set: od razu restart), --force (inna płytka), --lang=pl|en, --version""",
}


def main(argv):
    global JEZYK
    # DLACZEGO --lang: okienko uruchamia zmiany przez pkexec, a pkexec czysci
    # zmienne srodowiska (LANG), wiec jezyk trzeba przekazac w poleceniu.
    for a in argv:
        if a.startswith("--lang="):
            JEZYK = "pl" if a.split("=", 1)[1].startswith("pl") else "en"
    opcje = {a for a in argv if a.startswith("--")}
    arg = [a for a in argv if not a.startswith("--")]
    if "--help" in opcje or "-h" in argv:
        print(POMOC[JEZYK].format(w=WERSJA))
        return 0
    if "--version" in opcje:
        print(f"{NAZWA} {WERSJA}")
        return 0
    try:
        if not arg or arg[0] in ("status", "stan"):
            wypisz_stan()
        elif arg[0] == "set" and len(arg) == 2:
            kopia = ustaw_ekran(arg[1], wymus="--force" in opcje)
            if kopia is None:
                print(t("unchanged"))
            else:
                print(t("saved", ENV, kopia))
                print(f"{t('screen')}: {opis_ekranu(arg[1])}")
                if "--reboot" in opcje:
                    subprocess.run(["systemctl", "reboot"])
                else:
                    print(t("reboot_now"))
        elif arg[0] == "brightness":
            if len(arg) == 1:
                j = jasnosc_procent()
                print(t("brightness_set", j) if j is not None else t("no_backlight"))
            else:
                w = arg[1]
                if not re.fullmatch(r"[+-]?\d{1,3}", w):
                    raise Blad(t("bad_value", w))
                teraz = jasnosc_procent() or 0
                nowa = teraz + int(w) if w[0] in "+-" else int(w)
                print(t("brightness_set", ustaw_jasnosc(nowa)))
        elif arg[0] == "touch-reset":
            print(t("touch_reset_ok", reset_dotyku()))
        elif arg[0] == "hdmi-1080p" and len(arg) == 2 and arg[1] in ("on", "off"):
            kopia = ustaw_hdmi_1080p_w_pliku(arg[1] == "on")
            print(t("unchanged") if kopia is None else t("saved", ENV, kopia) + "\n" + t("reboot_now"))
        else:
            print(t("unknown_cmd", " ".join(arg)), file=sys.stderr)
            print(POMOC[JEZYK].format(w=WERSJA), file=sys.stderr)
            return 2
    except Blad as e:
        print(e, file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as e:
        print((e.stderr or b"").decode().strip() or str(e), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
