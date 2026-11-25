#!/usr/bin/env python3
"""Armbian Watch: ikona w zasobniku, ktora co jakis czas sprawdza katalogi
plikow na serwerach, GitHuba (PR-y, zgloszenia, commity, wydania) i wersje
pakietow w repozytoriach apt, i daje znac, gdy cos sie zmieni. Powstala dla
opiekuna plytki w Armbianie (stad nazwa i szablony), ale obserwuje dowolne
projekty. Jezyk: polski albo angielski (ustawienia, domyslnie jezyk systemu).

Uzycie:
  armbian-watch                ikona w zasobniku (normalna praca)
  armbian-watch --once         jedno sprawdzenie w terminalu, bez ikony (test;
                               dziala tez stare --raz)
  armbian-watch --version      numer wersji

Ustawienia: ~/.config/armbian-watch/settings.json (tworzone przy pierwszym
starcie), stan: ~/.local/state/armbian-watch/state.json. Do wersji 1.2.0
program nazywal sie "Czujka Armbian" (czujka-armbian); jego pliki sa
przenoszone przy pierwszym starcie (przenies_stare_pliki).
"""

import base64
import gzip
import json
import os
import re
import shutil
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path

NAZWA = "armbian-watch"
TYTUL = "Armbian Watch"
WERSJA = "1.3.1"
KATALOG_USTAWIEN = Path.home() / ".config" / NAZWA
PLIK_USTAWIEN = KATALOG_USTAWIEN / "settings.json"
PLIK_STANU = Path.home() / ".local" / "state" / NAZWA / "state.json"
PLIK_AUTOSTARTU = Path.home() / ".config" / "autostart" / f"{NAZWA}.desktop"


# ---------------------------------------------------------------- jezyk
# CO: teksty w programie sa po polsku; t() zamienia je na angielskie, gdy
# wybrany jest angielski.
# DLACZEGO slownik w pliku, a nie gettext: program to jeden skrypt i ma tak
# zostac (pakiet bez plikow .mo); kolejny jezyk to kolejny slownik.

JEZYK = "pl"
JEZYKI = [("auto", "Automatycznie (język systemu)"), ("pl", "Polski"), ("en", "English")]

EN = {
    # jezyk
    "Automatycznie (język systemu)": "Automatic (system language)",
    # typy obserwacji i pola
    "Katalog na serwerze (np. obrazy do testu)": "Directory on a server (e.g. test images)",
    "Adres katalogu": "Directory address",
    "Obserwowane foldery\n(dokładne nazwy po przecinku,\nnp. bananapipro, orangepi5)":
        "Watched folders\n(exact names, comma separated,\ne.g. bananapipro, orangepi5)",
    "Pokazuj tylko obserwowane foldery\n(bez nowości z innych folderów)":
        "Show only watched folders\n(nothing new from other folders)",
    "Tylko pliki z końcówką\n(po przecinku, np. .img.xz;\npuste = wszystkie pliki)":
        "Only files ending with\n(comma separated, e.g. .img.xz;\nempty = all files)",
    "PR-y autora w repozytorium GitHub": "Author's pull requests in a GitHub repository",
    "Repozytorium (właściciel/nazwa)": "Repository (owner/name)",
    "Login GitHub autora": "Author's GitHub login",
    "Zgłoszenie albo PR na GitHubie": "Issue or pull request on GitHub",
    "Numer": "Number",
    "Nowe commity w gałęzi GitHub": "New commits in a GitHub branch",
    "Gałąź": "Branch",
    "Ścieżki plików lub katalogów\n(po jednej w wierszu)": "File or directory paths\n(one per line)",
    "Wydania repozytorium GitHub": "GitHub repository releases",
    "Tylko wydania z plikami płytki\n(nazwa płytki, np. bananapipro;\npuste = wszystkie wydania)":
        "Only releases with files for the board\n(board name, e.g. bananapipro;\nempty = all releases)",
    "Wersja pakietu w repozytorium apt": "Package version in an apt repository",
    "Adres pliku Packages.gz": "Packages.gz address",
    "Nazwa pakietu": "Package name",
    "nazwa": "name",
    "typ": "type",
    "Obserwowane foldery (zaznaczone „tylko obserwowane”)":
        "Watched folders (\"only watched\" is ticked)",
    # szablony
    "Obrazy do testu Armbian (opiekun płytki)": "Armbian test images (board maintainer)",
    "Obrazy do testu Armbian": "Armbian test images",
    "Moje PR-y w Armbian": "My Armbian pull requests",
    "Zgłoszenie": "Issue",
    "Commity w gałęzi wydania Armbian": "Commits in an Armbian release branch",
    "Gałąź wydania Armbian": "Armbian release branch",
    "Wydania": "Releases",
    "Wydania Armbian build": "Armbian build releases",
    "Obrazy społecznościowe Armbian dla płytki": "Armbian community images for a board",
    "Obrazy społecznościowe": "Community images",
    "Wersja jądra w apt Armbian": "Kernel version in Armbian apt",
    "Jądro w apt Armbian": "Kernel in Armbian apt",
    # sprawdzanie
    "limit zapytań GitHuba, kolejna próba po {godz} (token w ustawieniach daje 5000/h)":
        "GitHub request limit, next try after {godz} (a token in settings gives 5000/h)",
    "{nazwa}: uzupełnij w ustawieniach: {braki}": "{nazwa}: fill in the settings: {braki}",
    "{tag}: obrazy {filtr}: {ile}": "{tag}: {filtr} images: {ile}",
    " (testowe)": " (pre-release)",
    "otwarty": "open",
    "zamknięty": "closed",
    "scalony": "merged",
    "komentarze": "comments",
    "nowy obraz": "new image",
    "nowy plik": "new file",
    "nowy folder": "new folder",
    "nowe": "new",
    "nie ma pakietu {pakiet} w {url}": "no package {pakiet} in {url}",
    "Nowy obraz do testu!": "New test image!",
    "Nowe obrazy do testu: {ile}": "New test images: {ile}",
    "Armbian Watch: nowe zdarzenia: {ile}": "Armbian Watch: new events: {ile}",
    "…i jeszcze {ile}": "…and {ile} more",
    # tryb --raz
    "BŁĄD:": "ERROR:",
    "Zdarzeń: {z}, błędów: {b}, obserwacji w stanie: {o}, czas: {c:.1f} s":
        "Events: {z}, errors: {b}, watches in state: {o}, time: {c:.1f} s",
    # okno ustawien
    "Armbian Watch: ustawienia": "Armbian Watch: settings",
    "<b>Witaj!</b> Dodaj rzeczy do obserwowania (przycisk <i>Dodaj</i> w zakładce Obserwacje) "
    "i uzupełnij ich pola, np. swój login GitHub albo nazwę płytki. Armbian Watch sprawdza je "
    "zaraz po starcie i potem co ustawiony czas.":
        "<b>Welcome!</b> Add things to watch (the <i>Add</i> button on the Watches tab) and fill "
        "in their fields, e.g. your GitHub login or your board name. Armbian Watch checks them right "
        "after start and then at the set interval.",
    "Ogólne": "General",
    "Obserwacje": "Watches",
    "Sprawdzaj co": "Check every",
    "Token GitHub": "GitHub token",
    "opcjonalny, github_pat_...": "optional, github_pat_...",
    "Pokaż": "Show",
    "Bez tokenu GitHub pozwala na 60 zapytań na godzinę z jednego adresu IP (jedna obserwacja "
    "GitHuba = ok. 1 zapytanie na sprawdzenie). Token tworzysz na swoim koncie GitHub: Settings, "
    "Developer settings, Personal access tokens, Fine-grained tokens, dostęp <i>Public "
    "repositories</i>, bez żadnych uprawnień. Podnosi limit do 5000 na godzinę i nie daje dostępu "
    "do niczego na koncie. <a href='https://github.com/settings/personal-access-tokens/new'>"
    "Utwórz token</a>. Zapisywany jest w pliku ustawień dostępnym tylko dla Ciebie.":
        "Without a token GitHub allows 60 requests per hour from one IP address (one GitHub "
        "watch = about 1 request per check). Create a token on your GitHub account: Settings, "
        "Developer settings, Personal access tokens, Fine-grained tokens, access <i>Public "
        "repositories</i>, no permissions at all. It raises the limit to 5000 per hour and gives "
        "access to nothing on your account. <a href='https://github.com/settings/personal-access-"
        "tokens/new'>Create a token</a>. It is saved in a settings file only you can read.",
    "Uruchamiaj przy logowaniu": "Start at login",
    "Język": "Language",
    "Dodaj": "Add",
    "Usuń": "Remove",
    "Obserwacja": "Watch",
    "Wybierz obserwację z listy albo dodaj nową.": "Pick a watch from the list or add a new one.",
    "Rodzaj": "Kind",
    "Nazwa": "Name",
    "* pole wymagane": "* required field",
    "Obserwacja „{nazwa}”: uzupełnij: {braki}.": "Watch \"{nazwa}\": fill in: {braki}.",
    "Obserwacja „{nazwa}”: taka nazwa już jest, nazwy muszą się różnić.":
        "Watch \"{nazwa}\": this name is already used, names must differ.",
    # ikona, menu, okienko
    "jeszcze nie": "not yet",
    "Ostatnie sprawdzenie: {czas}": "Last check: {czas}",
    "Ostatnie sprawdzenie: {czas} · następne ok. {nast}": "Last check: {czas} · next about {nast}",
    "sprawdzam…": "checking…",
    "Pokaż zdarzenia": "Show events",
    "Sprawdź teraz": "Check now",
    "Otwórz: {nazwa}": "Open: {nazwa}",
    "Ustawienia…": "Settings…",
    "Uruchamiaj przy starcie": "Start with the desktop",
    "Zakończ": "Quit",
    "Nowe: {ile}": "New: {ile}",
    "Błędy: {ile}": "Errors: {ile}",
    "Nic nowego od uruchomienia.": "Nothing new since start.",
    "Kliknij wpis, aby otworzyć stronę.": "Click an entry to open its page.",
    "Wyczyść": "Clear",
    "Ustawienia": "Settings",
    "Zapisz": "Save",
    "Anuluj": "Cancel",
}


