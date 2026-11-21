#!/usr/bin/python3
"""test-bananapipro-gui: okno do skryptu test-bananapipro.sh (GTK 3).

Okno uruchamia skrypt przez pkexec w trybie --maszynowo i czyta jego linie:
  MODUL|nazwa                 zaczyna sie modul
  WYNIK|STATUS|obszar|test|opis   wynik jednego testu
  INFO|tekst                  komunikat
  PYTANIE|tekst               czeka na odpowiedz t / n / p
  CZEKAJ|tekst                czeka na potwierdzenie (dowolna linia)
  KONIEC|raport|szczegoly|pass|fail|warn|skip
Odpowiedzi idą na standardowe wejscie skryptu.
DLACZEGO GTK 3: jest na obrazach XFCE (Debian i Ubuntu) i w LXQt, a Qt na A20 jest ciezki.
"""

import os
import shutil
import subprocess
import sys
import threading

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk  # noqa: E402

TU = os.path.dirname(os.path.realpath(__file__))
SKRYPT = next((p for p in (os.path.join(TU, "test-bananapipro.sh"),
                           "/usr/share/test-bananapipro/test-bananapipro.sh") if os.path.exists(p)), None)
STAN_EKRANOW = "/var/lib/test-bananapipro/ekrany"

KOLORY = {"PASS": "#2e7d32", "FAIL": "#c62828", "WARN": "#ef6c00", "SKIP": "#757575"}
NAZWY = {"PASS": "OK", "FAIL": "BŁĄD", "WARN": "UWAGA", "SKIP": "pominięty"}

CSS = b"""
.duzy { font-size: 120%; padding: 10px 18px; min-height: 40px; }
.pytanie { font-size: 115%; }
.ramka-pytania { background-color: alpha(@theme_selected_bg_color, 0.15); border-radius: 6px; padding: 8px; }
"""


