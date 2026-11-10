#!/usr/bin/env python3
# Uzycie: python3 generuj-logo.py <katalog>   (tworzy arkada20-logo*.svg i arkada20-icon.svg)
# Litery rysowane z pikseli (prostokatow), wiec logo nie zalezy od zainstalowanych czcionek.
# Generuje logo Arkada20 (SVG): ikona (uklad A20 z joystickiem) + pikselowy napis.
import sys
OUT = sys.argv[1]

GLYPHS = {
 'A': [".###.","#...#","#...#","#####","#...#","#...#","#...#"],
 'R': ["####.","#...#","#...#","####.","#.#..","#..#.","#...#"],
 'K': ["#...#","#..#.","#.#..","##...","#.#..","#..#.","#...#"],
 'D': ["####.","#...#","#...#","#...#","#...#","#...#","####."],
 '2': [".###.","#...#","....#","...#.","..#..",".#...","#####"],
 '0': [".###.","#...#","#..##","#.#.#","##..#","#...#",".###."],
}
C = dict(bg="#140b24", body="#21123d", line="#2ee6ff", pink="#ff3ea5", white="#f4f1ff", shadow="#0a0614")

def word(text, x0, y0, px, colors):
    out = []
    x = x0
    for i, ch in enumerate(text):
        col = colors[i]
        for r, row in enumerate(GLYPHS[ch]):
            for c, v in enumerate(row):
                if v == '#':
                    # cien przesuniety o 1 piksel, dla glebi jak na automatach
                    out.append(f'<rect x="{x+c*px+px*0.35:.1f}" y="{y0+r*px+px*0.35:.1f}" width="{px+0.6}" height="{px+0.6}" fill="{C["shadow"]}"/>')
        x += 6 * px
    x = x0
    for i, ch in enumerate(text):
        col = colors[i]
        for r, row in enumerate(GLYPHS[ch]):
            for c, v in enumerate(row):
                if v == '#':
                    out.append(f'<rect x="{x+c*px}" y="{y0+r*px}" width="{px+0.6}" height="{px+0.6}" fill="{col}"/>')
        x += 6 * px
    return '<g shape-rendering="crispEdges">\n' + "\n".join(out) + '\n</g>', x - px

def icon(x, y, s):
    # Uklad scalony 96x96 w skali s, z noz kami i joystickiem
    k = s / 96.0
    g = [f'<g transform="translate({x},{y}) scale({k})">']
    # noz ki: po 6 na kazdym boku
    for i in range(6):
        p = 18 + i * 12
        g.append(f'<rect x="{p-2.5}" y="0" width="5" height="10" rx="1" fill="{C["line"]}"/>')
        g.append(f'<rect x="{p-2.5}" y="86" width="5" height="10" rx="1" fill="{C["line"]}"/>')
        g.append(f'<rect x="0" y="{p-2.5}" width="10" height="5" rx="1" fill="{C["line"]}"/>')
        g.append(f'<rect x="86" y="{p-2.5}" width="10" height="5" rx="1" fill="{C["line"]}"/>')
    g.append(f'<rect x="8" y="8" width="80" height="80" rx="10" fill="{C["body"]}" stroke="{C["line"]}" stroke-width="3"/>')
    # znacznik pinu 1, jak na prawdziwym ukladzie
    g.append(f'<circle cx="19" cy="19" r="3" fill="{C["line"]}" opacity="0.7"/>')
    # joystick: podstawa, drazek, kulka z odblaskiem
    g.append(f'<ellipse cx="48" cy="70" rx="22" ry="7" fill="{C["shadow"]}" stroke="{C["line"]}" stroke-width="2.5"/>')
    g.append(f'<rect x="45" y="38" width="6" height="32" rx="3" fill="{C["white"]}"/>')
    g.append(f'<circle cx="48" cy="34" r="13" fill="{C["pink"]}"/>')
    g.append(f'<circle cx="43.5" cy="29.5" r="4" fill="{C["white"]}" opacity="0.85"/>')
    g.append('</g>')
    return "\n".join(g)

def svg(w, h, body, bg):
    back = f'<rect width="{w}" height="{h}" rx="{int(h*0.12)}" fill="{C["bg"]}"/>' if bg else ''
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">\n<title>Arkada20</title>\n{back}\n{body}\n</svg>\n'

px = 9
txt, xend = word("ARKADA20", 160, 38, px, [C["white"]]*6 + [C["pink"]]*2)
W = xend + 30
open(f"{OUT}/arkada20-logo.svg","w").write(svg(W, 140, icon(24, 22, 96) + "\n" + txt, True))
open(f"{OUT}/arkada20-logo-transparent.svg","w").write(svg(W, 140, icon(24, 22, 96) + "\n" + txt, False))
open(f"{OUT}/arkada20-icon.svg","w").write(svg(128, 128, icon(16, 16, 96), True))
print("szerokosc", W)