def t(tekst, **kw):
    """CO: tekst w wybranym jezyku; {pola} wypelnia z kw."""
    if JEZYK == "en":
        tekst = EN.get(tekst, tekst)
    return tekst.format(**kw) if kw else tekst


def ustaw_jezyk(wybor):
    global JEZYK
    if wybor in ("pl", "en"):
        JEZYK = wybor
        return
    loc = (os.environ.get("LC_ALL") or os.environ.get("LC_MESSAGES")
           or os.environ.get("LANG") or "")
    JEZYK = "pl" if loc.lower().startswith("pl") else "en"


# ---------------------------------------------------------------- ustawienia

def domyslne_ustawienia():
    """CO: ustawienia dla nowego uzytkownika: ogolne, bez niczyich danych.
    DLACZEGO tak skromnie: kazdy obserwuje swoje plytki, PR-y i zgloszenia; przy
    pierwszym starcie otwiera sie okno ustawien z szablonami do dodania.
    DLACZEGO funkcja: nazwy obserwacji w jezyku uzytkownika."""
    return {
        "co_ile_minut": 60,
        "github_token": "",
        "jezyk": "auto",
        "obserwacje": [
            {"typ": "katalog", "nazwa": t("Obrazy do testu Armbian"),
             "url": "https://fi.mirror.armbian.de/incoming/igorpecovnik/", "plytki": [],
             "tylko_wybrane": True, "koncowki": [".img.xz"]},
            {"typ": "github_wydania", "nazwa": t("Wydania Armbian build"), "repo": "armbian/build"},
        ],
    }


# CO: opis typow obserwacji dla okna ustawien: nazwa i pola (klucz, etykieta,
# rodzaj pola, wymagane). Etykiety po polsku; t() tlumaczy je przy wyswietleniu.
TYPY = {
    "katalog": ("Katalog na serwerze (np. obrazy do testu)", [
        ("url", "Adres katalogu", "tekst", True),
        ("plytki", "Obserwowane foldery\n(dokładne nazwy po przecinku,\nnp. bananapipro, orangepi5)", "przecinki", False),
        ("tylko_wybrane", "Pokazuj tylko obserwowane foldery\n(bez nowości z innych folderów)", "tak_nie", False),
        ("koncowki", "Tylko pliki z końcówką\n(po przecinku, np. .img.xz;\npuste = wszystkie pliki)", "przecinki", False)]),
    "github_pr_autora": ("PR-y autora w repozytorium GitHub", [
        ("repo", "Repozytorium (właściciel/nazwa)", "tekst", True),
        ("autor", "Login GitHub autora", "tekst", True)]),
    "github_zgloszenie": ("Zgłoszenie albo PR na GitHubie", [
        ("repo", "Repozytorium (właściciel/nazwa)", "tekst", True),
        ("numer", "Numer", "liczba", True)]),
    "github_commity": ("Nowe commity w gałęzi GitHub", [
        ("repo", "Repozytorium (właściciel/nazwa)", "tekst", True),
        ("galaz", "Gałąź", "tekst", True),
        ("sciezki", "Ścieżki plików lub katalogów\n(po jednej w wierszu)", "wiersze", True)]),
    "github_wydania": ("Wydania repozytorium GitHub", [
        ("repo", "Repozytorium (właściciel/nazwa)", "tekst", True),
        ("zasob_zawiera", "Tylko wydania z plikami płytki\n(nazwa płytki, np. bananapipro;\npuste = wszystkie wydania)", "tekst", False)]),
    "apt_pakiet": ("Wersja pakietu w repozytorium apt", [
        ("url", "Adres pliku Packages.gz", "tekst", True),
        ("pakiet", "Nazwa pakietu", "tekst", True)]),
}

# CO: gotowe szablony do przycisku "Dodaj" w oknie ustawien (nazwy przez t()).
SZABLONY = [
    ("Obrazy do testu Armbian (opiekun płytki)",
     {"typ": "katalog", "nazwa": "Obrazy do testu Armbian",
      "url": "https://fi.mirror.armbian.de/incoming/igorpecovnik/", "plytki": [],
      "tylko_wybrane": True, "koncowki": [".img.xz"]}),
    ("Moje PR-y w Armbian",
     {"typ": "github_pr_autora", "nazwa": "Moje PR-y w Armbian", "repo": "armbian/build", "autor": ""}),
    ("Zgłoszenie albo PR na GitHubie",
     {"typ": "github_zgloszenie", "nazwa": "Zgłoszenie", "repo": "", "numer": 0}),
    ("Commity w gałęzi wydania Armbian",
     {"typ": "github_commity", "nazwa": "Gałąź wydania Armbian", "repo": "armbian/build",
      "galaz": "", "sciezki": []}),
    ("Wydania repozytorium GitHub",
     {"typ": "github_wydania", "nazwa": "Wydania", "repo": ""}),
    ("Obrazy społecznościowe Armbian dla płytki",
     {"typ": "github_wydania", "nazwa": "Obrazy społecznościowe", "repo": "armbian/community",
      "zasob_zawiera": ""}),
    ("Wersja jądra w apt Armbian",
     {"typ": "apt_pakiet", "nazwa": "Jądro w apt Armbian",
      "url": "https://apt.armbian.com/dists/trixie/main/binary-armhf/Packages.gz",
      "pakiet": "linux-image-current-"}),
]


# ---------------------------------------------------------------- siec

def pobierz(url, token="", naglowki=None):
    """CO: pobiera adres i zwraca bajty.
    DLACZEGO ogolny User-Agent: nie wysylamy na zewnatrz danych uzytkownika."""
    zadanie = urllib.request.Request(url, headers={"User-Agent": NAZWA, **(naglowki or {})})
    if token and "api.github.com" in url:
        zadanie.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(zadanie, timeout=60) as odp:
        return odp.read()


# CO: czas (unix), do ktorego nie pytamy GitHuba, osobno dla wyszukiwania
# ("search") i reszty API ("core"), bo GitHub liczy je osobno.
# DLACZEGO: bez logowania GitHub daje 60 zapytan na godzine (wyszukiwanie 10 na
# minute); po przekroczeniu kolejne zapytania tylko zasmiecaja liste bledow.
github_przerwa_do = {"core": 0.0, "search": 0.0}


class LimitGitHuba(Exception):
    pass


def github(sciezka, token=""):
    zasob = "search" if sciezka.startswith("/search/") else "core"

    def limit():
        godz = datetime.fromtimestamp(github_przerwa_do[zasob]).strftime("%H:%M")
        return LimitGitHuba(t("limit zapytań GitHuba, kolejna próba po {godz} "
                              "(token w ustawieniach daje 5000/h)", godz=godz))
    if time.time() < github_przerwa_do[zasob]:
        raise limit()
    try:
        return json.loads(pobierz("https://api.github.com" + sciezka, token,
                                  {"Accept": "application/vnd.github+json"}))
    except urllib.error.HTTPError as e:
        if e.code in (403, 429) and e.headers.get("X-RateLimit-Remaining") == "0":
            reset = float(e.headers.get("X-RateLimit-Reset", time.time() + 3600))
            github_przerwa_do[zasob] = reset + 30
            raise limit() from e
        raise


