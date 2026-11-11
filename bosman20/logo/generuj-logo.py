#!/usr/bin/env python3
# Uzycie: python3 generuj-logo.py <katalog>   (tworzy bosman20-logo*.svg i bosman20-icon.svg)
# CO: logo Bosman20: ikona (uklad A20 ze sterem okretowym i dysza drukarki) + napis.
# DLACZEGO litery z poziomych pasow: wygladaja jak warstwy wydruku 3D; sa rysowane
#     prostokatami, wiec logo nie zalezy od zainstalowanych czcionek (jak w Arkada20).
import math
import sys
OUT = sys.argv[1]

GLYPHS = {
 'B': ["####.","#...#","#...#","####.","#...#","#...#","####."],
 'O': [".###.","#...#","#...#","#...#","#...#","#...#",".###."],
 'S': [".####","#....","#....",".###.","....#","....#","####."],
 'M': ["#...#","##.##","#.#.#","#.#.#","#...#","#...#","#...#"],
 'A': [".###.","#...#","#...#","#####","#...#","#...#","#...#"],
 'N': ["#...#","##..#","#.#.#","#..##","#...#","#...#","#...#"],
 '2': [".###.","#...#","....#","...#.","..#..",".#...","#####"],
 '0': [".###.","#...#","#..##","#.#.#","##..#","#...#",".###."],
}
C = dict(bg="#0b1a2e", body="#12304f", line="#4fd1c5", orange="#ff8a3d",
         white="#eef6ff", shadow="#06101d", brass="#f2b544")

def word(text, x0, y0, px, colors):
    # Kazdy piksel litery = dwie warstwy (pasy) z cienka szczelina, jak linie wydruku.
    out = []
    lay = px / 2.0
    for shadow in (True, False):
        x = x0
        for i, ch in enumerate(text):
            col = C["shadow"] if shadow else colors[i]
            d = px * 0.35 if shadow else 0
            for r, row in enumerate(GLYPHS[ch]):
                c = 0
                while c < 5:
                    if row[c] != '#':
                        c += 1
                        continue
                    # sasiednie piksele w wierszu laczone w jeden ciagly pas
                    e = c
                    while e < 5 and row[e] == '#':
                        e += 1
                    for k in range(2):
                        out.append(f'<rect x="{x+c*px+d:.1f}" y="{y0+r*px+k*lay+d:.1f}" '
                                   f'width="{(e-c)*px+0.6:.1f}" height="{lay-0.7:.1f}" rx="1.2" fill="{col}"/>')
                    c = e
            x += 6 * px
    return "<g>\n" + "\n".join(out) + "\n</g>", x0 + len(text) * 6 * px - px

def icon(x, y, s):
    k = s / 96.0
    g = [f'<g transform="translate({x},{y}) scale({k})">']
    # nozki ukladu A20, po 6 na kazdym boku (jak w logo Arkada20)
    for i in range(6):
        p = 18 + i * 12
        g.append(f'<rect x="{p-2.5}" y="0" width="5" height="10" rx="1" fill="{C["line"]}"/>')
        g.append(f'<rect x="{p-2.5}" y="86" width="5" height="10" rx="1" fill="{C["line"]}"/>')
        g.append(f'<rect x="0" y="{p-2.5}" width="10" height="5" rx="1" fill="{C["line"]}"/>')
        g.append(f'<rect x="86" y="{p-2.5}" width="10" height="5" rx="1" fill="{C["line"]}"/>')
    g.append(f'<rect x="8" y="8" width="80" height="80" rx="10" fill="{C["body"]}" stroke="{C["line"]}" stroke-width="3"/>')
    g.append(f'<circle cx="19" cy="19" r="3" fill="{C["line"]}" opacity="0.7"/>')
    # ster okretowy: kolo z 8 szprychami i uchwytami
    cx, cy = 48, 38
    for i in range(8):
        a = math.radians(i * 45 + 22.5)
        x1, y1 = cx + 7 * math.cos(a), cy + 7 * math.sin(a)
        x2, y2 = cx + 25 * math.cos(a), cy + 25 * math.sin(a)
        g.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{C["brass"]}" stroke-width="3.2" stroke-linecap="round"/>')
    g.append(f'<circle cx="{cx}" cy="{cy}" r="17" fill="none" stroke="{C["brass"]}" stroke-width="3.6"/>')
    # piasta steru = dysza drukarki, pod nia swieza warstwa filamentu
    g.append(f'<circle cx="{cx}" cy="{cy}" r="8.5" fill="{C["body"]}"/>')
    g.append(f'<rect x="{cx-5.5}" y="{cy-8}" width="11" height="8" rx="1.5" fill="{C["white"]}"/>')
    g.append(f'<path d="M{cx-5},{cy} L{cx+5},{cy} L{cx+1.6},{cy+6} L{cx-1.6},{cy+6} Z" fill="{C["white"]}"/>')
    # wydruk pod sterem: trzy warstwy, najwyzsza krotsza (wlasnie drukowana)
    g.append(f'<rect x="22" y="78" width="52" height="4" rx="2" fill="{C["orange"]}" opacity="0.55"/>')
    g.append(f'<rect x="22" y="73" width="52" height="4" rx="2" fill="{C["orange"]}" opacity="0.8"/>')
    g.append(f'<rect x="22" y="68" width="34" height="4" rx="2" fill="{C["orange"]}"/>')
    g.append('</g>')
    return "\n".join(g)

def svg(w, h, body, bg):
    back = f'<rect width="{w}" height="{h}" rx="{int(h*0.12)}" fill="{C["bg"]}"/>' if bg else ''
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">\n<title>Bosman20</title>\n{back}\n{body}\n</svg>\n'

px = 9
txt, xend = word("BOSMAN20", 160, 38, px, [C["white"]]*6 + [C["orange"]]*2)
W = int(xend + 30)
open(f"{OUT}/bosman20-logo.svg","w").write(svg(W, 140, icon(24, 22, 96) + "\n" + txt, True))
open(f"{OUT}/bosman20-logo-transparent.svg","w").write(svg(W, 140, icon(24, 22, 96) + "\n" + txt, False))
open(f"{OUT}/bosman20-icon.svg","w").write(svg(128, 128, icon(16, 16, 96), True))
print("szerokosc", W)
