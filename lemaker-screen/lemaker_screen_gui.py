#!/usr/bin/python3
"""lemaker-screen-gui: okienko do ustawien ekranow LeMaker (GTK 3).

Odczyt stanu i jasnosc dzialaja bez hasla (jasnosc przez logind). Zmiany w
/boot/armbianEnv.txt i reset dotyku ida przez pkexec (systemowe pytanie o haslo)
do polecenia lemaker-screen.
DLACZEGO GTK 3, a nie Qt: XFCE na plytce juz go ma, a Qt na A20 jest ciezki.
"""

import os
import subprocess
import sys

# CO: modul lemaker_screen obok tego pliku (zrodla) albo z pakietu .deb.
sys.path.insert(0, "/usr/share/lemaker-screen")
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import lemaker_screen as ls  # noqa: E402

import gi  # noqa: E402
gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

# CO: --lang=pl przy uruchomieniu okna wybiera polski (domyslnie angielski).
for _a in sys.argv[1:]:
    if _a.startswith("--lang="):
        ls.JEZYK = "pl" if _a.split("=", 1)[1].startswith("pl") else "en"
PL = ls.JEZYK == "pl"
T = {
    "title": ("LeMaker screen", "Ekran LeMaker"),
    "screen": ("Screen", "Ekran"),
    "apply": ("Apply", "Zastosuj"),
    "reboot_needed": ("Configured: {}. The screen changes after a reboot.",
                      "Ustawiony: {}. Ekran zmieni się po ponownym uruchomieniu."),
    "ok_active": ("Working now: {}", "Działa teraz: {}"),
    "brightness": ("Brightness", "Jasność"),
    "no_backlight": ("No LCD is working now, so there is no brightness to set.",
                     "Teraz nie działa żaden ekran LCD, więc nie ma czego rozjaśniać."),
    "touch": ("Touch", "Dotyk"),
    "touch_ok": ("works", "działa"),
    "touch_none": ("not found", "nie znaleziono"),
    "touch_reset": ("Reset", "Resetuj"),
    "touch_hint": ("Use it when touch reacts on its own or does not react.",
                   "Użyj, gdy dotyk sam klika albo przestaje reagować."),
    "hdmi": ("HDMI monitor", "Monitor HDMI"),
    "hdmi_on": ("connected", "podłączony"),
    "hdmi_off": ("not connected", "niepodłączony"),
    "hdmi_1080p": ("Force HDMI 1920x1080 (needed when the LCD and HDMI work together)",
                   "Wymuś HDMI 1920x1080 (potrzebne, gdy LCD i HDMI działają razem)"),
    "reboot_q": ("The new screen setting works after a reboot. Reboot now?",
                 "Nowe ustawienie ekranu zadziała po ponownym uruchomieniu. Uruchomić ponownie teraz?"),
    "error": ("Error", "Błąd"),
    "no_overlays": ("This Armbian has no LeMaker overlays yet. Update the system (sudo apt update && sudo apt full-upgrade).",
                    "Ten Armbian nie ma jeszcze nakładek LeMaker. Zaktualizuj system (sudo apt update && sudo apt full-upgrade)."),
    "close": ("Close", "Zamknij"),
}


def tr(k, *a):
    s = T[k][1 if PL else 0]
    return s.format(*a) if a else s


def polecenie_root(*arg):
    """CO: polecenie lemaker-screen jako root przez pkexec. Zwraca (ok, tekst)."""
    cli = "/usr/bin/lemaker-screen"
    if not os.path.exists(cli):   # uruchomione z katalogu zrodel
        cli = os.path.join(os.path.dirname(os.path.realpath(__file__)), "lemaker_screen.py")
    p = subprocess.run(["pkexec", cli, *arg, f"--lang={ls.JEZYK}"], capture_output=True, text=True)
    # 126/127 = uzytkownik anulowal okno hasla
    if p.returncode in (126, 127):
        return False, None
    return p.returncode == 0, (p.stdout + p.stderr).strip()