# ------------------------------------------------- funkcje sprawdzajace
# Kazda zwraca slownik: klucz -> {"wartosc": ..., "tytul": ..., "url": ...}
# (opcjonalnie "pelny", "rodzaj", "wazne"). Nowy klucz albo zmieniona wartosc
# = zdarzenie. DLACZEGO "wartosc" zawsze po polsku: jest porownywana ze
# stanem, wiec zmiana jezyka nie moze jej zmienic; tlumaczy ja dopiero
# pokaz_wartosc().

def lista_katalogu(url):
    """CO: nazwy z listingu katalogu na serwerze (autoindex Apache/nginx)."""
    tekst = pobierz(url).decode("utf-8", "replace")
    nazwy = []
    for h in re.findall(r'href="([^"]+)"', tekst):
        h = urllib.parse.unquote(h)
        if h.startswith(("?", "/", "http", "#", "..")):
            continue
        nazwy.append(h)
    return nazwy


# CO: ile poziomow pod obserwowanym folderem zagladamy (np. bananapipro/archive/).
GLEBOKOSC_KATALOGU = 3

# CO: nazwa obrazu Armbiana, np.
# Armbian_26.11.3_Bananapipro_resolute_current_6.18.65_xfce_desktop.img.xz
# Armbian_community_26.11.0-trunk.137_Bananapipro_trixie_current_6.18.64_minimal.img.xz
WZOR_OBRAZU = re.compile(
    r"^Armbian(?:[-_](?:community|unofficial))?_(?P<wersja>\d[^_]*)_(?P<plytka>[^_]+)_(?P<wydanie>[^_]+)_(?P<galaz>[^_]+)_"
    r"(?P<jadro>\d[^_]*?)(?:_(?P<reszta>.+?))?\.img(?P<ext>\..+)?$", re.I)


def skroc_nazwe(sciezka):
    """CO: krotka nazwa wpisu do okienka i powiadomien oraz jego rodzaj.
    DLACZEGO: pelne nazwy obrazow maja ok. 70 znakow i w waskim okienku widac
    tylko ich poczatek; tu zostaje to, co je rozroznia:
    "Bananapipro 26.11.3 · resolute · current 6.18.65 · xfce desktop"."""
    folder = sciezka.endswith("/")
    nazwa = sciezka.rstrip("/").rsplit("/", 1)[-1]
    m = WZOR_OBRAZU.match(nazwa)
    if m and not folder:
        czesci = [f"{m['plytka']} {m['wersja']}", m["wydanie"], f"{m['galaz']} {m['jadro']}"]
        if m["reszta"]:
            czesci.append(m["reszta"].replace("_", " "))
        tekst = " · ".join(czesci)
        ext = (m["ext"] or "").lower()
        if ext in ("", ".xz"):
            return tekst, "obraz"
        return f"{tekst} ({ext.lstrip('.').removeprefix('xz.')})", "plik"
    return nazwa + ("/" if folder else ""), "folder" if folder else "plik"


def zawiera_czlon(tekst, wzorzec):
    """CO: czy wzorzec jest osobnym czlonem tekstu, bez wzgledu na wielkosc liter
    ("bananapipro" jest w Armbian_26.11.3_Bananapipro_..., "bananapi" nie)."""
    return re.search(rf"(?<![a-z0-9]){re.escape(wzorzec.lower())}(?![a-z0-9])", tekst.lower()) is not None


def pasuje_nazwa(nazwa, wzorce):
    """CO: czy wpis z listingu nalezy do obserwowanych nazw.
    DLACZEGO dokladnie, a nie "zawiera": "bananapi" nie moze lapac bananapipro,
    bananapif3 itd. Folder musi sie nazywac dokladnie tak; plik musi miec nazwe
    jako osobny czlon (Armbian_26.11.3_Bananapipro_... pasuje do bananapipro)."""
    czysta = nazwa.rstrip("/").lower()
    if nazwa.endswith("/"):
        return czysta in wzorce
    return any(zawiera_czlon(czysta, w) for w in wzorce)


def sprawdz_katalog(o, token):
    wynik = {}
    wzorce = [p.strip().rstrip("/").lower() for p in o.get("plytki", []) if p.strip()]
    tylko_wybrane = bool(o.get("tylko_wybrane"))
    koncowki = tuple(k.lower() for k in o.get("koncowki", []) if k)

    def dodaj(sciezka, url, wazne):
        # DLACZEGO filtr koncowek pomija tez foldery: przy ".img.xz" interesuja
        # nas tylko obrazy, nie same katalogi ani pliki .asc/.sha/.torrent.
        if koncowki and not sciezka.lower().endswith(koncowki):
            return
        krotka, rodzaj = skroc_nazwe(sciezka)
        wynik[sciezka] = {"wartosc": "jest", "tytul": krotka, "pelny": sciezka,
                          "rodzaj": rodzaj, "url": url, "wazne": wazne}

    def wglab(url, prefiks, poziom):
        for plik in lista_katalogu(url):
            adres = urllib.parse.urljoin(url, plik)
            dodaj(prefiks + plik, adres, True)
            if plik.endswith("/") and poziom < GLEBOKOSC_KATALOGU:
                wglab(adres, prefiks + plik, poziom + 1)

    for nazwa in lista_katalogu(o["url"]):
        url = urllib.parse.urljoin(o["url"], nazwa)
        nasza = pasuje_nazwa(nazwa, wzorce)
        if nasza or not tylko_wybrane:
            dodaj(nazwa, url, nasza)
        # DLACZEGO zagladamy glebiej tylko w obserwowane foldery: obraz do testu
        # to nowe pliki w katalogu plytki (tez w podkatalogach, np. archive/),
        # a reszta plytek nas nie dotyczy.
        if nasza and nazwa.endswith("/"):
            wglab(url, nazwa, 1)
    return wynik


def opis_pr(i):
    pr = i.get("pull_request") or {}
    if pr.get("merged_at"):
        return "scalony"
    return "zamkniety" if i["state"] == "closed" else "otwarty"


def sprawdz_pr_autora(o, token):
    q = urllib.parse.quote(f"repo:{o['repo']} author:{o['autor']} is:pr")
    dane = github(f"/search/issues?q={q}&sort=updated&per_page=30", token)
    wynik = {}
    for i in dane.get("items", []):
        wynik[f"#{i['number']}"] = {
            "wartosc": f"{opis_pr(i)}, komentarze: {i['comments']}",
            "tytul": f"#{i['number']} {i['title']}", "url": i["html_url"]}
    return wynik


def sprawdz_zgloszenie(o, token):
    i = github(f"/repos/{o['repo']}/issues/{o['numer']}", token)
    return {f"#{o['numer']}": {"wartosc": f"{opis_pr(i)}, komentarze: {i['comments']}",
                               "tytul": f"#{o['numer']} {i['title']}",
                               "pelny": f"{o['repo']}#{o['numer']} {i['title']}",
                               "url": i["html_url"]}}


def sprawdz_commity(o, token):
    wynik = {}
    for sciezka in o["sciezki"]:
        q = urllib.parse.urlencode({"sha": o["galaz"], "path": sciezka, "per_page": 10})
        try:
            dane = github(f"/repos/{o['repo']}/commits?{q}", token)
        except urllib.error.HTTPError as e:
            if e.code == 404:          # galezi jeszcze nie ma albo zostala usunieta
                continue
            raise
        for c in dane:
            wynik[c["sha"][:10]] = {"wartosc": "jest",
                                    "tytul": c["commit"]["message"].splitlines()[0],
                                    "pelny": f"{c['sha'][:10]} {c['commit']['message']}",
                                    "url": c["html_url"]}
    return wynik


def sprawdz_wydania(o, token):
    wynik = {}
    filtr = o.get("zasob_zawiera")
    for r in github(f"/repos/{o['repo']}/releases?per_page=5", token):
        if filtr:
            # DLACZEGO osobny czlon, a nie "zawiera": w armbian/community jest ok.
            # 950 plikow na wydanie i "Bananapi" lapaloby Bananapim3, Bananapim64...
            zasoby = [a["name"] for a in r.get("assets", []) if zawiera_czlon(a["name"], filtr)]
            if not zasoby:
                continue
            tytul = t("{tag}: obrazy {filtr}: {ile}", tag=r["tag_name"], filtr=filtr, ile=len(zasoby))
        else:
            tytul = f"{o['repo']} {r['tag_name']}" + (t(" (testowe)") if r.get("prerelease") else "")
        wynik[r["tag_name"]] = {"wartosc": "jest", "tytul": tytul, "url": r["html_url"]}
    return wynik