class Okno(Gtk.Window):
    """CO: dwa widoki w Gtk.Stack: wybor testow i przebieg.
    DLACZEGO dwa widoki zamiast jednego: okno ma sie miescic na ekranie 5" (800x480)."""

    def __init__(self):
        super().__init__(title="Test Banana Pi Pro")
        self.set_default_size(800, 460)
        self.set_icon_name("utilities-system-monitor")
        self.proces = None
        self.przerwij = False
        self.raport = None
        self.moduly = self.lista_modulow()

        self.stos = Gtk.Stack(transition_type=Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self.add(self.stos)
        self.stos.add_named(self.widok_wyboru(), "wybor")
        self.stos.add_named(self.widok_przebiegu(), "przebieg")

    # ------------------------------------------------------------ wybor testow
    @staticmethod
    def lista_modulow():
        if not SKRYPT:
            return []
        w = subprocess.run(["bash", SKRYPT, "--lista"], capture_output=True, text=True)
        # CO: nazwa|opis|wymagany; starsza wersja skryptu nie ma trzeciego pola.
        return [(l.split("|") + ["0"])[:3] for l in w.stdout.splitlines() if "|" in l]

    def widok_wyboru(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, border_width=10)
        tytul = Gtk.Label(xalign=0)
        tytul.set_markup("<b>Test obrazu Armbian na Banana Pi Pro</b>  "
                         "<small>raport po angielsku trafi do katalogu domowego</small>")
        box.pack_start(tytul, False, False, 0)
        if not SKRYPT:
            box.pack_start(Gtk.Label(label="Nie znaleziono test-bananapipro.sh obok tego programu."), True, True, 0)
            return box

        siatka = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=2,
                             column_spacing=12, row_spacing=2, homogeneous=True)
        self.pola = {}
        for nazwa, opis, _wym in self.moduly:
            p = Gtk.CheckButton(active=True)
            l = Gtk.Label(xalign=0)
            l.set_markup(f"<b>{GLib.markup_escape_text(nazwa)}</b>  <small>{GLib.markup_escape_text(opis)}</small>")
            l.set_line_wrap(True)
            l.set_max_width_chars(42)
            p.add(l)
            self.pola[nazwa] = p
            siatka.add(p)
        przewijanie = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        przewijanie.add(siatka)
        box.pack_start(przewijanie, True, True, 0)

        rzad = Gtk.Box(spacing=8)
        for etykieta, stan in (("Wszystkie", True), ("Żadne", False)):
            b = Gtk.Button(label=etykieta)
            b.connect("clicked", lambda _b, s=stan: [p.set_active(s) for p in self.pola.values()])
            rzad.pack_start(b, False, False, 0)
        wymagane = Gtk.Button(label="Wymagane (Armbian)")
        wymagane.set_tooltip_text("Zaznacza tylko testy z listy kontrolnej wydania Armbiana i włącza "
                                  "\"Bez pytań\": system, SD, SATA, USB, Ethernet, Wi-Fi, sieć, HDMI, dźwięk, "
                                  "obciążenie, pakiety. Ekran LCD i GPIO testujesz osobno.")
        wymagane.connect("clicked", self.zaznacz_wymagane)
        rzad.pack_start(wymagane, False, False, 0)
        self.bez_pytan = Gtk.CheckButton(label="Bez pytań (tylko automatyczne)")
        rzad.pack_start(self.bez_pytan, False, False, 8)
        box.pack_start(rzad, False, False, 0)

        przyciski = Gtk.Box(spacing=8)
        start = Gtk.Button(label="Start testu")
        start.get_style_context().add_class("duzy")
        start.get_style_context().add_class("suggested-action")
        start.connect("clicked", self.start_testu)
        przyciski.pack_end(start, False, False, 0)

        ekrany = Gtk.Button(label="Kontynuuj test ekranów" if os.path.isdir(STAN_EKRANOW) else "Test ekranów LCD")
        ekrany.set_tooltip_text("7\", 7\" z HDMI, 5\", bez LCD: skrypt ustawia kolejne ekrany i restartuje płytkę. "
                                "Po każdym restarcie otwórz to okno i kliknij Kontynuuj.")
        ekrany.get_style_context().add_class("duzy")
        ekrany.connect("clicked", lambda _b: self.uruchom(["--ekrany"]))
        przyciski.pack_end(ekrany, False, False, 0)

        przygotuj = Gtk.Button(label="Przygotuj")
        przygotuj.set_tooltip_text("Instaluje narzędzia (gpiod, i2c-tools, alsa-utils, iw) i włącza nakładki pwm "
                                   "i spi-spidev do testów GPIO (z kopią armbianEnv.txt).")
        przygotuj.get_style_context().add_class("duzy")
        przygotuj.connect("clicked", lambda _b: self.uruchom(["--przygotuj"]))
        przyciski.pack_start(przygotuj, False, False, 0)
        box.pack_start(przyciski, False, False, 0)
        return box

    def zaznacz_wymagane(self, _):
        for nazwa, _opis, wym in self.moduly:
            self.pola[nazwa].set_active(wym == "1")
        self.bez_pytan.set_active(True)

    def start_testu(self, _):
        wybrane = [n for n, p in self.pola.items() if p.get_active()]
        if not wybrane:
            return
        # DLACZEGO --minimalny: raport dostaje wtedy dopisek "minimal, automatic checks only".
        wymagane = [n for n, _o, w in self.moduly if w == "1"]
        if sorted(wybrane) == sorted(wymagane) and self.bez_pytan.get_active():
            self.uruchom(["--minimalny"])
            return
        arg = []
        if len(wybrane) < len(self.pola):
            arg += ["--tylko", ",".join(wybrane)]
        if self.bez_pytan.get_active():
            arg.append("--bez-pytan")
        self.uruchom(arg)

    # ------------------------------------------------------------ przebieg
    def widok_przebiegu(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, border_width=8)
        self.etap = Gtk.Label(xalign=0)
        box.pack_start(self.etap, False, False, 0)

        # CO: lista wynikow: status, obszar, test, opis.
        self.wyniki = Gtk.ListStore(str, str, str, str)
        widok = Gtk.TreeView(model=self.wyniki, headers_visible=True)
        for i, naglowek in enumerate(("Wynik", "Obszar", "Test", "Szczegóły")):
            r = Gtk.CellRendererText()
            if i == 3:
                r.set_property("ellipsize", 3)  # Pango.EllipsizeMode.END
            kol = Gtk.TreeViewColumn(naglowek, r, markup=i)
            kol.set_resizable(True)
            if i == 3:
                kol.set_expand(True)
            widok.append_column(kol)
        widok.set_tooltip_column(3)
        self.widok_wynikow = widok
        przewijanie = Gtk.ScrolledWindow()
        przewijanie.add(widok)
        box.pack_start(przewijanie, True, True, 0)

        # CO: panel pytania (tak/nie/pomin) albo prosby (Gotowe), duze przyciski do dotyku.
        self.ramka = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.ramka.get_style_context().add_class("ramka-pytania")
        self.tresc = Gtk.Label(xalign=0, wrap=True)
        self.tresc.get_style_context().add_class("pytanie")
        self.ramka.pack_start(self.tresc, False, False, 0)
        self.przyciski_pytania = Gtk.Box(spacing=8, homogeneous=True)
        for etykieta, odp, klasa in (("Działa (tak)", "t", "suggested-action"),
                                     ("Nie działa", "n", "destructive-action"),
                                     ("Pomiń", "p", None)):
            b = Gtk.Button(label=etykieta)
            b.get_style_context().add_class("duzy")
            if klasa:
                b.get_style_context().add_class(klasa)
            b.connect("clicked", lambda _b, o=odp: self.odpowiedz(o))
            self.przyciski_pytania.pack_start(b, True, True, 0)
        self.ramka.pack_start(self.przyciski_pytania, False, False, 0)
        self.gotowe = Gtk.Button(label="Gotowe")
        self.gotowe.get_style_context().add_class("duzy")
        self.gotowe.get_style_context().add_class("suggested-action")
        self.gotowe.connect("clicked", lambda _b: self.odpowiedz(""))
        self.ramka.pack_start(self.gotowe, False, False, 0)
        box.pack_start(self.ramka, False, False, 0)

        dol = Gtk.Box(spacing=8)
        self.podsumowanie = Gtk.Label(xalign=0)
        dol.pack_start(self.podsumowanie, True, True, 0)
        self.b_przerwij = Gtk.Button(label="Przerwij pytania")
        self.b_przerwij.set_tooltip_text("Pomija wszystkie kolejne pytania; testy automatyczne idą do końca.")
        self.b_przerwij.connect("clicked", self.przerwij_pytania)
        dol.pack_end(self.b_przerwij, False, False, 0)
        self.b_kopiuj = Gtk.Button(label="Kopiuj raport")
        self.b_kopiuj.connect("clicked", self.kopiuj_raport)
        dol.pack_end(self.b_kopiuj, False, False, 0)
        self.b_otworz = Gtk.Button(label="Otwórz raport")
        self.b_otworz.connect("clicked", self.pokaz_raport)
        dol.pack_end(self.b_otworz, False, False, 0)
        self.b_wroc = Gtk.Button(label="Wróć")
        self.b_wroc.connect("clicked", lambda _b: self.stos.set_visible_child_name("wybor"))
        dol.pack_end(self.b_wroc, False, False, 0)
        box.pack_start(dol, False, False, 0)
        return box

    def pokaz_ramke(self, tekst, pytanie):
        self.tresc.set_text(tekst)
        self.przyciski_pytania.set_visible(pytanie)
        self.gotowe.set_visible(not pytanie)
        self.ramka.show()
        (self.przyciski_pytania.get_children()[0] if pytanie else self.gotowe).grab_focus()

    # ------------------------------------------------------------ proces
    def uruchom(self, arg):
        """CO: skrypt jako root przez pkexec, wyjscie czytane w osobnym watku."""
        if not shutil.which("pkexec"):
            self.komunikat("Brak pkexec. Uruchom w terminalu: sudo " + SKRYPT)
            return
        self.wyniki.clear()
        self.raport = None
        self.przerwij = False
        for b in (self.b_kopiuj, self.b_otworz, self.b_wroc):
            b.set_sensitive(False)
        self.b_przerwij.set_sensitive(True)
        self.ramka.hide()
        self.podsumowanie.set_text("")
        self.etap.set_markup("<i>Czekam na hasło administratora...</i>")
        self.stos.set_visible_child_name("przebieg")
        self.proces = subprocess.Popen(["pkexec", "/bin/bash", SKRYPT, "--maszynowo", *arg],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                       text=True, bufsize=1)
        threading.Thread(target=self.czytaj, daemon=True).start()

    def czytaj(self):
        for linia in self.proces.stdout:
            GLib.idle_add(self.linia, linia.rstrip("\n"))
        kod = self.proces.wait()
        GLib.idle_add(self.koniec_procesu, kod)

    def linia(self, linia):
        typ, _, reszta = linia.partition("|")
        if typ == "MODUL":
            self.etap.set_markup(f"Moduł: <b>{GLib.markup_escape_text(reszta)}</b>")
        elif typ == "INFO":
            self.etap.set_text(reszta)
        elif typ == "WYNIK":
            st, ob, te, op = (reszta.split("|", 3) + ["", "", "", ""])[:4]
            e = GLib.markup_escape_text
            it = self.wyniki.append([f'<span foreground="{KOLORY.get(st, "#000")}"><b>{NAZWY.get(st, st)}</b></span>',
                                     e(ob), e(te), e(op)])
            self.widok_wynikow.scroll_to_cell(self.wyniki.get_path(it), None, False, 0, 0)
        elif typ in ("PYTANIE", "CZEKAJ"):
            if self.przerwij:
                self.odpowiedz("p" if typ == "PYTANIE" else "")
            else:
                self.pokaz_ramke(reszta, typ == "PYTANIE")
        elif typ == "KONIEC":
            raport, _, p, f, w, s = (reszta.split("|") + [""] * 6)[:6]
            self.raport = raport
            self.podsumowanie.set_markup(
                f'<span foreground="{KOLORY["PASS"]}"><b>{p} OK</b></span>, '
                f'<span foreground="{KOLORY["FAIL"]}"><b>{f} błędów</b></span>, '
                f'<span foreground="{KOLORY["WARN"]}">{w} uwag</span>, {s} pominiętych')
            self.etap.set_text("Raport: " + raport)
        return False

    def odpowiedz(self, odp):
        self.ramka.hide()
        if self.proces and self.proces.poll() is None:
            try:
                self.proces.stdin.write(odp + "\n")
                self.proces.stdin.flush()
            except BrokenPipeError:
                pass

    def przerwij_pytania(self, _):
        self.przerwij = True
        if self.ramka.get_visible():
            self.odpowiedz("p" if self.przyciski_pytania.get_visible() else "")

    def koniec_procesu(self, kod):
        self.ramka.hide()
        self.b_przerwij.set_sensitive(False)
        self.b_wroc.set_sensitive(True)
        ma_raport = bool(self.raport) and os.path.exists(self.raport)
        self.b_kopiuj.set_sensitive(ma_raport)
        self.b_otworz.set_sensitive(ma_raport)
        # DLACZEGO 126/127 bez wynikow: pkexec anulowany albo brak okienka hasla w pulpicie.
        if kod in (126, 127) and len(self.wyniki) == 0:
            self.etap.set_text("Nie uruchomiono (anulowane hasło albo brak agenta polkit). W terminalu: sudo " + SKRYPT)
        return False

    def pokaz_raport(self, _):
        """CO: raport we wlasnym okienku (przewijany tekst).
        DLACZEGO nie xdg-open: na lekkich obrazach nie ma xdg-utils ani programu
        przypisanego do plikow .md; wlasne okienko dziala zawsze."""
        with open(self.raport) as f:
            tekst = f.read()
        d = Gtk.Dialog(title="Raport", transient_for=self, modal=True)
        d.set_default_size(760, 420)
        widok = Gtk.TextView(editable=False, monospace=True, wrap_mode=Gtk.WrapMode.WORD_CHAR)
        widok.get_buffer().set_text(tekst)
        przewijanie = Gtk.ScrolledWindow(vexpand=True)
        przewijanie.add(widok)
        d.get_content_area().pack_start(przewijanie, True, True, 0)
        d.add_button("W edytorze", 1)
        d.add_button("Kopiuj", 2)
        d.add_button("Zamknij", Gtk.ResponseType.CLOSE)
        d.show_all()
        while True:
            odp = d.run()
            if odp == 1:
                # CO: domyslny program dla pliku (przez GIO, bez xdg-open); gdy go nie ma, edytor tekstu.
                try:
                    Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(self.raport).get_uri(), None)
                except GLib.Error:
                    edytor = next((e for e in ("featherpad", "mousepad", "gedit", "kate", "xed", "pluma")
                                   if shutil.which(e)), None)
                    if edytor:
                        subprocess.Popen([edytor, self.raport])
                    else:
                        self.etap.set_text("Brak programu do otwarcia pliku: " + self.raport)
            elif odp == 2:
                self.kopiuj_raport(None)
            else:
                break
        d.destroy()

    def kopiuj_raport(self, _):
        with open(self.raport) as f:
            Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(f.read(), -1)
        self.etap.set_text("Raport skopiowany: wklej go na forum Armbiana albo w zgłoszeniu na GitHubie.")

    def komunikat(self, tekst):
        d = Gtk.MessageDialog(transient_for=self, modal=True, message_type=Gtk.MessageType.ERROR,
                              buttons=Gtk.ButtonsType.OK, text=tekst)
        d.run()
        d.destroy()


def main():
    dostawca = Gtk.CssProvider()
    dostawca.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), dostawca,
                                             Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    okno = Okno()
    okno.connect("destroy", Gtk.main_quit)
    okno.show_all()
    okno.ramka.hide()
    Gtk.main()


if __name__ == "__main__":
    main()