class Okno(Gtk.Window):
    """CO: zwarte okno: siatka, jedna linia na kazda rzecz.
    DLACZEGO lista rozwijana i podpowiedzi zamiast ramek i opisow: okno ma sie
    miescic na ekranie 5" (800x480) bez przewijania."""

    def __init__(self):
        super().__init__(title=tr("title"))
        self.set_icon_name("lemaker-screen")
        self.set_resizable(False)
        self.zmiana_jasnosci = None
        siatka = Gtk.Grid(column_spacing=10, row_spacing=8)
        siatka.set_border_width(10)
        self.add(siatka)

        self.model = Gtk.Label(xalign=0)
        siatka.attach(self.model, 0, 0, 3, 1)

        # ---- ekran: lista + Zastosuj, pod spodem stan
        siatka.attach(self.etykieta(tr("screen")), 0, 1, 1, 1)
        self.lista = Gtk.ComboBoxText()
        for klucz in ls.EKRANY:
            self.lista.append(klucz, ls.opis_ekranu(klucz))
        siatka.attach(self.lista, 1, 1, 1, 1)
        zastosuj = Gtk.Button(label=tr("apply"))
        zastosuj.connect("clicked", self.zastosuj_ekran)
        siatka.attach(zastosuj, 2, 1, 1, 1)
        self.stan_ekranu = Gtk.Label(xalign=0)
        self.stan_ekranu.set_line_wrap(True)
        self.stan_ekranu.set_max_width_chars(48)
        siatka.attach(self.stan_ekranu, 1, 2, 2, 1)

        # ---- jasnosc
        siatka.attach(self.etykieta(tr("brightness")), 0, 3, 1, 1)
        self.suwak = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 5)
        self.suwak.set_value_pos(Gtk.PositionType.RIGHT)
        self.suwak.set_hexpand(True)
        self.suwak.connect("value-changed", self.przesunieto)
        self.brak_bl = Gtk.Label(label=tr("no_backlight"), xalign=0)
        self.brak_bl.set_line_wrap(True)
        self.brak_bl.set_max_width_chars(48)
        pole = Gtk.Box()
        pole.pack_start(self.suwak, True, True, 0)
        pole.pack_start(self.brak_bl, True, True, 0)
        siatka.attach(pole, 1, 3, 2, 1)

        # ---- dotyk
        siatka.attach(self.etykieta(tr("touch")), 0, 4, 1, 1)
        self.stan_dotyku = Gtk.Label(xalign=0)
        siatka.attach(self.stan_dotyku, 1, 4, 1, 1)
        self.przycisk_dotyku = Gtk.Button(label=tr("touch_reset"))
        self.przycisk_dotyku.set_tooltip_text(tr("touch_hint"))
        self.przycisk_dotyku.connect("clicked", self.reset_dotyku)
        siatka.attach(self.przycisk_dotyku, 2, 4, 1, 1)

        # ---- HDMI
        siatka.attach(self.etykieta("HDMI"), 0, 5, 1, 1)
        self.stan_hdmi = Gtk.Label(xalign=0)
        siatka.attach(self.stan_hdmi, 1, 5, 1, 1)
        self.hdmi_1080p = Gtk.CheckButton(label="1920x1080")
        self.hdmi_1080p.set_tooltip_text(tr("hdmi_1080p"))
        self.hdmi_1080p_id = self.hdmi_1080p.connect("toggled", self.przelacz_1080p)
        siatka.attach(self.hdmi_1080p, 2, 5, 1, 1)

        zamknij = Gtk.Button(label=tr("close"))
        zamknij.set_halign(Gtk.Align.END)
        zamknij.connect("clicked", lambda *_: self.destroy())
        siatka.attach(zamknij, 0, 6, 3, 1)

        self.odswiez()

    @staticmethod
    def etykieta(tekst):
        l = Gtk.Label(xalign=0)
        l.set_markup(f"<b>{GLib.markup_escape_text(tekst)}</b>")
        return l

    def komunikat(self, typ, tekst, pytanie=False):
        d = Gtk.MessageDialog(transient_for=self, modal=True, message_type=typ,
                              buttons=Gtk.ButtonsType.YES_NO if pytanie else Gtk.ButtonsType.OK,
                              text=tekst)
        odp = d.run()
        d.destroy()
        return odp == Gtk.ResponseType.YES

    def odswiez(self):
        try:
            s = ls.stan()
        except ls.Blad as e:
            self.komunikat(Gtk.MessageType.ERROR, str(e))
            return
        self.model.set_markup(f"<small>{GLib.markup_escape_text(s['model'])}</small>")
        self.lista.set_active_id(s["ustawiony"])
        if s["ustawiony"] != s["dziala"]:
            self.stan_ekranu.set_markup("<small><b>" + GLib.markup_escape_text(
                tr("reboot_needed", ls.opis_ekranu(s["ustawiony"]))) + "</b></small>")
        else:
            self.stan_ekranu.set_markup("<small>" + GLib.markup_escape_text(
                tr("ok_active", ls.opis_ekranu(s["dziala"]))) + "</small>")
        if not s["nakladki"]:
            self.stan_ekranu.set_text(tr("no_overlays"))
        jest_bl = s["jasnosc"] is not None
        self.suwak.set_visible(jest_bl)
        self.suwak.set_no_show_all(not jest_bl)
        self.brak_bl.set_visible(not jest_bl)
        self.brak_bl.set_no_show_all(jest_bl)
        if jest_bl:
            self.suwak.set_value(s["jasnosc"])
        self.stan_dotyku.set_text(tr("touch_ok") if s["dotyk"] else tr("touch_none"))
        self.przycisk_dotyku.set_sensitive(bool(s["dotyk"]))
        self.stan_hdmi.set_text(tr("hdmi_on") if s["hdmi"] else tr("hdmi_off"))
        with self.hdmi_1080p.handler_block(self.hdmi_1080p_id):
            self.hdmi_1080p.set_active(s["hdmi_1080p"])

    def zastosuj_ekran(self, _):
        wybrany = self.lista.get_active_id()
        ok, tekst = polecenie_root("set", wybrany)
        if tekst is None:
            return
        if not ok:
            self.komunikat(Gtk.MessageType.ERROR, tekst)
        elif "lemaker-screen.bak" in tekst and self.komunikat(Gtk.MessageType.QUESTION, tr("reboot_q"), pytanie=True):
            subprocess.run(["systemctl", "reboot"])
        self.odswiez()

    def przesunieto(self, suwak):
        # DLACZEGO z opoznieniem: suwak wysyla dziesiatki zdarzen na sekunde,
        # a kazde to wywolanie logind; wystarczy ostatnia wartosc.
        if self.zmiana_jasnosci:
            GLib.source_remove(self.zmiana_jasnosci)
        self.zmiana_jasnosci = GLib.timeout_add(150, self.ustaw_jasnosc)

    def ustaw_jasnosc(self):
        self.zmiana_jasnosci = None
        try:
            ls.ustaw_jasnosc(self.suwak.get_value())
        except (ls.Blad, subprocess.CalledProcessError) as e:
            self.komunikat(Gtk.MessageType.ERROR, str(e))
        return False

    def reset_dotyku(self, _):
        ok, tekst = polecenie_root("touch-reset")
        if tekst is not None and not ok:
            self.komunikat(Gtk.MessageType.ERROR, tekst)
        self.odswiez()

    def przelacz_1080p(self, przycisk):
        ok, tekst = polecenie_root("hdmi-1080p", "on" if przycisk.get_active() else "off")
        if tekst is not None and not ok:
            self.komunikat(Gtk.MessageType.ERROR, tekst)
        self.odswiez()


def main():
    okno = Okno()
    okno.connect("destroy", Gtk.main_quit)
    okno.show_all()
    Gtk.main()


if __name__ == "__main__":
    main()