def wersja_klucz(w):
    """CO: klucz do porownania wersji typu 26.8.3 (liczby po kolei)."""
    return [int(x) if x.isdigit() else x for x in re.split(r"[.+~-]", w)]


def sprawdz_apt(o, token):
    tekst = gzip.decompress(pobierz(o["url"])).decode("utf-8", "replace")
    wersje = []
    for blok in tekst.split("\n\n"):
        if re.search(rf"^Package: {re.escape(o['pakiet'])}$", blok, re.M):
            m = re.search(r"^Version: (\S+)$", blok, re.M)
            if m:
                wersje.append(m.group(1))
    if not wersje:
        # DLACZEGO blad, a nie pusty wynik: przy literowce w nazwie pakietu
        # (albo niedokonczonej nazwie z szablonu) obserwacja milczalaby zawsze.
        raise ValueError(t("nie ma pakietu {pakiet} w {url}", pakiet=o["pakiet"], url=o["url"]))
    najnowsza = max(wersje, key=wersja_klucz)
    return {o["pakiet"]: {"wartosc": najnowsza, "tytul": f"{o['pakiet']} {najnowsza}",
                          "url": o["url"].rsplit("/dists/", 1)[0]}}


SPRAWDZACZE = {
    "katalog": sprawdz_katalog,
    "github_pr_autora": sprawdz_pr_autora,
    "github_zgloszenie": sprawdz_zgloszenie,
    "github_commity": sprawdz_commity,
    "github_wydania": sprawdz_wydania,
    "apt_pakiet": sprawdz_apt,
}


# ------------------------------------------------------ opis zdarzen

def pokaz_wartosc(w):
    """CO: wartosc ze stanu (zawsze po polsku, bez ogonkow) w jezyku uzytkownika."""
    slowa = {"otwarty": t("otwarty"), "zamkniety": t("zamknięty"), "scalony": t("scalony"),
             "komentarze": t("komentarze")}
    czesci = []
    for c in w.split(", "):
        k, sep, v = c.partition(": ")
        czesci.append(f"{slowa.get(k, k)}{sep}{v}")
    return ", ".join(czesci)


def opis_zmiany(stary, nowy):
    """CO: krotki opis zmiany: tylko to, co sie zmienilo, np. "komentarze: 1 → 2"."""
    a, b = stary.split(", "), nowy.split(", ")
    if len(a) == len(b):
        czesci = []
        for x, y in zip(a, b):
            if x == y:
                continue
            kx, sx, vx = x.partition(": ")
            ky, sy, vy = y.partition(": ")
            if sx and sy and kx == ky:
                czesci.append(f"{pokaz_wartosc(kx)}: {vx} → {vy}")
            else:
                czesci.append(f"{pokaz_wartosc(x)} → {pokaz_wartosc(y)}")
        if czesci:
            return ", ".join(czesci)
    return f"{pokaz_wartosc(stary)} → {pokaz_wartosc(nowy)}"


def opis_nowego(z):
    """CO: opis nowego wpisu (2. kolumna okienka): "nowy obraz", "nowe" itd."""
    return {"obraz": t("nowy obraz"), "plik": t("nowy plik"),
            "folder": t("nowy folder")}.get(z.get("rodzaj"), t("nowe"))


def tekst_zdarzenia(z):
    """CO: jedna linia o zdarzeniu (powiadomienie, tryb --raz)."""
    return z["tytul"] + (f" ({z['zmiana']})" if z["zmiana"] else "")


# ------------------------------------------------------ logika zdarzen

def wczytaj_json(plik, domyslne):
    try:
        return json.loads(plik.read_text())
    except (OSError, ValueError):
        return domyslne


def zapisz_json(plik, dane):
    plik.parent.mkdir(parents=True, exist_ok=True)
    tymczasowy = plik.with_suffix(".tmp")
    tymczasowy.write_text(json.dumps(dane, indent=2, ensure_ascii=False))
    tymczasowy.replace(plik)


def ustawienia_z_pliku():
    """CO: ustawienia dokladnie tak, jak sa w pliku (dla okna ustawien)."""
    if not PLIK_USTAWIEN.exists():
        zapisz_ustawienia(domyslne_ustawienia())
    u = wczytaj_json(PLIK_USTAWIEN, domyslne_ustawienia())
    u.setdefault("co_ile_minut", 60)
    u.setdefault("github_token", "")
    u.setdefault("jezyk", "auto")
    u.setdefault("obserwacje", [])
    return u


def zapisz_ustawienia(u):
    # DLACZEGO chmod 600: w pliku moze byc token GitHub.
    zapisz_json(PLIK_USTAWIEN, u)
    os.chmod(PLIK_USTAWIEN, 0o600)


def ustawienia():
    """CO: ustawienia do sprawdzania; token moze tez przyjsc ze zmiennej GITHUB_TOKEN."""
    u = ustawienia_z_pliku()
    if not u["github_token"]:
        u["github_token"] = os.environ.get("GITHUB_TOKEN", "")
    return u


def brakujace_pola(o):
    """CO: wymagane pola obserwacji, ktore sa puste (do okna i do sprawdzania)."""
    if o.get("typ") not in TYPY:
        return [t("typ")]
    braki = [] if str(o.get("nazwa", "")).strip() else [t("nazwa")]
    for klucz, etykieta, rodzaj, wymagane in TYPY[o["typ"]][1]:
        w = o.get(klucz)
        if wymagane and (not w or (rodzaj == "liczba" and int(w) <= 0)):
            braki.append(t(etykieta).split("\n")[0])
    if o["typ"] == "katalog" and o.get("tylko_wybrane") and not o.get("plytki"):
        braki.append(t("Obserwowane foldery (zaznaczone „tylko obserwowane”)"))
    return braki


def sprawdz_wszystko():
    """CO: jedna runda sprawdzen. Zwraca (zdarzenia, bledy).
    DLACZEGO pierwsza runda danej obserwacji jest cicha: przy pierwszym starcie
    wszystko byloby "nowe" i zasypaloby powiadomieniami."""
    u = ustawienia()
    stan = wczytaj_json(PLIK_STANU, {})
    # CO: odcisk ustawien kazdej obserwacji z ostatniej udanej rundy.
    # DLACZEGO: po zmianie ustawien (np. nowy folder albo filtr koncowek)
    # wszystko, co juz lezy na serwerze, wygladaloby na "nowe"; wtedy runda
    # jest cicha, tak jak pierwsza.
    odciski = stan.setdefault("_odciski", {})
    zdarzenia, bledy = [], []
    czas = datetime.now().strftime("%Y-%m-%d %H:%M")
    for o in u["obserwacje"]:
        klucz_obs = f"{o['typ']}|{o.get('nazwa', '')}"
        funkcja = SPRAWDZACZE.get(o["typ"])
        braki = brakujace_pola(o)
        if not funkcja or braki:
            bledy.append(t("{nazwa}: uzupełnij w ustawieniach: {braki}",
                           nazwa=o.get("nazwa"), braki=", ".join(braki)))
            continue
        try:
            teraz = funkcja(o, u["github_token"])
        except LimitGitHuba as e:
            # DLACZEGO jeden wpis: przy limicie obserwacje GitHuba padaja z tego
            # samego powodu.
            if str(e) not in bledy:
                bledy.append(str(e))
            continue
        except Exception as e:  # siec, zmiana strony
            bledy.append(f"{o.get('nazwa')}: {e}")
            continue
        poprzednio = stan.get(klucz_obs)
        odcisk = json.dumps({k: v for k, v in o.items() if k != "nazwa"},
                            sort_keys=True, ensure_ascii=False)
        zmienione = klucz_obs in odciski and odciski[klucz_obs] != odcisk
        odciski[klucz_obs] = odcisk
        if poprzednio is not None and zmienione:
            poprzednio.update(teraz)
        elif poprzednio is not None:
            for k, v in teraz.items():
                stary = poprzednio.get(k)
                if stary is not None and stary.get("wartosc") == v["wartosc"]:
                    continue
                zdarzenia.append({
                    "obserwacja": o["nazwa"], "typ": o["typ"], "tytul": v["tytul"],
                    "pelny": v.get("pelny", v["tytul"]), "rodzaj": v.get("rodzaj"),
                    "zmiana": "" if stary is None else opis_zmiany(stary.get("wartosc", ""), v["wartosc"]),
                    "url": v["url"], "wazne": v.get("wazne", False), "czas": czas})
            # DLACZEGO laczymy ze starym stanem: wpis, ktory chwilowo zniknal z
            # listy (np. stronicowanie GitHuba), nie wroci potem jako "nowy".
            poprzednio.update(teraz)
            stan[klucz_obs] = poprzednio
        else:
            stan[klucz_obs] = teraz
    zapisz_json(PLIK_STANU, stan)
    return zdarzenia, bledy


