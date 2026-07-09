#!/usr/bin/env python3
"""Generate the 13 Game Center icons (512x512 PNG, RGB, no alpha) as LEXIS
letter/glyph tiles. Renders inline SVG via headless Google Chrome.

Run:  python3 store/gamecenter-icons/generate.py
Output: store/gamecenter-icons/*.png  (leaderboards gold, achievements mint)
"""
import os, subprocess, tempfile

OUT = os.path.dirname(os.path.abspath(__file__))
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

BG    = "#0F0F1F"   # lexisBg
MINT  = "#66E5B3"   # lexisAccent  — achievements
GOLD  = "#FFD133"   # lexisGold    — leaderboards
WHITE = "#F2F2FF"   # lexisText
RED   = "#FF4059"   # lexisDanger

def txt(s, size, dy=0, fill=WHITE):
    return (f'<text x="256" y="{262+dy}" text-anchor="middle" '
            f'dominant-baseline="central" font-family="Arial Black, Arial, sans-serif" '
            f'font-weight="900" font-size="{size}" letter-spacing="-4" fill="{fill}">{s}</text>')

# A clean lightning bolt, centred ~ (256,256).
BOLT = f'<polygon points="288,150 188,280 246,280 224,362 328,212 266,212" fill="{WHITE}"/>'

def flame(fill=WHITE):
    return (f'<path d="M256 150 C 300 200 302 240 280 268 C 316 252 316 316 256 360 '
            f'C 196 316 198 254 232 268 C 210 240 214 200 256 150 Z" fill="{fill}"/>')

def tile(border, glow, inner):
    return f'''<svg width="512" height="512" viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <radialGradient id="g" cx="50%" cy="40%" r="60%">
      <stop offset="0%" stop-color="{glow}" stop-opacity="0.45"/>
      <stop offset="55%" stop-color="{glow}" stop-opacity="0.07"/>
      <stop offset="100%" stop-color="{glow}" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="t" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#33406B"/>
      <stop offset="100%" stop-color="#1A2138"/>
    </linearGradient>
  </defs>
  <rect width="512" height="512" fill="{BG}"/>
  <rect width="512" height="512" fill="url(#g)"/>
  <rect x="106" y="106" width="300" height="300" rx="58" fill="url(#t)" stroke="{border}" stroke-width="9"/>
  <rect x="122" y="122" width="268" height="120" rx="46" fill="#FFFFFF" opacity="0.06"/>
  {inner}
</svg>'''

# (filename, border, glow, inner-glyph)
ITEMS = [
    # Leaderboards — gold
    ("lb_relaxed",         GOLD, GOLD, txt("R", 190)),
    ("lb_classic",         GOLD, GOLD, txt("C", 190)),
    ("lb_rapid",           GOLD, GOLD, BOLT),
    ("lb_insane",          GOLD, GOLD, flame(WHITE)),
    ("lb_daily",           GOLD, GOLD, txt("D", 190)),
    ("lb_weekly",          GOLD, GOLD, txt("W", 168)),
    # Achievements — mint
    ("ach_first_word",     MINT, MINT, txt("A", 190)),
    ("ach_50_words",       MINT, MINT, txt("50", 150)),
    ("ach_200_words",      MINT, MINT, txt("200", 112)),
    ("ach_seven_letters",  MINT, MINT, txt("7", 190)),
    ("ach_combo_5",        MINT, MINT, txt("5&#215;", 128)),
    ("ach_insane_survivor",MINT, MINT, flame(RED)),
    ("ach_score_10k",      MINT, MINT, txt("10K", 108)),
]

def render(name, svg):
    html = ('<html><head><style>*{margin:0;padding:0}'
            'html,body{width:512px;height:512px;overflow:hidden;background:' + BG + '}'
            '</style></head><body>' + svg + '</body></html>')
    with tempfile.NamedTemporaryFile('w', suffix='.html', delete=False) as f:
        f.write(html); html_path = f.name
    png = os.path.join(OUT, name + '.png')
    subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars',
                    '--force-device-scale-factor=1', '--window-size=512,512',
                    '--default-background-color=FF0F0F1F',
                    '--screenshot=' + png, html_path],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.unlink(html_path)
    print('  ' + name + '.png')

if __name__ == '__main__':
    print('Rendering 13 Game Center icons →', OUT)
    for name, border, glow, inner in ITEMS:
        render(name, tile(border, glow, inner))
    print('Done.')