# ------------------------------------------------------ autostart

def ustaw_autostart(wlacz):
    if wlacz:
        # DLACZEGO dwa warianty: z pakietu .deb program jest w /usr/bin, a uruchomiony
        # z katalogu zrodel trzeba wywolac pelna sciezka.
        sciezka = Path(__file__).resolve()
        polecenie = NAZWA if str(sciezka).startswith("/usr/bin/") else f"{sys.executable} {sciezka}"
        PLIK_AUTOSTARTU.parent.mkdir(parents=True, exist_ok=True)
        PLIK_AUTOSTARTU.write_text(
            f"[Desktop Entry]\nType=Application\nName={TYTUL}\n"
            f"Exec={polecenie}\n"
            f"Icon={NAZWA}\nX-GNOME-Autostart-enabled=true\n")
    elif PLIK_AUTOSTARTU.exists():
        PLIK_AUTOSTARTU.unlink()


# CO: pliki z czasow, gdy program nazywal sie "Czujka Armbian" (do 1.2.0).
STARA_NAZWA = "czujka-armbian"
STARE_PLIKI = [
    (Path.home() / ".config" / STARA_NAZWA / "ustawienia.json", PLIK_USTAWIEN),
    (Path.home() / ".local" / "state" / STARA_NAZWA / "stan.json", PLIK_STANU),
]
STARY_AUTOSTART = Path.home() / ".config" / "autostart" / f"{STARA_NAZWA}.desktop"


def przenies_stare_pliki():
    """CO: przenosi ustawienia, stan i autostart ze starej nazwy do nowej.
    DLACZEGO: po zmianie nazwy nie moze zginac zadna obserwacja ani token, a
    bez starego stanu kazda obserwacja zaczelaby od nowa (cicha pierwsza
    runda przegapilaby to, co doszlo w miedzyczasie)."""
    for stary, nowy in STARE_PLIKI:
        if stary.exists() and not nowy.exists():
            nowy.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(stary), str(nowy))
            for smiec in stary.parent.glob("*.tmp"):
                smiec.unlink()
            try:
                stary.parent.rmdir()
            except OSError:
                pass        # zostaly tam inne pliki uzytkownika: nie ruszamy
    if STARY_AUTOSTART.exists():
        STARY_AUTOSTART.unlink()
        ustaw_autostart(True)


# ------------------------------------------------------ ikony

# CO: kolory ikony: szare kolko = nic nowego, czerwone = nowe zdarzenia.
KOLOR_SPOKOJ = "#8c8c8c"
KOLOR_NOWE = "#e53935"
KOLOR_ARMBIAN = "#f60f00"   # czerwony trojkat z logo Armbiana

# CO: znak "A" z logo Armbiana (odwrocone V ze scietym czubkiem i czerwonym
# trojkatem w srodku), odrysowany z logo w ukladzie ok. 220 x 185.
# DLACZEGO wektor, a nie obrazek: ostry przy kazdym rozmiarze zasobnika.
ZNAK_A = [(88, 10), (148, 10), (228, 195), (176, 195), (116, 54), (56, 195), (8, 195)]
TROJKAT_A = [(88, 141), (145, 141), (116, 187)]


def rysuj_ikone(stan):
    """CO: ikona do zasobnika: "spokoj" (szare kolko z A), "nowe" (czerwone
    kolko z A) albo "obraz" (pingwin Armbiana: nowy obraz do testu)."""
    from PyQt6.QtCore import QPointF, Qt
    from PyQt6.QtGui import QColor, QIcon, QPainter, QPixmap, QPolygonF

    if stan == "obraz":
        pix = QPixmap()
        pix.loadFromData(base64.b64decode(PINGWIN_PNG))
        return QIcon(pix)
    ikona = QIcon()
    for rozmiar in (16, 22, 24, 32, 48, 64, 128):
        pix = QPixmap(rozmiar, rozmiar)
        pix.fill(Qt.GlobalColor.transparent)
        p = QPainter(pix)
        p.setRenderHint(QPainter.RenderHint.Antialiasing)
        p.setPen(Qt.PenStyle.NoPen)
        p.setBrush(QColor(KOLOR_NOWE if stan == "nowe" else KOLOR_SPOKOJ))
        m = rozmiar / 64
        p.drawEllipse(QPointF(32 * m, 32 * m), 31 * m, 31 * m)
        # DLACZEGO te liczby: znak ma ok. 60% szerokosci kolka, srodek nieco
        # nizej (optycznie, bo A jest u gory waskie).
        s = 38 / 220 * m

        def wielokat(punkty):
            return QPolygonF([QPointF(32 * m + (x - 118) * s, 33 * m + (y - 102) * s)
                              for x, y in punkty])
        p.setBrush(QColor("white"))
        p.drawPolygon(wielokat(ZNAK_A))
        p.setBrush(QColor("white" if stan == "nowe" else KOLOR_ARMBIAN))
        p.drawPolygon(wielokat(TROJKAT_A))
        p.end()
        ikona.addPixmap(pix)
    return ikona


# ------------------------------------------------------ okno ustawien

def okno_ustawien_klasa():
    """CO: klasa okna ustawien (Qt importowane dopiero tu, bo --raz dziala bez Qt)."""
    import copy
    from PyQt6.QtGui import QIntValidator
    from PyQt6.QtWidgets import (QCheckBox, QComboBox, QDialog, QDialogButtonBox, QFormLayout,
                                 QGroupBox, QHBoxLayout, QLabel, QLineEdit, QListWidget, QMenu,
                                 QMessageBox, QPlainTextEdit, QPushButton, QSpinBox, QTabWidget,
                                 QVBoxLayout, QWidget)

    class OknoUstawien(QDialog):
        def __init__(self, po_zapisie, powitanie=False):
            super().__init__()
            self.setWindowTitle(t("Armbian Watch: ustawienia"))
            self.setWindowIcon(rysuj_ikone("spokoj"))
            self.resize(780, 560)
            self.po_zapisie = po_zapisie
            self.u = ustawienia_z_pliku()
            self.obs = copy.deepcopy(self.u["obserwacje"])
            uklad = QVBoxLayout(self)
            if powitanie:
                l = QLabel(t("<b>Witaj!</b> Dodaj rzeczy do obserwowania (przycisk <i>Dodaj</i> "
                             "w zakładce Obserwacje) i uzupełnij ich pola, np. swój login GitHub "
                             "albo nazwę płytki. Armbian Watch sprawdza je zaraz po starcie i "
                             "potem co ustawiony czas."))
                l.setWordWrap(True)
                uklad.addWidget(l)
            zakladki = QTabWidget()
            uklad.addWidget(zakladki)
            zakladki.addTab(self.zakladka_ogolne(), t("Ogólne"))
            zakladki.addTab(self.zakladka_obserwacje(), t("Obserwacje"))
            if powitanie:
                zakladki.setCurrentIndex(1)
            przyciski = QDialogButtonBox(QDialogButtonBox.StandardButton.Save
                                         | QDialogButtonBox.StandardButton.Cancel)
            # DLACZEGO wlasne napisy: Qt bez zaladowanych tlumaczen pokazuje
            # standardowe przyciski zawsze po angielsku.
            przyciski.button(QDialogButtonBox.StandardButton.Save).setText(t("Zapisz"))
            przyciski.button(QDialogButtonBox.StandardButton.Cancel).setText(t("Anuluj"))
            przyciski.accepted.connect(self.zapisz)
            przyciski.rejected.connect(self.reject)
            uklad.addWidget(przyciski)

        # -------------------------------------------------- zakladka Ogolne
        def zakladka_ogolne(self):
            w = QWidget()
            f = QFormLayout(w)
            self.jezyk = QComboBox()
            for kod, opis in JEZYKI:
                self.jezyk.addItem(t(opis), kod)
            self.jezyk.setCurrentIndex(max(0, self.jezyk.findData(self.u.get("jezyk", "auto"))))
            f.addRow(t("Język") + (" / Language" if JEZYK == "pl" else " / Język"), self.jezyk)
            self.minuty = QSpinBox()
            self.minuty.setRange(15, 1440)
            self.minuty.setSingleStep(15)
            self.minuty.setSuffix(" min")
            self.minuty.setValue(int(self.u.get("co_ile_minut", 60)))
            f.addRow(t("Sprawdzaj co"), self.minuty)
            self.token = QLineEdit(self.u.get("github_token", ""))
            self.token.setEchoMode(QLineEdit.EchoMode.Password)
            self.token.setPlaceholderText(t("opcjonalny, github_pat_..."))
            pokaz = QCheckBox(t("Pokaż"))
            pokaz.toggled.connect(lambda v: self.token.setEchoMode(
                QLineEdit.EchoMode.Normal if v else QLineEdit.EchoMode.Password))
            wiersz = QHBoxLayout()
            wiersz.addWidget(self.token)
            wiersz.addWidget(pokaz)
            f.addRow(t("Token GitHub"), wiersz)
            opis = QLabel(t(
                "Bez tokenu GitHub pozwala na 60 zapytań na godzinę z jednego adresu IP (jedna "
                "obserwacja GitHuba = ok. 1 zapytanie na sprawdzenie). Token tworzysz na swoim "
                "koncie GitHub: Settings, Developer settings, Personal access tokens, Fine-grained "
                "tokens, dostęp <i>Public repositories</i>, bez żadnych uprawnień. Podnosi limit do "
                "5000 na godzinę i nie daje dostępu do niczego na koncie. <a href='https://github."
                "com/settings/personal-access-tokens/new'>Utwórz token</a>. Zapisywany jest w pliku "
                "ustawień dostępnym tylko dla Ciebie."))
            opis.setWordWrap(True)
            opis.setOpenExternalLinks(True)
            f.addRow("", opis)
            self.autostart = QCheckBox(t("Uruchamiaj przy logowaniu"))
            self.autostart.setChecked(PLIK_AUTOSTARTU.exists())
            f.addRow("", self.autostart)
            return w

        # --------------------------------------------- zakladka Obserwacje
        def zakladka_obserwacje(self):
            w = QWidget()
            h = QHBoxLayout(w)
            lewa = QVBoxLayout()
            self.lista = QListWidget()
            for o in self.obs:
                self.lista.addItem(o.get("nazwa", ""))
            self.lista.currentRowChanged.connect(self.pokaz)
            lewa.addWidget(self.lista)
            przyciski = QHBoxLayout()
            dodaj = QPushButton(t("Dodaj"))
            m = QMenu(dodaj)
            for etykieta, wzor in SZABLONY:
                m.addAction(t(etykieta), lambda wz=wzor: self.dodaj(wz))
            dodaj.setMenu(m)
            usun = QPushButton(t("Usuń"))
            usun.clicked.connect(self.usun)
            gora = QPushButton("↑")
            gora.clicked.connect(lambda: self.przesun(-1))
            dol = QPushButton("↓")
            dol.clicked.connect(lambda: self.przesun(1))
            for b in (dodaj, usun, gora, dol):
                przyciski.addWidget(b)
            lewa.addLayout(przyciski)
            h.addLayout(lewa, 2)
            self.ramka = QGroupBox(t("Obserwacja"))
            self.formularz = QFormLayout(self.ramka)
            h.addWidget(self.ramka, 3)
            if self.obs:
                self.lista.setCurrentRow(0)
            else:
                self.pokaz(-1)
            return w

        def pokaz(self, i):
            # CO: buduje formularz pol dla wybranej obserwacji od nowa.
            while self.formularz.rowCount():
                self.formularz.removeRow(0)
            if i < 0 or i >= len(self.obs):
                self.formularz.addRow(QLabel(t("Wybierz obserwację z listy albo dodaj nową.")))
                return
            o = self.obs[i]
            typ_opis, pola = TYPY.get(o["typ"], (o["typ"], []))
            self.formularz.addRow(t("Rodzaj"), QLabel(t(typ_opis)))
            nazwa = QLineEdit(o.get("nazwa", ""))

            def zmiana_nazwy(tekst):
                o["nazwa"] = tekst
                self.lista.item(i).setText(tekst)
            nazwa.textChanged.connect(zmiana_nazwy)
            self.formularz.addRow(t("Nazwa"), nazwa)
            for klucz, etykieta, rodzaj, wymagane in pola:
                gwiazdka = " *" if wymagane else ""
                if rodzaj == "tak_nie":
                    pole = QCheckBox(t(etykieta))
                    pole.setChecked(bool(o.get(klucz)))
                    pole.toggled.connect(lambda v, k=klucz: o.__setitem__(k, v))
                    self.formularz.addRow("", pole)
                    continue
                if rodzaj == "wiersze":
                    pole = QPlainTextEdit("\n".join(o.get(klucz, [])))
                    pole.setFixedHeight(90)
                    pole.textChanged.connect(lambda p=pole, k=klucz: o.__setitem__(
                        k, [x.strip() for x in p.toPlainText().splitlines() if x.strip()]))
                else:
                    wartosc = o.get(klucz, "")
                    if rodzaj == "przecinki":
                        wartosc = ", ".join(wartosc or [])
                    elif rodzaj == "liczba":
                        wartosc = str(wartosc) if wartosc else ""
                    pole = QLineEdit(str(wartosc))
                    pole.setCursorPosition(0)   # dlugi adres: widac poczatek, nie koniec
                    if rodzaj == "liczba":
                        pole.setValidator(QIntValidator(1, 10**9))
                    pole.textChanged.connect(lambda v, k=klucz, r=rodzaj: o.__setitem__(k, self.zamien(v, r)))
                self.formularz.addRow(t(etykieta) + gwiazdka, pole)
            self.formularz.addRow("", QLabel(t("* pole wymagane")))

        @staticmethod
        def zamien(tekst, rodzaj):
            if rodzaj == "przecinki":
                return [x.strip() for x in tekst.split(",") if x.strip()]
            if rodzaj == "liczba":
                return int(tekst) if tekst.isdigit() else 0
            return tekst.strip()

        def dodaj(self, wzor):
            nowa = copy.deepcopy(wzor)
            nowa["nazwa"] = t(nowa["nazwa"])
            self.obs.append(nowa)
            self.lista.addItem(nowa["nazwa"])
            self.lista.setCurrentRow(len(self.obs) - 1)

        def usun(self):
            i = self.lista.currentRow()
            if i < 0:
                return
            del self.obs[i]
            self.lista.takeItem(i)
            self.pokaz(self.lista.currentRow())

        def przesun(self, krok):
            i = self.lista.currentRow()
            j = i + krok
            if i < 0 or j < 0 or j >= len(self.obs):
                return
            self.obs[i], self.obs[j] = self.obs[j], self.obs[i]
            self.lista.blockSignals(True)
            self.lista.clear()
            for o in self.obs:
                self.lista.addItem(o.get("nazwa", ""))
            self.lista.blockSignals(False)
            self.lista.setCurrentRow(j)

        def zapisz(self):
            nazwy = set()
            for i, o in enumerate(self.obs):
                braki = brakujace_pola(o)
                powtorka = o.get("nazwa", "").strip() in nazwy
                if braki or powtorka:
                    self.lista.setCurrentRow(i)
                    nazwa = o.get("nazwa", "")
                    QMessageBox.warning(self, TYTUL,
                                        t("Obserwacja „{nazwa}”: uzupełnij: {braki}.",
                                          nazwa=nazwa, braki=", ".join(braki)) if braki else
                                        t("Obserwacja „{nazwa}”: taka nazwa już jest, nazwy "
                                          "muszą się różnić.", nazwa=nazwa))
                    return
                nazwy.add(o["nazwa"].strip())
            self.u["jezyk"] = self.jezyk.currentData()
            self.u["co_ile_minut"] = self.minuty.value()
            self.u["github_token"] = self.token.text().strip()
            self.u["obserwacje"] = self.obs
            zapisz_ustawienia(self.u)
            ustaw_jezyk(self.u["jezyk"])
            ustaw_autostart(self.autostart.isChecked())
            self.accept()
            self.po_zapisie()

    return OknoUstawien


# ------------------------------------------------------ okienko zdarzen

def okienko_klasa():
    """CO: klasa okienka ze zdarzeniami (lewy przycisk na ikonie).
    DLACZEGO zwykle okno, a nie dymek przy ikonie: na Waylandzie program nie
    moze sam ustawic okna przy zasobniku; okno ustawia pulpit, a samo chowa
    sie, gdy klikniesz gdzie indziej."""
    from PyQt6.QtCore import QEvent, Qt, QUrl
    from PyQt6.QtGui import QColor, QDesktopServices, QIcon, QKeySequence, QPalette, QShortcut
    from PyQt6.QtWidgets import (QHBoxLayout, QHeaderView, QLabel, QPushButton, QToolButton,
                                 QTreeWidget, QTreeWidgetItem, QVBoxLayout, QWidget)

    class Okienko(QWidget):
        def __init__(self, sprawdz, ustawienia_cb, wyczysc):
            super().__init__()
            self.setWindowTitle(TYTUL)
            self.setWindowIcon(rysuj_ikone("spokoj"))
            self.resize(660, 420)
            self.schowane_o = 0.0
            uklad = QVBoxLayout(self)
            uklad.setContentsMargins(12, 10, 12, 10)
            uklad.setSpacing(6)

            gora = QHBoxLayout()
            self.ikona = QLabel()
            gora.addWidget(self.ikona)
            tytul = QLabel(TYTUL)
            f = tytul.font()
            f.setBold(True)
            f.setPointSizeF(f.pointSizeF() * 1.15)
            tytul.setFont(f)
            gora.addWidget(tytul)
            gora.addStretch()
            self.b_sprawdz = QToolButton()
            self.b_sprawdz.clicked.connect(sprawdz)
            self.b_ustaw = QToolButton()
            self.b_ustaw.clicked.connect(ustawienia_cb)
            for b, nazwa, zapas in ((self.b_sprawdz, "view-refresh", "⟳"),
                                    (self.b_ustaw, "configure", "⚙")):
                ik = QIcon.fromTheme(nazwa)
                if ik.isNull():
                    b.setText(zapas)
                else:
                    b.setIcon(ik)
                b.setAutoRaise(True)
                gora.addWidget(b)
            uklad.addLayout(gora)

            self.status = QLabel()
            self.status.setForegroundRole(QPalette.ColorRole.PlaceholderText)
            uklad.addWidget(self.status)
            self.bledy = QLabel()
            self.bledy.setWordWrap(True)
            self.bledy.setStyleSheet("color: #d32f2f;")
            uklad.addWidget(self.bledy)

            self.drzewo = QTreeWidget()
            self.drzewo.setColumnCount(3)
            self.drzewo.setHeaderHidden(True)
            self.drzewo.setRootIsDecorated(False)
            self.drzewo.setIndentation(14)
            # DLACZEGO skracanie na koncu: poczatek krotkiej nazwy (plytka, wersja)
            # najlepiej odroznia wpisy; pelna nazwa jest w dymku.
            self.drzewo.setTextElideMode(Qt.TextElideMode.ElideRight)
            self.drzewo.setUniformRowHeights(True)
            self.drzewo.setAlternatingRowColors(True)
            self.drzewo.setMouseTracking(True)
            n = self.drzewo.header()
            n.setStretchLastSection(False)
            n.setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
            n.setSectionResizeMode(1, QHeaderView.ResizeMode.Fixed)
            n.setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
            self.drzewo.itemClicked.connect(self.klik)
            uklad.addWidget(self.drzewo, 1)
            self.pusto = QLabel()
            self.pusto.setAlignment(Qt.AlignmentFlag.AlignCenter)
            self.pusto.setForegroundRole(QPalette.ColorRole.PlaceholderText)
            self.pusto.setMargin(24)
            uklad.addWidget(self.pusto, 1)

            dol = QHBoxLayout()
            self.podpowiedz = QLabel()
            self.podpowiedz.setForegroundRole(QPalette.ColorRole.PlaceholderText)
            dol.addWidget(self.podpowiedz)
            dol.addStretch()
            self.b_wyczysc = QPushButton()
            self.b_wyczysc.clicked.connect(wyczysc)
            dol.addWidget(self.b_wyczysc)
            uklad.addLayout(dol)
            QShortcut(QKeySequence("Escape"), self, self.hide)

        def odswiez(self, historia, stan_ui):
            """CO: wypelnia okienko: status, bledy i zdarzenia wedlug obserwacji."""
            self.ikona.setPixmap(rysuj_ikone(stan_ui["ikona"]).pixmap(22, 22))
            self.b_sprawdz.setToolTip(t("Sprawdź teraz"))
            self.b_ustaw.setToolTip(t("Ustawienia"))
            self.b_wyczysc.setText(t("Wyczyść"))
            self.b_wyczysc.setEnabled(bool(historia))
            self.podpowiedz.setText(t("Kliknij wpis, aby otworzyć stronę.") if historia else "")
            self.status.setText(opis_statusu(stan_ui))
            bledy = stan_ui["bledy"]
            self.bledy.setVisible(bool(bledy))
            self.bledy.setText("\n".join(f"• {b[:140]}" for b in bledy[:4])
                               + (("\n" + t("…i jeszcze {ile}", ile=len(bledy) - 4)) if len(bledy) > 4 else ""))
            self.bledy.setToolTip("\n".join(bledy))

            self.drzewo.clear()
            self.drzewo.setVisible(bool(historia))
            self.pusto.setVisible(not historia)
            self.pusto.setText(t("Nic nowego od uruchomienia."))
            grupy, ile = {}, {}
            for z in historia:   # najnowsze pierwsze; grupy w kolejnosci najnowszych
                grupa = grupy.get(z["obserwacja"])
                if grupa is None:
                    grupa = grupy[z["obserwacja"]] = QTreeWidgetItem(self.drzewo)
                    grupa.setFirstColumnSpanned(True)
                    f = grupa.font(0)
                    f.setBold(True)
                    grupa.setFont(0, f)
                    grupa.setFlags(Qt.ItemFlag.ItemIsEnabled)
                ile[z["obserwacja"]] = ile.get(z["obserwacja"], 0) + 1
                grupa.setText(0, f"{z['obserwacja']}  ({ile[z['obserwacja']]})")
                w = QTreeWidgetItem(grupa, [z["tytul"], z["zmiana"] or opis_nowego(z),
                                            z["czas"][11:] if z["czas"][:10] == datetime.now()
                                            .strftime("%Y-%m-%d") else z["czas"][5:]])
                w.setData(0, Qt.ItemDataRole.UserRole, z["url"])
                w.setToolTip(0, f"{z['pelny']}\n{z['url']}")
                w.setToolTip(1, z["zmiana"] or opis_nowego(z))
                if z.get("nieprzeczytane"):
                    f = w.font(0)
                    f.setBold(True)
                    w.setFont(0, f)
                if z["wazne"]:
                    w.setForeground(1, QColor(KOLOR_NOWE))
            self.drzewo.expandAll()
            # DLACZEGO limit: dluga zmiana (np. stan PR i komentarze) nie moze
            # zabrac miejsca nazwie; reszta jest w dymku.
            self.drzewo.setColumnWidth(1, min(self.drzewo.sizeHintForColumn(1) + 12, 240))

        def klik(self, w, kolumna):
            url = w.data(0, Qt.ItemDataRole.UserRole)
            if url:
                QDesktopServices.openUrl(QUrl(url))

        def changeEvent(self, e):
            # CO: chowa okienko, gdy klikniesz poza nim (jak dymek z zasobnika).
            if e.type() == QEvent.Type.ActivationChange and not self.isActiveWindow() \
                    and self.isVisible():
                self.schowane_o = time.time()
                self.hide()
            super().changeEvent(e)

    return Okienko


def opis_statusu(stan_ui):
    if stan_ui["trwa"]:
        return t("sprawdzam…")
    if stan_ui["ostatnie"] is None:
        return t("Ostatnie sprawdzenie: {czas}", czas=t("jeszcze nie"))
    nast = (stan_ui["ostatnie"] + timedelta(minutes=stan_ui["co_ile"])).strftime("%H:%M")
    return t("Ostatnie sprawdzenie: {czas} · następne ok. {nast}",
             czas=stan_ui["ostatnie"].strftime("%H:%M"), nast=nast)


# ------------------------------------------------------ ikona w zasobniku

def uruchom_ikone():
    from PyQt6.QtCore import QObject, QTimer, QUrl, pyqtSignal
    from PyQt6.QtGui import QAction, QDesktopServices
    from PyQt6.QtWidgets import QApplication, QMenu, QSystemTrayIcon

    pierwszy_start = not PLIK_USTAWIEN.exists()
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    app.setApplicationName(TYTUL)
    app.setDesktopFileName(NAZWA)

    class Poslaniec(QObject):
        # DLACZEGO sygnal: sprawdzanie idzie w osobnym watku (siec potrafi stac
        # minute), a ikone i menu wolno zmieniac tylko z watku okna.
        gotowe = pyqtSignal(list, list)

    poslaniec = Poslaniec()
    tray = QSystemTrayIcon(rysuj_ikone("spokoj"))
    menu = QMenu()
    historia = []          # ostatnie zdarzenia, najnowsze pierwsze
    stan_ui = {"ikona": "spokoj", "trwa": False, "ostatnie": None, "bledy": [],
               "url_powiadomienia": None,
               "co_ile": max(15, int(ustawienia().get("co_ile_minut", 60)))}

    def otworz(url):
        QDesktopServices.openUrl(QUrl(url))

    def ustaw_ikone(stan):
        stan_ui["ikona"] = stan
        tray.setIcon(rysuj_ikone(stan))

    def oznacz_przeczytane():
        ustaw_ikone("spokoj")
        odswiez_menu()

    def odswiez_menu():
        menu.clear()
        naglowek = menu.addAction(opis_statusu(stan_ui))
        naglowek.setEnabled(False)
        menu.addAction(t("Pokaż zdarzenia"), pokaz_okienko)
        menu.addAction(t("Sprawdź teraz"), sprawdz_teraz)
        menu.addSeparator()
        for o in ustawienia()["obserwacje"]:
            if o["typ"] == "katalog":
                menu.addAction(t("Otwórz: {nazwa}", nazwa=o["nazwa"]), lambda u=o["url"]: otworz(u))
        menu.addSeparator()
        menu.addAction(t("Ustawienia…"), lambda: pokaz_ustawienia(False))
        auto = QAction(t("Uruchamiaj przy starcie"), menu)
        auto.setCheckable(True)
        auto.setChecked(PLIK_AUTOSTARTU.exists())
        auto.toggled.connect(ustaw_autostart)
        menu.addAction(auto)
        menu.addAction(t("Zakończ"), app.quit)
        nowe = sum(1 for z in historia if z.get("nieprzeczytane"))
        tray.setToolTip(TYTUL + "\n" + opis_statusu(stan_ui)
                        + (("\n" + t("Nowe: {ile}", ile=nowe)) if nowe else "")
                        + (("\n" + t("Błędy: {ile}", ile=len(stan_ui["bledy"]))) if stan_ui["bledy"] else ""))
        if okienko.isVisible():
            okienko.odswiez(historia, stan_ui)

    def sprawdz_teraz():
        if stan_ui["trwa"]:
            return
        stan_ui["trwa"] = True
        odswiez_menu()

        def praca():
            try:
                zdarzenia, bledy = sprawdz_wszystko()
            except Exception as e:
                zdarzenia, bledy = [], [str(e)]
            poslaniec.gotowe.emit(zdarzenia, bledy)
        threading.Thread(target=praca, daemon=True).start()

    def po_sprawdzeniu(zdarzenia, bledy):
        stan_ui["trwa"] = False
        stan_ui["ostatnie"] = datetime.now()
        stan_ui["bledy"] = bledy
        if zdarzenia:
            for z in zdarzenia:
                z["nieprzeczytane"] = True
            historia[:0] = list(reversed(zdarzenia))
            del historia[100:]
            obrazy = [z for z in zdarzenia if z["wazne"] and z["typ"] == "katalog"]
            wazne = [z for z in zdarzenia if z["wazne"]]
            # DLACZEGO pingwin tylko przy obrazie: to najwazniejsze zdarzenie
            # (obraz do testu); reszta zmian to czerwone kolko.
            if obrazy:
                ustaw_ikone("obraz")
            elif stan_ui["ikona"] != "obraz":
                ustaw_ikone("nowe")
            pokazane = wazne or zdarzenia
            stan_ui["url_powiadomienia"] = pokazane[0]["url"]
            if obrazy:
                tytul = t("Nowy obraz do testu!") if len(obrazy) == 1 else \
                    t("Nowe obrazy do testu: {ile}", ile=len(obrazy))
            else:
                tytul = t("Armbian Watch: nowe zdarzenia: {ile}", ile=len(zdarzenia))
            linie = [("• " + tekst_zdarzenia(z)) if wazne else f"• {z['obserwacja']}: {tekst_zdarzenia(z)}"
                     for z in pokazane[:5]]
            if len(pokazane) > 5:
                linie.append(t("…i jeszcze {ile}", ile=len(pokazane) - 5))
            # DLACZEGO wazne powiadomienie bez limitu czasu: obraz do testu ma
            # nie zniknac, zanim uzytkownik go zauwazy.
            tray.showMessage(tytul, "\n".join(linie), rysuj_ikone("obraz" if obrazy else "nowe"),
                             0 if wazne else 15000)
        odswiez_menu()

    def klik_w_powiadomienie():
        if stan_ui["url_powiadomienia"]:
            otworz(stan_ui["url_powiadomienia"])
        oznacz_przeczytane()

    def pokaz_okienko():
        okienko.odswiez(historia, stan_ui)
        okienko.show()
        okienko.raise_()
        okienko.activateWindow()
        # DLACZEGO: obejrzane = przeczytane; pogrubienie zostaje do kolejnego
        # otwarcia, zeby bylo widac, co doszlo.
        for z in historia:
            z["nieprzeczytane"] = False
        oznacz_przeczytane()

    def klik_w_ikone(powod):
        # DLACZEGO bez menu pod lewym przyciskiem: na Waylandzie Qt nie moze
        # otworzyc menu bez okna-rodzica; menu jest pod prawym przyciskiem.
        if powod == QSystemTrayIcon.ActivationReason.Trigger:
            # DLACZEGO 0,4 s: klik w ikone najpierw zabiera okienku fokus (ono
            # sie chowa), a dopiero potem przychodzi tutaj; bez tego okienko
            # od razu otworzyloby sie z powrotem.
            if okienko.isVisible() or time.time() - okienko.schowane_o < 0.4:
                okienko.hide()
            else:
                pokaz_okienko()

    def wyczysc():
        historia.clear()
        oznacz_przeczytane()

    OknoUstawien = okno_ustawien_klasa()
    okna = []   # DLACZEGO lista: okno musi miec zywa referencje, inaczej Python je usunie

    def po_zapisie_ustawien():
        # DLACZEGO: po wpisaniu albo zmianie tokenu stara blokada limitu juz nie
        # obowiazuje (z tokenem limit jest liczony na konto, nie na adres IP).
        for zasob in github_przerwa_do:
            github_przerwa_do[zasob] = 0.0
        stan_ui["co_ile"] = max(15, int(ustawienia().get("co_ile_minut", 60)))
        zegar.start(stan_ui["co_ile"] * 60 * 1000)
        odswiez_menu()
        sprawdz_teraz()

    def pokaz_ustawienia(powitanie):
        if okna and okna[0].isVisible():
            okna[0].raise_()
            okna[0].activateWindow()
            return
        okna[:] = [OknoUstawien(po_zapisie_ustawien, powitanie)]
        okna[0].show()

    okienko = okienko_klasa()(sprawdz_teraz, lambda: pokaz_ustawienia(False), wyczysc)
    poslaniec.gotowe.connect(po_sprawdzeniu)
    tray.messageClicked.connect(klik_w_powiadomienie)
    tray.activated.connect(klik_w_ikone)
    tray.setContextMenu(menu)
    odswiez_menu()
    tray.show()

    zegar = QTimer()
    zegar.timeout.connect(sprawdz_teraz)
    zegar.start(stan_ui["co_ile"] * 60 * 1000)
    QTimer.singleShot(3000, sprawdz_teraz)   # pierwsze sprawdzenie zaraz po starcie
    if pierwszy_start:
        QTimer.singleShot(1000, lambda: pokaz_ustawienia(True))
    sys.exit(app.exec())


# CO: pingwin Armbiana (128 x 128 PNG), ikona "nowy obraz do testu".
# Zrodlo: armbian/build, packages/bsp/common/usr/share/armbian/armbian-user-icon.png
# (GPL-2.0).
PINGWIN_PNG = """
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
Tdbk/pL/DzXBmLSVHifAAAAAAElFTkSuQmCC
"""


def main():
    if "--wersja" in sys.argv or "--version" in sys.argv:
        print(f"{NAZWA} {WERSJA}")
        return
    przenies_stare_pliki()
    # DLACZEGO jezyk przed czymkolwiek innym: od niego zaleza nazwy obserwacji
    # w ustawieniach tworzonych przy pierwszym starcie.
    ustaw_jezyk(wczytaj_json(PLIK_USTAWIEN, {}).get("jezyk", "auto"))
    if "--once" in sys.argv or "--raz" in sys.argv:
        start = time.time()
        zdarzenia, bledy = sprawdz_wszystko()
        for z in zdarzenia:
            print(("[!] " if z["wazne"] else "") + f"{z['obserwacja']}: {tekst_zdarzenia(z)}\n    {z['url']}")
        for b in bledy:
            print(t("BŁĄD:"), b)
        stan = wczytaj_json(PLIK_STANU, {})
        print(t("Zdarzeń: {z}, błędów: {b}, obserwacji w stanie: {o}, czas: {c:.1f} s",
                z=len(zdarzenia), b=len(bledy), o=len([k for k in stan if not k.startswith("_")]),
                c=time.time() - start))
        return
    uruchom_ikone()


if __name__ == "__main__":
    main()
