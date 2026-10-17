# Generates Design/BigScreen/Duo/DuoLayouts.html and one render page per state in /tmp/duo.
import os, re
REPO = '/Users/valz/Documents/perso/trains-near-me'
OUTDIR = REPO + '/Design/BigScreen/Duo'
TMP = '/tmp/duo'
FONTDIR_REL = '../../../SNCFCore/Sources/SNCFCore/Theme/Fonts/'
FONTDIR_ABS = 'file://' + REPO + '/SNCFCore/Sources/SNCFCore/Theme/Fonts/'

MONO = "'JetBrains Mono', ui-monospace, monospace"
SANS = "-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif"

# ---------------------------------------------------------------- geometry (points)
OUT_W, OUT_H = 466, 678          # outer screen, portrait, spine on the left edge
IN_W, IN_H = 951, 669            # inner screen, landscape (panel nativeOrientation 270)
HINGE = IN_W / 2                 # 475.5: the fold runs down the middle of the long axis
KEEP = 12                        # half-width of the keep-out band around the crease (assumption)
L_END = HINGE - KEEP             # 463.5: left half usable to here
R_START = HINGE + KEEP           # 487.5: right half usable from here

TH = {
  'dark': dict(name='dark', ground='#0E0F11', card='#17191C', raised='#23262B', ink='#F2EFE8', ink2='#8F8D86', ink3='#D9D6CE',
               amber='#FFC23D', time='#FFC23D', clear='#46C27A', cau='#FF9A55', caubg='rgba(255,138,61,0.16)',
               stop='#FF6B5F', stopbg='rgba(255,90,78,0.16)', W='#B5AD9F', E='#7D8A98',
               hair='rgba(255,255,255,0.07)', hair2='rgba(255,255,255,0.12)', chipline='rgba(242,239,232,0.22)',
               grid='rgba(255,255,255,0.05)', flap='#23262B', flapdigit='#FFC23D', seam='#0E0F11', ring='#0E0F11',
               dash='#6E6C66', sleeper='#3A3631', sleeperH='#4A453E', rail='#9C9A93', mdel='#D9771A', msev='#C42B1C',
               gcau='#FF9A55', gstop='#FF6B5F', sel='rgba(255,194,61,0.09)', selring='rgba(255,194,61,0.55)',
               glass='rgba(38,41,46,0.78)', glassline='rgba(255,255,255,0.10)', tabsel='rgba(255,255,255,0.10)',
               crease='rgba(255,255,255,0.045)', creaseline='rgba(255,255,255,0.07)', wall='#0A0B0C',
               plate='#0E0F11', hatch='rgba(255,194,61,0.34)', past='rgba(255,255,255,0.025)',
               barink='#F2EFE8', barinktext='#0E0F11', clockdigit='#F2EFE8', paper='#F2EFE8', papertext='#0E0F11'),
  'light': dict(name='light', ground='#F2EFE8', card='#FBFAF7', raised='#ECE8DF', ink='#16171A', ink2='#66645E', ink3='#3A3631',
               amber='#FFC23D', time='#16171A', clear='#2B7F4C', cau='#9A4808', caubg='#FBE3CC',
               stop='#A3231A', stopbg='#F8D9D4', W='#3A3631', E='#55606D',
               hair='rgba(22,23,26,0.08)', hair2='rgba(22,23,26,0.14)', chipline='rgba(22,23,26,0.22)',
               grid='#E6E1D6', flap='#16171A', flapdigit='#FFC23D', seam='rgba(242,239,232,0.16)', ring='#16171A',
               dash='#A9A69E', sleeper='#E2DDD2', sleeperH='#C9C2B4', rail='#A9A69E', mdel='#D9771A', msev='#C42B1C',
               gcau='#9A4808', gstop='#A3231A', sel='rgba(255,194,61,0.22)', selring='rgba(196,140,20,0.55)',
               glass='rgba(251,250,247,0.86)', glassline='rgba(22,23,26,0.08)', tabsel='rgba(22,23,26,0.07)',
               crease='rgba(22,23,26,0.035)', creaseline='rgba(22,23,26,0.06)', wall='#F2EFE8',
               plate='#16171A', hatch='rgba(255,194,61,0.55)', past='rgba(22,23,26,0.035)',
               barink='#16171A', barinktext='#F2EFE8', clockdigit='#F2EFE8', paper='#16171A', papertext='#F2EFE8'),
}

NOW = 17 * 60 + 40
def mins(t):
    h, m = t.split(':'); return int(h) * 60 + int(m)
def hhmm(m):
    m %= 1440
    return f'{m // 60:02d}:{m % 60:02d}'

# ---------------------------------------------------------------- data
# Journey Grenoble -> Voiron (the Tableau board)
JOURNEY = [  # dep, arr, number, duration, status
  ('17:42', '18:07', '17653', '25 min', ('next', 'in 2 min')),
  ('18:12', '18:36', '17655', '24 min', ('late', 12)),
  ('18:42', '19:08', '17657', '26 min', ('canc',)),
  ('19:12', '19:37', '17659', '25 min', ('wait', '1 h 32')),
  ('19:42', '20:07', '17661', '25 min', ('late', 24)),
  ('20:42', '21:07', '17663', '25 min', ('wait', '3 h 02')),
]
# Voiron station (the StationLines river): line -> trains (time, delay | 'X')
LINES = {
  'lyon': dict(name='Lyon Part-Dieu', side='W', num=17614, trains=[('17:51', 0), ('18:21', 12), ('18:51', 0), ('19:21', 0)]),
  'sag':  dict(name='St-André-le-Gaz', side='W', num=17710, trains=[('18:05', 0), ('19:05', 'X'), ('20:05', 0)]),
  'gre':  dict(name='Grenoble', side='E', num=17613, trains=[('17:46', 0), ('17:58', 0), ('18:16', 24), ('18:28', 0), ('18:46', 0)]),
  'ugg':  dict(name='Grenoble Universités-Gières', short='Grenoble Univ.-Gières', side='E', num=17717, trains=[('18:10', 0), ('19:10', 0)]),
  'val':  dict(name='Valence Ville', side='E', num=17853, via='via Moirans', trains=[('18:02', 0), ('19:02', 0), ('20:02', 0)]),
}
LANE_ORDER = ['lyon', 'sag', 'ugg', 'gre', 'val']   # same order as StationLines-B (W above the axis, E below)

def station_departures():
    out = []
    for k, L in LINES.items():
        for i, (t, d) in enumerate(L['trains']):
            out.append(dict(t=t, d=d, line=k, name=L.get('short', L['name']) if False else L['name'], num=L['num'] + 2 * i, side=L['side']))
    return sorted(out, key=lambda r: mins(r['t']))

# ---------------------------------------------------------------- small pieces
def mono(size, weight=500, color=None, ls=0, extra=''):
    c = f' color: {color};' if color else ''
    l = f' letter-spacing: {ls}px;' if ls else ''
    return f'font: {weight} {size}px {MONO};{c}{l} {extra}'

def caps(text, th, size=10.5, color=None, ls=1.4, weight=600):
    return f'<span style="{mono(size, weight, color or th["ink2"], ls)}; white-space: nowrap">{text}</span>'

def pill(text, fg, bg, size=12.5, pad='3px 7px'):
    return f'<span style="{mono(size, 700, fg)}; background: {bg}; padding: {pad}; border-radius: 7px; white-space: nowrap">{text}</span>'

def chip(text, th, size=10.5):
    return (f'<span style="{mono(size, 600, th["ink"], 0.6)}; padding: 1px 5px; border-radius: 5px; '
            f'border: 1px solid {th["chipline"]}; white-space: nowrap">{text}</span>')

def tag(text, th, filled=True, size=10):
    if filled:
        return f'<span style="{mono(size, 700, "#0E0F11", 1.2)}; background: {th["amber"]}; padding: 3px 6px; border-radius: 5px; white-space: nowrap">{text}</span>'
    col = th['amber'] if th['name'] == 'dark' else th['ink']
    return f'<span style="{mono(size, 700, col, 1.2)}; border: 1.5px solid {th["amber"]}; padding: 2px 5px; border-radius: 5px; white-space: nowrap">{text}</span>'

def late_pill(d, th, size=12.5):
    fg, bg = (th['cau'], th['caubg']) if d < 20 else (th['stop'], th['stopbg'])
    return pill(f'+{d}', fg, bg, size)

def canc_pill(th, size=11):
    return pill('CANCELLED', th['stop'], th['stopbg'], size, '5px 7px')

def next_time_style(th, size, weight=700):
    """The next train's time: amber text on dark, an amber fill on light (amber is never text on paper)."""
    if th['name'] == 'dark':
        return f'{mono(size, weight, th["amber"])}'
    return f'{mono(size, weight, th["ink"])}; background: {th["amber"]}; border-radius: 6px; padding: 0 4px; margin: 0 -4px'

def flaps(t, th, w=36, h=52, fs=34, gap=4, digit=None, bg=None, colon=None):
    digit = digit or th['flapdigit']; bg = bg or th['flap']
    colon = colon or (th['amber'] if th['name'] == 'dark' else th['ink'])
    def tile(d):
        return (f'<span style="width: {w}px; height: {h}px; border-radius: {max(4, round(w * 0.19))}px; background: {bg}; position: relative; '
                f'display: inline-flex; align-items: center; justify-content: center; {mono(fs, 700, digit)}">{d}'
                + (f'<span style="position: absolute; left: 0; right: 0; top: {h / 2 - .5}px; height: 1px; background: {th["seam"] if bg == th["flap"] else "rgba(0,0,0,0.35)"}"></span>' if bg != th['raised'] else '') + '</span>')
    parts = [tile(c) if c != ':' else f'<span style="width: {fs * 0.32:.0f}px; text-align: center; {mono(fs * 0.8, 700, colon)}">:</span>' for c in t]
    return f'<span style="display: inline-flex; align-items: center; gap: {gap}px" role="img" aria-label="{t}">' + ''.join(parts) + '</span>'

def glyph(th, h=40, w=14):
    return (f'<div style="width: {w}px; height: {h}px; display: flex; flex-direction: column; align-items: center; padding: 4px 0 4px; box-sizing: border-box; flex: none" aria-hidden="true">'
            f'<div style="width: 10px; height: 10px; border-radius: 6px; border: 2.5px solid {th["ink2"]}; box-sizing: border-box"></div>'
            f'<div style="flex: 1; width: 2.5px; background: {th["ink2"]}; margin: 2px 0"></div>'
            f'<div style="width: 13px; height: 13px; border-radius: 7px; background: {th["amber"]}{"; box-shadow: inset 0 0 0 1.5px #16171A" if th["name"] == "light" else ""}"></div></div>')

def route_head(origin, dest, th, size=28, h=None):
    return (f'<div style="display: flex; gap: 11px; align-items: stretch">{glyph(th, h or size + 26)}'
            f'<div style="display: flex; flex-direction: column; gap: 1px; justify-content: center">'
            f'<span style="font-size: {size * 0.54:.0f}px; font-weight: 500; color: {th["ink2"]}">{origin}</span>'
            f'<span style="font-size: {size}px; font-weight: 700; line-height: 1.05; letter-spacing: -0.2px">{dest}</span></div></div>')

ICONS = {
  'bell': '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/>',
  'share': '<path d="M12 3v12M7 8l5-5 5 5"/><path d="M5 13v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6"/>',
  'swap': '<path d="M7 4v16M3 8l4-4 4 4"/><path d="M17 20V4M13 16l4 4 4-4"/>',
  'expand': '<path d="M14 4h6v6M10 20H4v-6M20 4l-7 7M4 20l7-7"/>',
  'chev': '<path d="M9 6l6 6-6 6"/>', 'back': '<path d="M15 6l-6 6 6 6"/>', 'down': '<path d="M6 9l6 6 6-6"/>',
  'plus': '<path d="M12 5v14M5 12h14"/>', 'minus': '<path d="M5 12h14"/>', 'check': '<path d="M5 12l5 5 9-10"/>',
  'x': '<path d="M6 6l12 12M18 6L6 18"/>',
  'radar': '<circle cx="12" cy="12" r="2"/><path d="M16.2 7.8a6 6 0 0 1 0 8.4M7.8 16.2a6 6 0 0 1 0-8.4M19 5a10 10 0 0 1 0 14M5 19A10 10 0 0 1 5 5"/>',
  'route': '<circle cx="7" cy="5" r="2.4"/><path d="M7 7.5v4a4 4 0 0 0 4 4h2a4 4 0 0 1 4 4"/><circle cx="17" cy="20" r="1.6" fill="currentColor"/>',
  'sliders': '<path d="M4 7h10M18 7h2M4 17h4M12 17h8"/><circle cx="16" cy="7" r="2"/><circle cx="10" cy="17" r="2"/>',
  'lanes': '<path d="M3 6h9M8 12h12M3 18h7"/><path d="M14 6h2M14 18h6" opacity=".5"/>',
  'pair': '<path d="M4 9h13l-4-4M20 15H7l4 4"/>',
  'wall': '<rect x="3" y="5" width="8" height="14" rx="2"/><rect x="13" y="5" width="8" height="14" rx="2"/><path d="M3 12h18"/>',
  'walk': '<circle cx="13" cy="4" r="2"/><path d="M10 21l2-6 3 3v3M8 11l3-3 3 1 2 3h3M11 8l-1 6"/>',
  'train': '<rect x="5" y="3" width="14" height="14" rx="3"/><path d="M5 11h14M9 21l-2 0M8 17l-2 4M16 17l2 4"/><circle cx="9" cy="14" r=".6" fill="currentColor"/><circle cx="15" cy="14" r=".6" fill="currentColor"/>',
  'moon': '<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/>',
  'sun': '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
  'pin': '<path d="M9 3h6l-1 6 3 3H7l3-3zM12 12v9"/>',
  'loc': '<path d="M3 11l18-8-8 18-2-8z"/>',
  'ext': '<path d="M7 17L17 7M9 7h8v8"/>',
  'refresh': '<path d="M20 11a8 8 0 0 0-14.6-4.6L4 8M4 4v4h4M4 13a8 8 0 0 0 14.6 4.6L20 16M20 20v-4h-4"/>',
}
def icon(name, size=16, sw=2.2, color='currentColor'):
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="{color}" stroke-width="{sw}" '
            f'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="flex: none">{ICONS[name]}</svg>')

def glass_btn(th, inner, w=36, h=36, label=''):
    pad = '' if w else 'padding: 0 13px;'
    width = f'width: {w}px;' if w else ''
    return (f'<span style="{width} height: {h}px; {pad} border-radius: {h / 2}px; border: 1px solid {th["glassline"]}; background: {th["glass"]}; '
            f'color: {th["ink"]}; display: inline-flex; align-items: center; justify-content: center; gap: 6px; font: 600 14px {SANS}; box-sizing: border-box; flex: none; white-space: nowrap" '
            f'aria-label="{label}">{inner}</span>')

def track_rule(label, th, extra=''):
    sl = th['sleeper'] if th['name'] == 'light' else '#3A3631'
    rail = th['rail']
    return (f'<div style="display: flex; align-items: center; gap: 10px; {extra}">{caps(label, th)}'
            f'<div style="flex: 1; height: 12px; position: relative; background: repeating-linear-gradient(90deg, {sl} 0 4px, transparent 4px 13px)">'
            f'<div style="position: absolute; left: 0; right: 0; top: 3px; height: 2px; background: {rail}"></div>'
            f'<div style="position: absolute; left: 0; right: 0; bottom: 3px; height: 2px; background: {rail}"></div></div></div>')

def time_track(th, width, deps, span=200, scale=1.0):
    """The Tableau time track. deps: list of (scheduled, delay|'X', is_next)."""
    k = width / span
    s = scale
    sh, shh = 14 * s, 18 * s
    cy = 12 * s + 4
    out = []
    for m in range(0, span + 1, 10):
        hour = (NOW + m) % 60 == 0
        hh = shh if hour else sh
        x = min(max(m * k, 1.5), width - 1.5)
        out.append(f'<rect x="{x - 1.5 * s:.1f}" y="{cy - hh / 2:.1f}" width="{3 * s:.1f}" height="{hh:.1f}" rx="1" fill="{th["sleeperH"] if hour else th["sleeper"]}"/>')
        if hour:
            lab = f'{((NOW + m) // 60) % 24}h'
            anchor = 'end' if x > width - 12 else 'middle'
            out.append(f'<text x="{x:.1f}" y="{cy + shh / 2 + 11 * s:.1f}" text-anchor="{anchor}" font-family="JetBrains Mono, monospace" font-size="{9 * s:.1f}" font-weight="500" fill="{th["ink2"]}">{lab}</text>')
    gap = 7.4 * s / 2
    for dy in (-gap, gap):
        out.append(f'<rect x="0" y="{cy + dy - 0.8 * s:.1f}" width="{width}" height="{1.6 * s:.1f}" fill="{th["rail"]}"/>')
    for t, d, nxt in deps:
        m0 = mins(t) - NOW
        if d == 'X':
            if m0 > span: continue
            x = m0 * k
            out.append(f'<circle cx="{x:.1f}" cy="{cy}" r="{4.6 * s:.1f}" fill="{th["card"]}" stroke="{th["gstop"]}" stroke-width="{1.6 * s:.1f}"/>'
                       f'<path d="M{x - 2 * s:.1f} {cy - 2 * s:.1f}l{4 * s:.1f} {4 * s:.1f}M{x + 2 * s:.1f} {cy - 2 * s:.1f}l{-4 * s:.1f} {4 * s:.1f}" stroke="{th["gstop"]}" stroke-width="{1.4 * s:.1f}" stroke-linecap="round"/>')
            continue
        m1 = m0 + (d or 0)
        if m1 > span: continue
        x1 = m1 * k
        if d:
            x0 = m0 * k
            gcol = th['gcau'] if d < 20 else th['gstop']
            out.append(f'<path d="M{x0:.1f} {cy - 3 * s:.1f} Q{(x0 + x1) / 2:.1f} {cy - 19 * s:.1f} {x1:.1f} {cy - 3 * s:.1f}" fill="none" stroke="{gcol}" stroke-width="{1.3 * s:.1f}" stroke-dasharray="2 2"/>'
                       f'<circle cx="{x0:.1f}" cy="{cy}" r="{3.2 * s:.1f}" fill="{th["card"]}" stroke="{gcol}" stroke-width="{1.3 * s:.1f}"/>')
            col = th['mdel'] if d < 20 else th['msev']
            out.append(f'<circle cx="{x1:.1f}" cy="{cy}" r="{5 * s:.1f}" fill="{col}"/>')
        elif nxt:
            out.append(f'<circle cx="{x1:.1f}" cy="{cy}" r="{5.5 * s:.1f}" fill="{th["amber"]}" stroke="{th["ring"]}" stroke-width="{2 * s:.1f}"/>')
        else:
            out.append(f'<circle cx="{x1:.1f}" cy="{cy}" r="{5 * s:.1f}" fill="{th["ink"]}"/>')
    h = cy + shh / 2 + 14 * s
    return f'<svg width="{width}" height="{h:.0f}" viewBox="0 0 {width} {h:.0f}" role="img" aria-label="Time track, next 200 minutes" style="display: block; overflow: visible">{"".join(out)}</svg>'

# ---------------------------------------------------------------- chrome
def status_bar(th, kind, left=38):
    ink = th['ink']
    icons = (f'<span style="display: inline-flex; gap: 6px; align-items: center">'
             f'<svg width="18" height="11" viewBox="0 0 18 11"><g fill="{ink}"><rect x="0" y="7" width="3" height="4" rx="1"/><rect x="5" y="5" width="3" height="6" rx="1"/><rect x="10" y="2.5" width="3" height="8.5" rx="1"/><rect x="15" y="0" width="3" height="11" rx="1"/></g></svg>'
             f'<svg width="16" height="11" viewBox="0 0 16 11"><path d="M8 10.5l2.2-2.6a3.4 3.4 0 0 0-4.4 0zM3.4 5.4a7 7 0 0 1 9.2 0l1.4-1.6a9.2 9.2 0 0 0-12 0z" fill="{ink}"/></svg>'
             f'<svg width="26" height="12" viewBox="0 0 26 12"><rect x="0.5" y="0.5" width="22" height="11" rx="3.4" fill="none" stroke="{ink}" opacity=".4"/><rect x="2" y="2" width="16" height="8" rx="2" fill="{ink}"/><rect x="23.6" y="4" width="1.6" height="4" rx=".8" fill="{ink}" opacity=".4"/></svg></span>')
    if kind == 'outer':
        return (f'<div style="position: absolute; left: 0; right: 0; top: 0; height: 54px; color: {ink}">'
                f'<span style="position: absolute; left: 0; width: 170px; top: 19px; text-align: center; font: 600 17px {SANS}">17:40</span>'
                f'<span style="position: absolute; left: {OUT_W / 2 - 63}px; top: 11px; width: 126px; height: 37px; border-radius: 19px; background: #000"></span>'
                f'<span style="position: absolute; right: 30px; top: 21px">{icons}</span></div>')
    w = IN_W if kind == 'inner' else 669
    return (f'<div style="position: absolute; left: 0; width: {w}px; top: 0; height: 30px; color: {ink}">'
            f'<span style="position: absolute; left: {left}px; top: 8px; font: 600 15px {SANS}">17:40</span>'
            f'<span style="position: absolute; right: 38px; top: 9px">{icons}</span></div>')

def home_indicator(th, x_center, y):
    col = th['ink']
    return f'<span style="position: absolute; left: {x_center - 70}px; top: {y}px; width: 140px; height: 5px; border-radius: 3px; background: {col}; opacity: .55"></span>'

def tab_bar(th, active, x_center, y, items=None, w=300):
    items = items or [('radar', 'Near me'), ('route', 'Journeys'), ('sliders', 'Settings')]
    n = len(items)
    cells = []
    for ic, lab in items:
        on = lab == active
        col = (th['amber'] if th['name'] == 'dark' else th['ink']) if on else th['ink2']
        bg = f'background: {th["tabsel"]};' if on else ''
        cells.append(f'<span style="flex: 1; height: 48px; border-radius: 24px; {bg} display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 2px; color: {col}">'
                     f'{icon(ic, 20, 2)}<span style="font: 600 10px {SANS}">{lab}</span></span>')
    return (f'<div style="position: absolute; left: {x_center - w / 2}px; top: {y}px; width: {w}px; height: 58px; box-sizing: border-box; padding: 5px; border-radius: 29px; '
            f'background: {th["glass"]}; border: 1px solid {th["glassline"]}; box-shadow: 0 10px 28px rgba(0,0,0,{0.45 if th["name"] == "dark" else 0.12}); '
            f'backdrop-filter: blur(18px); display: flex; gap: 2px">{"".join(cells)}</div>')

def fade(th, x, w, y, h):
    return f'<div style="position: absolute; left: {x}px; width: {w}px; top: {y}px; height: {h}px; background: linear-gradient(180deg, transparent, {th["ground"]} 70%); pointer-events: none"></div>'

def device(kind, th, content):
    """A simple device frame at real point size. kind: outer | inner | tabletop."""
    bez = 11
    if kind == 'outer':
        w, h = OUT_W, OUT_H
        rad = 'border-radius: 8px 59px 59px 8px'
        frad = 'border-radius: 16px 68px 68px 16px'
        spine = (f'<div style="position: absolute; left: -9px; top: 26px; bottom: 26px; width: 9px; border-radius: 5px 0 0 5px; '
                 f'background: repeating-linear-gradient(180deg, #2A2C30 0 14px, #1B1C1F 14px 16px)" title="spine (hinge)"></div>')
        marks = ''
    else:
        if kind == 'inner':
            w, h = IN_W, IN_H
        else:
            w, h = 669, IN_W
        rad = 'border-radius: 55px'
        frad = 'border-radius: 64px'
        spine = ''
        if kind == 'inner':
            marks = (f'<div style="position: absolute; left: {bez + HINGE - 1}px; top: -7px; width: 2px; height: 9px; background: #8F8D86"></div>'
                     f'<div style="position: absolute; left: {bez + HINGE - 1}px; bottom: -7px; width: 2px; height: 9px; background: #8F8D86"></div>')
        else:
            marks = (f'<div style="position: absolute; top: {bez + HINGE - 1}px; left: -7px; height: 2px; width: 9px; background: #8F8D86"></div>'
                     f'<div style="position: absolute; top: {bez + HINGE - 1}px; right: -7px; height: 2px; width: 9px; background: #8F8D86"></div>')
    if kind == 'inner':
        crease = (f'<div style="position: absolute; left: {L_END}px; width: {2 * KEEP}px; top: 0; bottom: 0; '
                  f'background: linear-gradient(90deg, transparent, {th["crease"]} 40%, {th["crease"]} 60%, transparent); pointer-events: none"></div>'
                  f'<div style="position: absolute; left: {HINGE - 0.5}px; width: 1px; top: 0; bottom: 0; background: {th["creaseline"]}; pointer-events: none"></div>')
    elif kind == 'tabletop':
        crease = (f'<div style="position: absolute; top: {L_END}px; height: {2 * KEEP}px; left: 0; right: 0; '
                  f'background: linear-gradient(180deg, transparent, {th["crease"]} 40%, {th["crease"]} 60%, transparent); pointer-events: none"></div>'
                  f'<div style="position: absolute; top: {HINGE - 0.5}px; height: 1px; left: 0; right: 0; background: {th["creaseline"]}; pointer-events: none"></div>')
    else:
        crease = ''
    return (f'<div style="position: relative; flex: none; width: {w + 2 * bez}px; height: {h + 2 * bez}px; background: #050506; {frad}; '
            f'box-shadow: 0 30px 60px rgba(22,23,26,0.30), inset 0 0 0 1.5px #2A2C30">{spine}{marks}'
            f'<div class="screen" data-kind="{kind}" style="position: absolute; left: {bez}px; top: {bez}px; width: {w}px; height: {h}px; {rad}; overflow: hidden; '
            f'background: {th["ground"]}; color: {th["ink"]}; font-family: {SANS}">{content}{crease}</div></div>')

# ---------------------------------------------------------------- shared rows
def status_cell(st, th, dep):
    kind = st[0]
    if kind == 'next':
        return f'<span style="display: flex; align-items: center; gap: 7px">{tag("NEXT", th)}<span style="{mono(13.5, 700, th["clear"])}">{st[1]}</span></span>'
    if kind == 'late':
        d = st[1]
        col = th['cau'] if d < 20 else th['stop']
        return (f'<span style="display: flex; flex-direction: column; align-items: flex-end; gap: 3px">{late_pill(d, th)}'
                f'<span style="{mono(11, 500, col)}">leaves {hhmm(mins(dep) + d)}</span></span>')
    if kind == 'canc':
        return canc_pill(th)
    return f'<span style="{mono(13, 500, th["ink2"])}">{st[1]}</span>'

def journey_row(r, th, selected=False, compact=False, pad=16, show_dur=False, num=True):
    dep, arr, _num, dur, st = r
    canc = st[0] == 'canc'
    tstyle = next_time_style(th, 20) if st[0] == 'next' else mono(20, 700, th['ink2'] if canc else th['time'])
    strike = 'text-decoration: line-through; text-decoration-thickness: 1.5px;' if canc else ''
    op = 'opacity: 0.6;' if canc else ''
    selstyle = (f'background: {th["sel"]}; box-shadow: inset 3px 0 0 {th["amber"]};' if selected else '')
    h = 50 if st[0] == 'late' else 46
    durbar = ''
    if show_dur:
        mm = int(dur.split()[0]) if not canc else 0
        durbar = (f'<span style="display: flex; align-items: center; gap: 6px; width: 92px">'
                  f'<span style="width: {mm * 1.6:.0f}px; height: 3px; border-radius: 2px; background: {th["ink2"]}; opacity: {0 if canc else .8}"></span>'
                  f'<span style="{mono(11, 500, th["ink2"])}">{"—" if canc else dur}</span></span>')
    return (f'<div style="display: flex; align-items: center; gap: 12px; height: {h}px; padding: 0 {pad}px; border-top: 1px solid {th["hair"]}; {selstyle}">'
            f'<span style="display: flex; align-items: baseline; gap: 8px; {op}"><span style="{tstyle}; {strike}">{dep}</span>'
            f'<span style="width: 14px; border-top: 1.5px dashed {th["dash"]}; align-self: center"></span>'
            f'<span style="{mono(14.5, 500, th["ink2"] if canc else th["ink3"])}; {strike}">{arr}</span></span>'
            + (f'<span style="display: flex; align-items: center; gap: 5px; {op}">{chip("TER", th)}<span style="{mono(11.5, 500, th["ink2"])}">{r[2]}</span></span>' if num else (f'<span style="{op}">{chip("TER", th)}</span>' if num is None else ''))
            + f'{durbar}<span style="margin-left: auto">{status_cell(st, th, dep)}</span></div>')

def station_row(r, th, selected=False, pad=16, name_w=None, swatch=True):
    t, d = r['t'], r['d']
    m = mins(t) - NOW
    canc = d == 'X'
    is_next = m == 6
    if is_next:
        tst = next_time_style(th, 19)
    else:
        tst = mono(19, 700, th['ink2'] if canc else th['time'])
    strike = 'text-decoration: line-through; text-decoration-thickness: 1.5px;' if canc else ''
    if canc:
        right = canc_pill(th, 10.5)
    elif d:
        col = th['cau'] if d < 20 else th['stop']
        right = (f'<span style="display: flex; align-items: center; gap: 6px"><span style="{mono(11, 500, col)}">leaves {hhmm(mins(t) + d)}</span>{late_pill(d, th, 12)}</span>')
    else:
        right = f'<span style="{mono(13, 600 if m <= 10 else 500, th["clear"] if m <= 10 else th["ink2"])}">{"in " if m <= 10 else ""}{m} min</span>'
    sw = (f'<span style="width: 3px; height: 26px; border-radius: 2px; background: {th[r["side"]]}; flex: none"></span>' if swatch else '')
    selstyle = (f'background: {th["sel"]}; box-shadow: inset 3px 0 0 {th["amber"]};' if selected else '')
    via = LINES[r['line']].get('via')
    sub = f'TER {r["num"]}' + (f' · {via}' if via else '')
    return (f'<div style="display: flex; align-items: center; gap: 10px; height: 46px; padding: 0 {pad}px; border-top: 1px solid {th["hair"]}; {selstyle}">'
            f'{sw}<span style="{tst}; {strike} flex: none">{t}</span>'
            f'<span style="display: flex; flex-direction: column; min-width: 0; flex: 1; {"opacity: .6;" if canc else ""}">'
            f'<span style="font-size: 15.5px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; {strike}">{r["name"]}</span>'
            f'<span style="{mono(10.5, 500, th["ink2"])}; white-space: nowrap">{sub}</span></span>'
            f'<span style="flex: none">{right}</span></div>')

def journey_track_deps():
    out = []
    for dep, arr, num, dur, st in JOURNEY:
        d = 'X' if st[0] == 'canc' else (st[1] if st[0] == 'late' else 0)
        out.append((dep, d, st[0] == 'next'))
    return out

def station_track_deps():
    return [(r['t'], r['d'], mins(r['t']) - NOW == 6) for r in station_departures()]

def hero_journey(th, width, flap=(36, 52, 34), track=True, bell=False):
    """Flap hero of a journey board: next time, NEXT TRAIN · ARRIVES, chip + N° + duration, in 2 min, time track."""
    w, h, fs = flap
    inner = width - 28
    b = (f'<span style="margin-left: auto; align-self: flex-start">{glass_btn(th, icon("bell", 17), w=40, h=40, label="Remind me")}</span>' if bell else '')
    tr = f'<div style="margin-top: 14px">{time_track(th, inner, journey_track_deps())}</div>' if track else ''
    return (f'<div style="background: {th["card"]}; border: 1px solid {th["hair"]}; border-radius: 22px; padding: 14px; box-sizing: border-box; width: {width}px">'
            f'<div style="display: flex; align-items: center; gap: 14px">{flaps("17:42", th, w, h, fs)}'
            f'<div style="display: flex; flex-direction: column; gap: 5px">{caps("NEXT TRAIN · ARRIVES 18:07", th, 10)}'
            f'<span style="display: flex; gap: 6px; align-items: center">{chip("TER", th)}<span style="{mono(12, 500, th["ink2"])}">N° 17653 · 25 min</span></span>'
            f'<span style="{mono(15, 700, th["clear"])}">in 2 min</span></div>{b}</div>{tr}</div>')

def hero_station(th, width, flap=(34, 50, 32), track=True, header=True):
    inner = width - 28
    hd = (f'<div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 10px">'
          f'<span style="display: flex; align-items: baseline; gap: 8px">{caps("NEAREST STATION", th, 10)}'
          f'<span style="font-size: 17px; font-weight: 700">Voiron</span><span style="{mono(11, 500, th["ink2"])}">400 m</span></span>'
          f'<span style="display: flex; align-items: center; gap: 5px; {mono(10.5, 500, th["ink2"])}"><span style="width: 6px; height: 6px; border-radius: 3px; background: {th["clear"]}"></span>17:40</span></div>') if header else ''
    tr = f'<div style="margin-top: 12px">{time_track(th, inner, station_track_deps())}</div>' if track else ''
    return (f'<div style="background: {th["card"]}; border: 1px solid {th["hair"]}; border-radius: 22px; padding: 13px 14px 12px; box-sizing: border-box; width: {width}px">{hd}'
            f'<div style="display: flex; align-items: center; gap: 14px">{flaps("17:46", th, *flap)}'
            f'<div style="display: flex; flex-direction: column; gap: 4px; min-width: 0">'
            f'<span style="font-size: 20px; font-weight: 700; line-height: 1.1">Grenoble</span>'
            f'<span style="display: flex; gap: 6px; align-items: center">{chip("TER", th)}<span style="{mono(12, 500, th["ink2"])}">N° 17613</span></span>'
            f'<span style="{mono(15, 700, th["clear"])}">in 6 min</span></div></div>{tr}</div>')

def abs_div(x, y, w, inner, h=None, extra=''):
    hh = f' height: {h}px;' if h is not None else ''
    return f'<div style="position: absolute; left: {x}px; top: {y}px; width: {w}px;{hh} {extra}">{inner}</div>'

# ================================================================ 1. FOLDED
def folded_nearme(th):
    W = OUT_W
    rows = station_departures()[1:9]
    body = [status_bar(th, 'outer')]
    body.append(abs_div(20, 58, W - 40, f'<div style="display: flex; align-items: center; justify-content: space-between">'
                f'<span style="font-size: 30px; font-weight: 700; letter-spacing: -0.3px">Near me</span>'
                f'{glass_btn(th, icon("loc", 14) + "Find me!", w=0, h=36, label="Find me")}</div>'))
    body.append(abs_div(16, 104, W - 32, hero_station(th, W - 32, track=False)))
    body.append(abs_div(20, 242, W - 40, track_rule('THEN', th)))
    body.append(abs_div(0, 262, W, ''.join(station_row(r, th, pad=20) for r in rows)))
    body.append(fade(th, 0, W, 560, 118))
    body.append(tab_bar(th, 'Near me', W / 2, 598, w=290))
    body.append(home_indicator(th, W / 2, OUT_H - 9))
    return device('outer', th, ''.join(body))

def folded_journey(th):
    W = OUT_W
    body = [status_bar(th, 'outer')]
    body.append(abs_div(12, 56, W - 24, f'<div style="display: flex; align-items: center; justify-content: space-between">'
                f'{glass_btn(th, icon("back", 15, 2.6) + "Journeys", w=0, h=34)}'
                f'<span style="display: flex; gap: 8px">{glass_btn(th, icon("pair", 16), label="Round trip")}{glass_btn(th, icon("swap", 16), label="Swap direction")}</span></div>'))
    body.append(abs_div(20, 100, W - 40, f'<div style="display: flex; align-items: center; justify-content: space-between">'
                f'{route_head("Grenoble", "Voiron", th, 28)}'
                f'<span style="display: flex; flex-direction: column; align-items: flex-end; gap: 6px">{chip("DIRECT ONLY", th, 10)}{chip("REVERSES AT 13:00", th, 10)}</span></div>'))
    body.append(abs_div(16, 166, W - 32, hero_journey(th, W - 32, bell=True)))
    rows = ''.join(journey_row(r, th, pad=20, show_dur=False) for r in JOURNEY)
    body.append(abs_div(0, 334, W, rows))
    body.append(fade(th, 0, W, 560, 118))
    body.append(tab_bar(th, 'Journeys', W / 2, 598, w=290))
    body.append(home_indicator(th, W / 2, OUT_H - 9))
    return device('outer', th, ''.join(body))

# ================================================================ 2. UNFOLDED
LX0, LX1 = 20, L_END - 16           # left half content (no rail)
RX0, RX1 = R_START + 16, IN_W - 26  # right half content

def inspector(th, x0, x1, y0=40, close=True, actions=True, H=None):
    H = H or IN_H
    w = x1 - x0
    stops = [  # time, was, name, role, solid
        ('18:24', '18:12', 'Grenoble', 'YOU BOARD', True, 'board'),
        ('18:31', None, 'Saint-Égrève–St-Robert', '', True, 'mid'),
        ('18:40', None, 'Moirans', '', True, 'mid'),
        ('18:48', '18:36', 'Voiron', 'YOU GET OFF · 24 MIN', True, 'off'),
        ('18:54', None, 'Rives', '', False, 'mid'),
        ('19:14', None, 'La Tour-du-Pin', '', False, 'mid'),
        ('19:25', None, 'Bourgoin-Jallieu', '', False, 'mid'),
        ('19:53', None, 'Lyon Part-Dieu', '', False, 'end'),
    ]
    rows = []
    n = len(stops)
    svg = []
    cys, y = [], 12
    for st in stops:
        cys.append(y); y += 44 if (st[1] or st[3]) else 31
    for i, (t, was, name, role, solid, kind) in enumerate(stops):
        cy = cys[i]
        pitch = (cys[i + 1] - cy) if i < n - 1 else 0
        if i < n - 1:
            nxt_solid = stops[i + 1][4]
            seg_solid = solid and nxt_solid
            col = th['ink'] if seg_solid else th['ink2']
            dash = '' if seg_solid else ' stroke-dasharray="3 4" opacity="0.6"'
            svg.append(f'<path d="M8 {cy} V{cy + pitch}" stroke="{col}" stroke-width="3"{dash}/>')
        if kind == 'board':
            svg.append(f'<circle cx="8" cy="{cy}" r="6" fill="{th["card"]}" stroke="{th["ink"]}" stroke-width="2.6"/>')
        elif kind == 'off':
            svg.append(f'<circle cx="8" cy="{cy}" r="7" fill="{th["amber"]}" stroke="{th["ring"]}" stroke-width="2"/>')
        else:
            svg.append(f'<circle cx="8" cy="{cy}" r="4" fill="{th["card"] if not solid else th["ink"]}" stroke="{th["ink"] if solid else th["ink2"]}" stroke-width="2" opacity="{1 if solid else .6}"/>')
        dim = '' if solid else 'opacity: .55;'
        col = th['cau'] if was else (th['ink'] if solid else th['ink2'])
        tcell = (f'<span style="display: flex; flex-direction: column; width: 50px; flex: none"><span style="{mono(14, 700, col)}">{t}</span>'
                 + (f'<span style="{mono(10.5, 500, th["ink2"])}; text-decoration: line-through">{was}</span>' if was else '') + '</span>')
        rl = (f'<span style="{mono(9.5, 700, th["amber"] if (kind == "off" and th["name"] == "dark") else th["ink2"], 1.2)}">{role}</span>' if role else '')
        weight = 700 if role else 500
        rows.append(f'<div style="position: absolute; left: 26px; right: 0; top: {cy - 9}px; display: flex; gap: 10px; align-items: flex-start; {dim}">{tcell}'
                    f'<span style="display: flex; flex-direction: column; gap: 1px"><span style="font-size: 14.5px; font-weight: {weight}; line-height: 18px">{name}</span>{rl}</span></div>')
    stop_h = cys[-1] + 18
    pattern = (f'<div style="position: relative; height: {stop_h}px"><svg width="16" height="{stop_h}" style="position: absolute; left: 0; top: 0">{"".join(svg)}</svg>{"".join(rows)}</div>')
    tile = lambda lab, val, sub='', fill=None, fg=None: (
        f'<div style="flex: 1; background: {fill or th["raised"]}; border-radius: 14px; padding: 9px 12px; display: flex; flex-direction: column; gap: 3px">'
        f'{caps(lab, th, 9.5, fg or th["ink2"], 1.3)}<span style="{mono(20, 700, fg or th["ink"])}">{val}</span>'
        + (f'<span style="{mono(10.5, 500, fg or th["ink2"])}; text-decoration: line-through; opacity: .8">{sub}</span>' if sub else '') + '</div>')
    head = (f'<div style="display: flex; align-items: center; justify-content: space-between">{caps("TRAIN", th, 10.5, None, 1.8)}'
            + (glass_btn(th, icon("x", 14, 2.4), w=30, h=30, label="Close") if close else '') + '</div>'
            f'<div style="display: flex; flex-wrap: wrap; align-items: baseline; gap: 2px 10px; margin-top: 2px"><span style="{mono(28, 800)}; white-space: nowrap">N° 17655</span>{chip("TER", th, 11)}'
            f'<span style="font-size: 15px; color: {th["ink2"]}; margin-left: 4px; white-space: nowrap">to Lyon Part-Dieu</span></div>')
    tiles = (f'<div style="display: flex; gap: 8px; margin-top: 12px">{tile("LEAVES", "18:24", "18:12", None, None)}'
             f'{tile("YOU ARRIVE", "18:48", "18:36")}{tile("DELAY", "+12", "", th["caubg"], th["cau"])}</div>')
    acts = ((f'<div style="display: flex; gap: 8px">'
            f'<span style="flex: 1; height: 44px; border-radius: 14px; background: {th["amber"]}; color: #0E0F11; display: flex; align-items: center; justify-content: center; gap: 7px; font: 700 15px {SANS}">{icon("bell", 16, 2.4)}Watch train</span>'
            f'<span style="flex: 1; height: 44px; border-radius: 14px; background: {th["raised"]}; display: flex; align-items: center; justify-content: center; gap: 7px; font: 600 15px {SANS}">{icon("share", 16)}Share ETA</span></div>') if actions else '') + (
            f'<div style="display: flex; flex-direction: column; align-items: center; gap: 4px; margin-top: 10px">'
            f'<span style="font: 600 13px {SANS}; color: {th["amber"] if th["name"] == "dark" else th["ink"]}; display: inline-flex; gap: 4px; align-items: center; white-space: nowrap">Tickets &amp; details in SNCF Connect{icon("ext", 13, 2.4)}</span>'
            f'<span style="font-size: 10.5px; color: {th["ink2"]}; text-align: center">Not affiliated with SNCF. Train data © SNCF, via the SNCF open data API.</span></div>')
    return (abs_div(x0, y0, w, head + tiles + f'<div style="margin-top: 16px">{track_rule("STOPS", th)}</div>'
                    f'<div style="margin-top: 14px">{pattern}</div>')
            + abs_div(x0, H - 40 - (98 if actions else 46), w, acts))

def journey_left(th, x0, x1, selected=1, top=36):
    w = x1 - x0
    hdr = (f'<div style="display: flex; align-items: center; justify-content: space-between">'
           f'{glass_btn(th, icon("back", 15, 2.6) + "Journeys", w=0, h=32)}'
           f'<span style="display: flex; gap: 7px">{glass_btn(th, icon("pair", 15) + "Round trip", w=0, h=32, label="Round trip")}{glass_btn(th, icon("swap", 15), w=32, h=32, label="Swap direction")}</span></div>'
           f'<div style="display: flex; align-items: flex-end; justify-content: space-between; margin-top: 10px">{route_head("Grenoble", "Voiron", th, 28)}'
           f'<span style="display: flex; flex-direction: column; align-items: flex-end; gap: 5px">{chip("DIRECT ONLY", th, 9.5)}{chip("REVERSES AT 13:00", th, 9.5)}</span></div>')
    out = [abs_div(x0, top, w, hdr)]
    out.append(abs_div(x0 - 4, top + 104, w + 8, hero_journey(th, w + 8)))
    rows = ''.join(journey_row(r, th, selected=(i == selected), pad=16) for i, r in enumerate(JOURNEY))
    out.append(abs_div(x0 - 16, top + 262, w + 32, rows))
    return ''.join(out)

def unfolded_journey(th):
    body = [status_bar(th, 'inner')]
    body.append(journey_left(th, LX0, LX1))
    body.append(fade(th, 0, L_END, 560, 110))
    body.append(tab_bar(th, 'Journeys', L_END / 2, IN_H - 74, w=270))
    # the inspector card on the right half
    body.append(f'<div style="position: absolute; left: {R_START + 4}px; top: 30px; width: {IN_W - R_START - 18}px; bottom: 22px; border-radius: 28px 46px 46px 28px; background: {th["card"]}; border: 1px solid {th["hair"]}"></div>')
    body.append(inspector(th, RX0 + 8, RX1 - 8, 44))
    body.append(home_indicator(th, HINGE, IN_H - 9))
    return device('inner', th, ''.join(body))

# ---- round trip
OUT_ROWS = [
  ('17:16', '17:41', '17650', 'departed', 'gone'),
  ('17:46', '18:11', '17652', '25 min', 'pick'),
  ('18:16', '18:41', '17654', '25 min', 'late12'),
  ('18:46', '19:11', '17656', '', 'canc'),
  ('19:16', '19:41', '17658', '25 min', 'wait:1 h 36'),
  ('19:46', '20:11', '17660', '25 min', 'wait:2 h 06'),
]
BACK_ROWS = [
  ('20:06', '20:31', '17661', '', 'early'),
  ('20:42', '21:07', '17663', 'on time', 'fits'),
  ('21:12', '21:37', '17665', '25 min', 'more:+30 there'),
  ('21:42', '22:07', '17667', '25 min', 'more:+1 h there'),
  ('22:42', '23:07', '17669', '25 min', 'last'),
]
def rt_row(r, th, first=False):
    dep, arr, num, dur, kind = r
    top = '' if first else f'border-top: 1px solid {th["hair"]};'
    dim = kind in ('gone', 'early')
    canc = kind == 'canc'
    h = 40 if dim else 58
    sel = (f'background: {th["sel"]}; box-shadow: inset 0 0 0 1.5px {th["selring"]}, inset 3px 0 0 {th["amber"]};' if kind in ('pick', 'fits') else '')
    tcol = th['ink2'] if (dim or canc) else th['time']
    strike = 'text-decoration: line-through;' if canc else ''
    ts = next_time_style(th, 21) if kind == 'pick' else f'{mono(19 if dim else 21, 700, tcol)}; {strike}'
    sh = '0 4px 12px rgba(0,0,0,0.35)' if th['name'] == 'dark' else '0 4px 12px rgba(22,23,26,0.16)'
    paper = f'background: {th["paper"]}; color: {th["papertext"]}; box-shadow: {sh}'
    left = (f'<div style="display: flex; flex-direction: column; gap: 3px; {"opacity: .45;" if dim else ("opacity: .6;" if canc else "")}">'
            + (f'<div style="display: flex; align-items: center; gap: 8px"><span style="{mono(21, 700)}; {paper}; margin-left: -14px; padding: 3px 9px 3px 14px; border-radius: 0 14px 14px 0">{dep}</span>' if kind == 'fits' else
               f'<div style="display: flex; align-items: baseline; gap: 8px"><span style="{ts}">{dep}</span>')
            + f'<span style="width: 16px; border-top: 1.5px dashed {th["dash"]}; align-self: center"></span>'
            f'<span style="{mono(14, 500, th["ink2"] if (dim or canc) else th["ink3"])}; {strike}">{arr}</span></div>'
            + ('' if dim else f'<span style="{mono(11, 500, th["ink2"])}">TER {num}{(" · " + dur) if dur else ""}'
                 + (f' · <span style="color: {th["clear"]}; font-weight: 700">in 6 min</span>' if kind == 'pick' else '') + '</span>') + '</div>')
    if kind == 'pick':
        right = (f'<span style="display: flex; align-items: center; gap: 7px; margin-right: -14px; padding: 6px 12px 6px 10px; border-radius: 14px 0 0 14px; {paper}; {mono(11.5, 700, None, 0.4)}; white-space: nowrap">'
                 f'<span style="width: 18px; height: 18px; border-radius: 9px; background: {th["amber"]}; color: #0E0F11; display: flex; align-items: center; justify-content: center">{icon("check", 11, 3.4)}</span>2 h 31 THERE</span>')
    elif kind == 'late12':
        right = f'<span style="display: flex; flex-direction: column; align-items: flex-end; gap: 3px">{late_pill(12, th)}<span style="{mono(11, 500, th["cau"])}">leaves 18:28</span></span>'
    elif kind == 'canc':
        right = canc_pill(th)
    elif kind == 'gone':
        right = caps('DEPARTED', th, 10, None, 1)
    elif kind == 'early':
        right = caps('TOO EARLY', th, 10, None, 1)
    elif kind == 'fits':
        right = tag('FIRST THAT FITS', th)
    elif kind == 'last':
        right = tag('LAST TRAIN', th, filled=False)
    else:
        right = f'<span style="{mono(12.5, 500, th["ink2"])}">{kind.split(":", 1)[1]}</span>'
    return (f'<div style="display: flex; align-items: center; justify-content: space-between; height: {h}px; padding: 0 14px; {top} {sel}">{left}{right}</div>')

def rt_list(rows, th):
    return (f'<div style="background: {th["card"]}; border: 1px solid {th["hair"]}; border-radius: 20px; overflow: hidden">'
            + ''.join(rt_row(r, th, i == 0) for i, r in enumerate(rows)) + '</div>')

def unfolded_roundtrip(th):
    body = [status_bar(th, 'inner')]
    acc = th['amber'] if th['name'] == 'dark' else th['ink']
    lw, rw = LX1 - LX0, RX1 - RX0
    # left: outbound
    body.append(abs_div(LX0, 36, lw, f'<div style="display: flex; align-items: center; justify-content: space-between">'
                f'<span style="{mono(12, 700, acc, 1.8)}">① OUTBOUND</span>'
                f'<span style="display: flex; gap: 7px">{glass_btn(th, "Today " + icon("down", 13, 2.6), w=0, h=32)}{glass_btn(th, "Done", w=0, h=32)}</span></div>'
                f'<div style="margin-top: 8px">{route_head("Voiron", "Grenoble", th, 26)}</div>'))
    # right: way back
    body.append(abs_div(RX0, 36, rw, f'<div style="display: flex; align-items: center; justify-content: space-between">'
                f'<span style="{mono(12, 700, acc, 1.8)}">② WAY BACK</span>'
                f'{glass_btn(th, icon("share", 15), w=32, h=32, label="Share the plan")}</div>'
                f'<div style="margin-top: 8px">{route_head("Grenoble", "Voiron", th, 26)}</div>'))
    # lists, aligned so the two picked rows share one baseline
    ly = 150
    body.append(abs_div(LX0, ly, lw, rt_list(OUT_ROWS[:5], th)))
    body.append(abs_div(RX0, ly, rw, rt_list(BACK_ROWS, th)))
    # the pairing: two paper half-pills, the dashes are the only thing that crosses the crease
    py = ly + 40 + 29  # centre of the picked rows
    pt = th['papertext']
    body.append(f'<div style="position: absolute; left: {LX1}px; width: {RX0 - LX1}px; top: {py - 1}px; height: 0; border-top: 2px dashed {th["paper"]}; opacity: .9"></div>')
    # whole day out (left, above the tab bar)
    day = (f'<div style="display: flex; flex-direction: column; gap: 6px; padding: 11px 14px; border-radius: 18px; background: {th["card"]}; border: 1px solid {th["hair"]}">'
           f'{caps("THE WHOLE DAY OUT", th, 10)}'
           f'<svg width="{lw - 28}" height="32" viewBox="0 0 {lw - 28} 32" role="img" aria-label="17:46 to 18:11 on the train, 2 h 31 in Grenoble, 20:42 to 21:07 back">'
           f'<rect x="0" y="12" width="{lw - 28}" height="9" rx="4.5" fill="{th["raised"]}"/>'
           f'<rect x="0" y="12" width="40" height="9" rx="4.5" fill="{th["amber"]}"/><rect x="{lw - 68}" y="12" width="40" height="9" rx="4.5" fill="{th["amber"]}"/>'
           f'<text x="0" y="8" font-family="JetBrains Mono" font-size="10" font-weight="600" fill="{th["ink2"]}">17:46</text>'
           f'<text x="{(lw - 28) / 2}" y="8" text-anchor="middle" font-family="JetBrains Mono" font-size="10" font-weight="700" fill="{th["ink"]}">2 h 31 IN GRENOBLE</text>'
           f'<text x="{lw - 28}" y="8" text-anchor="end" font-family="JetBrains Mono" font-size="10" font-weight="600" fill="{th["ink2"]}">21:07</text>'
           f'<text x="0" y="31" font-family="JetBrains Mono" font-size="9.5" fill="{th["ink2"]}">25 min</text>'
           f'<text x="{lw - 28}" y="31" text-anchor="end" font-family="JetBrains Mono" font-size="9.5" fill="{th["ink2"]}">25 min</text></svg></div>')
    body.append(abs_div(LX0, 478, lw, day))
    body.append(tab_bar(th, 'Journeys', L_END / 2, IN_H - 74, w=270))
    # stay stepper + watch both (right)
    step = (f'<div style="display: flex; align-items: center; justify-content: space-between; padding: 9px 10px 9px 16px; border-radius: 18px; background: {th["card"]}; border: 1px solid {th["hair"]}">'
            f'<span style="display: flex; flex-direction: column; gap: 1px">{caps("STAY AT LEAST", th, 10)}<span style="{mono(22, 700)}">2 h 30</span></span>'
            f'<span style="display: flex; gap: 6px">'
            + ''.join(f'<span style="width: 42px; height: 42px; border-radius: 21px; background: {th["raised"]}; display: flex; align-items: center; justify-content: center">{icon(i, 16, 2.6)}</span>' for i in ('minus', 'plus'))
            + '</span></div>')
    watch = (f'<div style="display: flex; flex-direction: column; gap: 6px; margin-top: 10px">'
             f'<span style="height: 48px; border-radius: 16px; background: {th["amber"]}; color: #0E0F11; display: flex; align-items: center; justify-content: center; gap: 8px; font: 700 16px {SANS}">{icon("bell", 17, 2.4)}Watch both trains</span>'
             f'<span style="font-size: 11px; color: {th["ink2"]}; text-align: center">If the 20:42 is cancelled or late, you get the next one that fits.</span></div>')
    body.append(abs_div(RX0, 478, rw, step + watch))
    body.append(home_indicator(th, HINGE, IN_H - 9))
    return device('inner', th, ''.join(body)), py

def pairing_pills(th, py, x_off=11, y_off=11):
    """Drawn over the device (in frame coordinates) so they sit on top of the cards."""
    pt, pp = th['papertext'], th['paper']
    sh = '0 6px 16px rgba(0,0,0,0.40)' if th['name'] == 'dark' else '0 6px 16px rgba(22,23,26,0.20)'
    st = f'position: absolute; top: {y_off + py - 13}px; height: 26px; display: flex; align-items: center; gap: 6px; padding: 0 10px; background: {pp}; color: {pt}; box-shadow: {sh}; {mono(11.5, 700, pt, 0.4)}; white-space: nowrap'
    left = f'<div style="{st}; right: calc(100% - {x_off + L_END - 2}px); border-radius: 13px 4px 4px 13px">ARR 18:11</div>'
    right = f'<div style="{st}; left: {x_off + R_START + 2}px; border-radius: 4px 13px 13px 4px">20:42 BACK</div>'
    return left + right

# ---- station
def river(th, x0, y0, w, h, sel=('gre', 2), span=120, axis_y=236):
    """Voiron's horizontal river (StationLines B) re-laid for one half: terminus above the lane end, times on the lane."""
    lane_x0 = 92
    lane_x1 = w - 8
    tx0 = lane_x0 + 14
    k = (lane_x1 - 18 - tx0) / span
    X = lambda t: tx0 + (mins(t) - NOW) * k
    src_x, src_w = 6, 22
    pitch = 98
    ys = {'lyon': 56, 'sag': 56 + pitch, 'ugg': axis_y + 60, 'gre': axis_y + 60 + 90, 'val': axis_y + 60 + 180}
    src_cy = axis_y
    svg, html = [], []
    # grid + now
    for m in range(0, span + 1, 30):
        x = tx0 + m * k
        if m:
            svg.append(f'<path d="M{x:.1f} 20 V{h - 26}" stroke="{th["grid"]}" stroke-width="1"/>')
    svg.append(f'<path d="M{tx0:.1f} 18 V{h - 24}" stroke="{th["ink2"]}" stroke-width="1" stroke-dasharray="2 3" opacity=".7"/>')
    html.append(f'<span style="position: absolute; left: {tx0 - 34}px; top: {axis_y - 9}px; {mono(9.5, 700, th["ground"] if th["name"] == "dark" else th["card"])}; background: {th["ink"]}; padding: 2px 5px; border-radius: 4px">NOW 17:40</span>')
    for m in (x_ for x_ in (20, 50, 80, 110) if x_ < span):
        x = tx0 + m * k
        html.append(f'<span style="position: absolute; left: {x - 20}px; width: 40px; text-align: center; top: {axis_y - 7}px; {mono(9.5, 500, th["ink2"])}">{hhmm(NOW + m)}</span>')
    html.append(caps('WEST · TOWARDS LYON', th, 9, None, 1.2).replace('<span style="', f'<span style="position: absolute; left: 0; top: 4px; '))
    html.append(caps('EAST · TOWARDS GRENOBLE', th, 9, None, 1.2).replace('<span style="', f'<span style="position: absolute; left: 0; top: {h - 16}px; '))
    # source
    order = ['lyon', 'sag', 'ugg', 'gre', 'val']
    offs = {k_: (i - 2) * 6 for i, k_ in enumerate(order)}
    for kk in order:
        L = LINES[kk]
        col = th[L['side']]
        y = ys[kk]
        sy = src_cy + offs[kk]
        svg.append(f'<path d="M{src_x + src_w - 4} {sy} C{lane_x0 - 34} {sy} {lane_x0 - 50} {y} {lane_x0} {y} H{lane_x1}" fill="none" stroke="{col}" stroke-width="6" stroke-linecap="round"/>')
        svg.append(f'<path d="M{lane_x1} {y - 11} V{y + 11}" stroke="{col}" stroke-width="4.5" stroke-linecap="round"/>')
        # terminus label, above the lane end
        nm = L.get('short', L['name']) if kk == 'ugg' else L['name']
        html.append(f'<span style="position: absolute; right: {w - lane_x1}px; top: {y - 31}px; font-size: 14.5px; font-weight: 700; white-space: nowrap">{nm}</span>')
        # trains
        slots = {'b1': [], 'a1': [], 'b2': []}
        name_x0 = lane_x1 - len(nm) * 7.6 - 8
        for i, (t, d) in enumerate(L['trains']):
            m0 = mins(t) - NOW
            if m0 > span: continue
            xs = X(t)
            nxt = i == 0
            if d == 'X':
                svg.append(f'<circle cx="{xs:.1f}" cy="{y}" r="6.5" fill="{th["ground"]}" stroke="{th["gstop"]}" stroke-width="2"/>'
                           f'<path d="M{xs - 3:.1f} {y - 3}l6 6M{xs + 3:.1f} {y - 3}l-6 6" stroke="{th["gstop"]}" stroke-width="1.8" stroke-linecap="round"/>')
                lab = (f'<span style="{mono(11.5, 600, th["stop"])}; text-decoration: line-through">{t}</span>{pill("CANC.", th["stop"], th["stopbg"], 9.5, "1px 4px")}', 80, xs)
            elif d:
                xr = X(hhmm(mins(t) + d))
                gcol = th['gcau'] if d < 20 else th['gstop']
                mcol = th['mdel'] if d < 20 else th['msev']
                svg.append(f'<path d="M{xs:.1f} {y - 4} Q{(xs + xr) / 2:.1f} {y - 22} {xr:.1f} {y - 4}" fill="none" stroke="{gcol}" stroke-width="1.4" stroke-dasharray="2 2"/>'
                           f'<circle cx="{xs:.1f}" cy="{y}" r="3.6" fill="{th["ground"]}" stroke="{gcol}" stroke-width="1.5"/>'
                           f'<circle cx="{xr:.1f}" cy="{y}" r="6" fill="{mcol}" stroke="{th["ring"]}" stroke-width="1.5"/>')
                if sel == (kk, i):
                    svg.append(f'<circle cx="{xr:.1f}" cy="{y}" r="11" fill="none" stroke="{th["amber"]}" stroke-width="2.5"/>')
                lab = (f'<span style="{mono(11.5, 700, th["cau"] if d < 20 else th["stop"])}">{hhmm(mins(t) + d)}</span>{late_pill(d, th, 9.5)}', 74, xr)
            else:
                if nxt:
                    svg.append(f'<circle cx="{xs:.1f}" cy="{y}" r="7.5" fill="{th["amber"]}" stroke="{th["ring"]}" stroke-width="2.5"/>')
                    mm = m0
                    ins = f'<span style="{mono(11, 700, th["clear"] if mm <= 10 else th["ink"])}">in {mm}′</span>'
                    lab = (f'<span style="{mono(11.5, 700, "#0E0F11")}; background: {th["amber"]}; padding: 1px 4px; border-radius: 5px">{t}</span>{ins}', 82, xs + 30)
                else:
                    svg.append(f'<circle cx="{xs:.1f}" cy="{y}" r="5.5" fill="{th["ground"]}" stroke="{th["ink"] if th["name"] == "light" else th["ink3"]}" stroke-width="2.5"/>')
                    lab = (f'<span style="{mono(11.5, 600, th["ink"])}">{t}</span>', 38, xs)
            inner, lw, cx = lab
            lx0 = cx - lw / 2
            lx1 = cx + lw / 2
            if nxt:
                lx0 = xs - 10; lx1 = lx0 + lw
            placed = None
            for slot in ('b1', 'a1', 'b2'):
                if slot == 'a1' and lx1 > name_x0 - 4:
                    continue
                if all(lx1 + 4 < a or lx0 - 4 > b for a, b in slots[slot]):
                    placed = slot; break
            placed = placed or 'b2'
            slots[placed].append((lx0, lx1))
            ty = {'b1': y + 10, 'a1': y - 28, 'b2': y + 28}[placed]
            html.append(f'<span style="position: absolute; left: {lx0:.1f}px; top: {ty}px; width: {lw}px; display: flex; gap: 4px; align-items: center; justify-content: {"flex-start" if nxt else "center"}; white-space: nowrap">{inner}</span>')
    # source pill
    svg.append(f'<rect x="{src_x}" y="{src_cy - 32}" width="{src_w}" height="64" rx="11" fill="{th["amber"]}"/>')
    html.append(f'<span style="position: absolute; left: {src_x}px; width: {src_w}px; top: {src_cy - 32}px; height: 64px; display: flex; align-items: center; justify-content: center; writing-mode: vertical-rl; transform: rotate(180deg); {mono(8.5, 800, "#0E0F11", 1.2)}">VOIRON</span>')
    return (f'<div style="position: absolute; left: {x0}px; top: {y0}px; width: {w}px; height: {h}px">'
            f'<svg width="{w}" height="{h}" style="position: absolute; left: 0; top: 0; overflow: visible">{"".join(svg)}</svg>{"".join(html)}</div>')

def unfolded_station(th):
    body = [status_bar(th, 'inner')]
    lw = LX1 - LX0
    body.append(abs_div(LX0, 36, lw, f'<div style="display: flex; align-items: center; justify-content: space-between">'
                f'<span style="font-size: 28px; font-weight: 700; letter-spacing: -0.3px">Near me</span>'
                f'{glass_btn(th, icon("loc", 14) + "Find me!", w=0, h=34, label="Find me")}</div>'))
    body.append(abs_div(LX0 - 4, 82, lw + 8, hero_station(th, lw + 8, track=False)))
    body.append(abs_div(LX0, 222, lw, track_rule('THEN', th)))
    rows = station_departures()[1:10]
    body.append(abs_div(LX0 - 16, 242, lw + 32, ''.join(station_row(r, th, selected=(r['t'] == '18:16'), pad=16) for r in rows)))
    body.append(fade(th, 0, L_END, 560, 110))
    body.append(tab_bar(th, 'Near me', L_END / 2, IN_H - 74, w=270))
    rw = RX1 - RX0
    body.append(abs_div(RX0, 36, rw, f'<div style="display: flex; align-items: center; justify-content: space-between">'
                f'<span style="display: flex; flex-direction: column; gap: 2px">{caps("LINES FROM VOIRON", th, 10)}'
                f'<span style="{mono(10.5, 500, th["ink2"])}">5 directions · next 2 h</span></span>'
                f'<span style="display: flex; border-radius: 10px; background: {th["raised"]}; padding: 3px">'
                f'<span style="padding: 5px 9px; border-radius: 7px; background: {th["card"]}; {mono(10.5, 700, th["ink"], 1)}; white-space: nowrap">NEXT 2 H</span>'
                f'<span style="padding: 5px 9px; {mono(10.5, 600, th["ink2"], 1)}">TONIGHT</span></span></div>'))
    body.append(river(th, RX0 - 4, 92, rw + 10, 528))
    body.append(abs_div(RX0, IN_H - 34, rw, f'<div style="display: flex; justify-content: space-between; {mono(9.5, 500, th["ink2"])}">'
                f'<span>Tap a train or a terminus</span><span>Data © SNCF · not affiliated</span></div>'))
    body.append(home_indicator(th, HINGE, IN_H - 9))
    return device('inner', th, ''.join(body))

# ---- journeys home + lanes (the navigation comparison)
JLIST = [
  dict(o='Grenoble', d='Voiron', rule='REVERSES 13:00', sum='2 DISRUPTED · 25 MIN', sumc='cau', nxt='17:42',
       bars=[('17:42', '18:07', 0, 'next', 0), ('18:12', '18:36', 12, 'late', 1), ('18:42', '19:08', 0, 'canc', 0), ('19:12', '19:37', 0, 'ok', 1), ('19:42', '20:07', 24, 'late', 0)]),
  dict(o='Grenoble', d='Lyon Part-Dieu', rule='ALWAYS THIS WAY', sum='1 DELAYED · 1 H 17', sumc='cau', nxt='17:47',
       bars=[('17:47', '19:04', 0, 'next', 0), ('18:47', '20:04', 15, 'late', 1), ('19:47', '21:04', 0, 'ok', 0)]),
  dict(o='Grenoble', d='Chambéry', rule='ALWAYS THIS WAY', sum='EVERY TRAIN CANCELLED', sumc='stop', nxt=None, bars='hazard'),
  dict(o='Voiron', d='Valence Ville', rule='FOLLOWS YOU', sum='FOLLOWS YOU · 1 H 10', sumc='ink2', nxt='18:16',
       bars=[('18:16', '19:26', 0, 'next', 0), ('19:16', '20:26', 0, 'ok', 1)]),
]
LANE_T0, LANE_SPAN = NOW - 10, 150   # 17:30 -> 20:00

def lane_track(th, j, x0, w, h):
    k = w / LANE_SPAN
    X = lambda m: (m - LANE_T0) * k
    out = []
    nowx = X(NOW)
    out.append(f'<div style="position: absolute; left: 0; top: 0; width: {nowx}px; height: {h}px; background: {th["past"]}"></div>')
    if j['bars'] == 'hazard':
        out.append(f'<div style="position: absolute; left: 0; right: 0; top: 14px; height: {h - 28}px; border-radius: 12px; '
                   f'background: repeating-linear-gradient(-45deg, {th["hatch"]} 0 10px, transparent 10px 20px)"></div>'
                   f'<div style="position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); display: flex; flex-direction: column; align-items: center; gap: 2px; '
                   f'background: #0E0F11; padding: 7px 14px; border-radius: 9px"><span style="{mono(12, 800, th["amber"], 1.6)}">NO SERVICE</span>'
                   f'<span style="{mono(9.5, 500, "#B5B2AA")}">6 trains cancelled until 21:20</span></div>')
        return ''.join(out)
    sub_y = (14, 50)
    bh = 28
    for dep, arr, d, kind, sub in j['bars']:
        m0, m1 = mins(dep), mins(arr)
        y = sub_y[sub]
        if d:
            # ghost at the timetabled slot
            gx0, gx1 = X(m0), min(X(m1), w)
            if gx0 < w:
                out.append(f'<div style="position: absolute; left: {gx0:.1f}px; width: {gx1 - gx0:.1f}px; top: {y}px; height: {bh}px; box-sizing: border-box; border-radius: 7px; border: 1.5px dashed {th["gcau"] if d < 20 else th["gstop"]}; opacity: .55"></div>')
            m0 += d; m1 += d
        x0b, x1b = X(m0), X(m1)
        if x0b >= w:
            # the real bar slid out of the window: say so at the edge
            out.append(f'<span style="position: absolute; right: 0; top: {y + 6}px">{late_pill(d, th, 10)}</span>')
            continue
        x1c = min(x1b, w)
        clip = x1b > w
        if x1c - x0b < 44:
            continue  # ponytail: a sliver at the window edge says nothing; the range picker shows it
        rad = '7px 0 0 7px' if clip else '7px'
        label = dep if not d else hhmm(m0)
        if kind == 'next':
            st = f'background: {th["amber"]}; box-shadow: inset 0 0 0 1.5px #16171A; color: #0E0F11'
            txt = f'<span style="{mono(11, 700)}">{label}</span>' + (f'<span style="{mono(8.5, 800, None, 1)}">NEXT</span>' if x1c - x0b > 96 else '')
        elif kind == 'late':
            fg = th['cau'] if d < 20 else th['stop']
            # opaque, so the ghost's outline never shows through the real bar
            bg = ({'dark': '#352318', 'light': '#FBE3CC'} if d < 20 else {'dark': '#351B19', 'light': '#F8D9D4'})[th['name']]
            st = f'background: {bg}; box-shadow: inset 0 0 0 1.5px {fg}; color: {fg}'
            txt = f'<span style="{mono(11, 700)}">{label}</span><span style="{mono(9.5, 700)}">+{d}</span>'
        elif kind == 'canc':
            st = (f'background: repeating-linear-gradient(-45deg, {th["stopbg"]} 0 4px, transparent 4px 8px); border: 1.5px dashed {th["stop"]}; color: {th["stop"]}; box-sizing: border-box')
            txt = f'<span style="{mono(11, 600)}; text-decoration: line-through">{label}</span>' + (f'<span style="{mono(8.5, 700, None, .8)}">CANC.</span>' if x1c - x0b > 96 else '')
        else:
            st = f'background: {th["barink"]}; color: {th["barinktext"]}'
            txt = f'<span style="{mono(11, 700)}">{label}</span>'
        out.append(f'<div style="position: absolute; left: {x0b:.1f}px; width: {x1c - x0b:.1f}px; top: {y}px; height: {bh}px; border-radius: {rad}; {st}; '
                   f'display: flex; align-items: center; gap: 6px; padding: 0 7px; box-sizing: border-box; overflow: hidden; white-space: nowrap">{txt}</div>')
    return ''.join(out)

def journey_card(th, j, w, h, selected=False):
    acc_t = (f'<span style="{next_time_style(th, 20)}">{j["nxt"]}</span>' if j['nxt'] else
             f'<span style="{mono(10.5, 800, th["amber"], 1.4)}; background: #0E0F11; padding: 5px 8px; border-radius: 6px">NO SERVICE</span>')
    sel = (f'background: {th["sel"]}; box-shadow: inset 0 0 0 1.5px {th["selring"]}, inset 3px 0 0 {th["amber"]};' if selected else f'background: {th["card"]};')
    return (f'<div style="height: {h}px; box-sizing: border-box; border-radius: 18px; border: 1px solid {th["hair"]}; {sel} padding: 12px 14px; display: flex; flex-direction: column; justify-content: space-between">'
            f'<div style="display: flex; align-items: center; justify-content: space-between; gap: 8px">{route_head(j["o"], j["d"], th, 20, 40)}<span style="flex: none">{acc_t}</span></div>'
            f'<div style="display: flex; justify-content: space-between; align-items: center">{caps(j["rule"], th, 9.5, None, 1.2)}'
            f'<span style="{mono(9.5, 600, th[j["sumc"]], 1)}">{j["sum"] if j["sumc"] != "ink2" else "1 H 10 ON BOARD"}</span></div></div>')

def journeys_home(th, nav):
    rail_w = 68 if nav == 'B' else 0
    body = []
    if nav == 'B':
        body.append(rail(th, 'Journeys'))
    body.append(status_bar(th, 'inner', 38 + rail_w))
    x0 = LX0 + rail_w
    lw = LX1 - x0
    head = (f'<div style="display: flex; align-items: center; justify-content: space-between">'
            f'<span style="font-size: 28px; font-weight: 700; letter-spacing: -0.3px">Journeys</span>'
            f'<span style="display: flex; gap: 7px">{glass_btn(th, "Edit", w=0, h=32)}{glass_btn(th, icon("plus", 15, 2.6), w=32, h=32, label="Add a journey")}</span></div>')
    body.append(abs_div(x0, 36, lw, head))
    lane_top, lane_h, gap = 128, 92, 10
    for i, j in enumerate(JLIST):
        y = lane_top + i * (lane_h + gap)
        body.append(abs_div(x0, y, lw, journey_card(th, j, lw, lane_h, selected=(i == 0))))
    # right half: the lanes, row-aligned with the cards
    rw = RX1 - RX0
    k = rw / LANE_SPAN
    axis = []
    for m in (NOW, 18 * 60, 18 * 60 + 30, 19 * 60, 19 * 60 + 30):
        x = (m - LANE_T0) * k
        if m == NOW:
            axis.append(f'<span style="position: absolute; left: {x - 32}px; top: 0; {mono(9.5, 700, th["papertext"] if th["name"] == "dark" else "#16171A")}; background: {th["paper"] if th["name"] == "dark" else th["amber"]}; padding: 2px 5px; border-radius: 4px">NOW 17:40</span>')
        else:
            axis.append(f'<span style="position: absolute; left: {x - 20}px; width: 40px; text-align: center; top: 2px; {mono(9.5, 500, th["ink2"])}">{hhmm(m)}</span>')
    rhead = (f'<div style="display: flex; align-items: center; justify-content: space-between">'
             f'<span style="display: flex; flex-direction: column; gap: 2px">{caps("LANES", th, 10.5, th["ink"], 1.8)}<span style="{mono(10.5, 500, th["ink2"])}; white-space: nowrap">departure → arrival</span></span>'
             f'<span style="display: flex; border-radius: 10px; background: {th["raised"]}; padding: 3px">'
             f'<span style="padding: 5px 9px; border-radius: 7px; background: {th["card"]}; {mono(10.5, 700, th["ink"], 1)}; white-space: nowrap">NEXT 2 H</span>'
             f'<span style="padding: 5px 9px; {mono(10.5, 600, th["ink2"], 1)}">TONIGHT</span>'
             f'</span></div>')
    body.append(abs_div(RX0, 36, rw, rhead))
    body.append(abs_div(RX0, 100, rw, ''.join(axis), h=18, extra='position: absolute'))
    grid = ''.join(f'<div style="position: absolute; left: {RX0 + (m - LANE_T0) * k:.1f}px; top: 120px; width: 1px; height: {4 * (lane_h + gap)}px; background: {th["grid"]}"></div>' for m in (18 * 60, 18 * 60 + 30, 19 * 60, 19 * 60 + 30))
    body.append(grid)
    body.append(f'<div style="position: absolute; left: {RX0 + (NOW - LANE_T0) * k:.1f}px; top: 120px; height: {4 * (lane_h + gap)}px; border-left: 1.5px dashed {th["ink2"]}; opacity: .7"></div>')
    for i, j in enumerate(JLIST):
        y = lane_top + i * (lane_h + gap)
        selbg = f'background: {th["sel"]};' if i == 0 else ''
        body.append(f'<div style="position: absolute; left: {RX0 - 8}px; width: {rw + 16}px; top: {y}px; height: {lane_h}px; border-radius: 14px; {selbg}"></div>')
        body.append(abs_div(RX0, y, rw, lane_track(th, j, RX0, rw, lane_h), h=lane_h, extra='position: absolute; overflow: hidden'))
    # legend
    leg = (f'<div style="display: flex; gap: 14px; align-items: center; white-space: nowrap; {mono(9.5, 500, th["ink2"])}">'
           f'<span style="display: inline-flex; gap: 4px; align-items: center"><span style="width: 16px; height: 9px; border-radius: 3px; background: {th["amber"]}"></span>next</span>'
           f'<span style="display: inline-flex; gap: 4px; align-items: center"><span style="width: 16px; height: 9px; border-radius: 3px; background: {th["barink"]}"></span>on time</span>'
           f'<span style="display: inline-flex; gap: 4px; align-items: center"><span style="width: 16px; height: 9px; border-radius: 3px; background: {th["caubg"]}; box-shadow: inset 0 0 0 1.5px {th["cau"]}"></span>late</span>'
           f'<span style="display: inline-flex; gap: 4px; align-items: center"><span style="width: 16px; height: 9px; border-radius: 3px; border: 1.2px dashed {th["ink2"]}; box-sizing: border-box"></span>timetabled</span>'
           f'<span style="display: inline-flex; gap: 4px; align-items: center"><span style="width: 16px; height: 9px; border-radius: 3px; border: 1.2px dashed {th["stop"]}; background: {th["stopbg"]}; box-sizing: border-box"></span>cancelled</span></div>')
    body.append(abs_div(RX0, IN_H - 50, rw, leg))
    if nav == 'A':
        body.append(fade(th, 0, L_END, 560, 110))
        body.append(tab_bar(th, 'Journeys', L_END / 2, IN_H - 74, w=270))
    body.append(home_indicator(th, HINGE, IN_H - 9))
    return device('inner', th, ''.join(body))

def rail(th, active):
    items = [('radar', 'NEAR ME'), ('route', 'JOURNEYS'), ('lanes', 'LANES'), ('pair', 'ROUND\nTRIP'), ('wall', 'WALL')]
    out = []
    y = 44
    for ic, lab in items:
        on = lab.replace('\n', ' ').lower() == active.lower()
        col = (th['amber'] if th['name'] == 'dark' else th['ink']) if on else th['ink2']
        bg = f'background: {th["sel"]}; box-shadow: inset 3px 0 0 {th["amber"]};' if on else ''
        out.append(f'<div style="position: absolute; left: 0; top: {y}px; width: 68px; height: 62px; {bg} display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 4px; color: {col}">'
                   f'{icon(ic, 21, 2)}<span style="{mono(8.5, 700, None, .8)}; text-align: center; line-height: 1.15; white-space: pre">{lab}</span></div>')
        y += 68
    on = active == 'Settings'
    out.append(f'<div style="position: absolute; left: 0; top: {IN_H - 92}px; width: 68px; height: 56px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 4px; color: {th["ink2"]}">'
               f'{icon("sliders", 21, 2)}<span style="{mono(8.5, 700, None, .8)}">SETTINGS</span></div>')
    out.append(f'<div style="position: absolute; left: 22px; top: {IN_H - 132}px; display: flex; align-items: center; gap: 4px; {mono(9, 500, th["ink2"])}"><span style="width: 6px; height: 6px; border-radius: 3px; background: {th["clear"]}"></span>17:40</div>')
    return (f'<div style="position: absolute; left: 0; top: 0; width: 68px; height: {IN_H}px; border-right: 1px solid {th["hair"]}; background: {th["card"] if th["name"] == "light" else "#121316"}">{"".join(out)}</div>')

# ================================================================ 3. TABLETOP
def tabletop(th):
    W, H = 669, IN_W
    body = []  # Wall hides the status bar
    dark = th['name'] == 'dark'
    ground_top = th['wall']
    body.append(f'<div style="position: absolute; left: 0; top: 0; width: {W}px; height: {L_END}px; background: {ground_top}"></div>')
    # upper half: the desk clock
    head = (f'<div style="display: flex; align-items: flex-start; justify-content: space-between">'
            f'<div style="display: flex; flex-direction: column; gap: 4px">{caps("→ DEPARTURES · YOUR JOURNEY", th, 11, None, 2)}'
            f'<span style="font-size: 40px; font-weight: 800; letter-spacing: -0.8px; line-height: 1.05">Grenoble → Voiron</span></div>'
            f'<div style="display: flex; flex-direction: column; align-items: flex-end; gap: 6px">'
            f'{flaps("17:40", th, 34, 48, 32, 3, digit=th["clockdigit"], bg="#23262B" if dark else "#16171A", colon=th["ink2"])}'
            f'{caps("FRI 16 OCT", th, 10, None, 1.6)}</div></div>')
    body.append(abs_div(30, 40, W - 60, head))
    leave = (f'<div style="width: 300px; height: 236px; box-sizing: border-box; border-radius: 26px; background: #F5C04F; color: #0E0F11; padding: 18px 20px; display: flex; flex-direction: column; justify-content: space-between">'
             f'<span style="{mono(12, 800, "#0E0F11", 2.2)}">LEAVE HOME IN</span>'
             f'<div style="display: flex; align-items: flex-end; gap: 12px">{flaps("38", th, 70, 100, 70, 6, digit="#FFC23D", bg="#0E0F11")}'
             f'<span style="{mono(13, 800, "#0E0F11", 1.6)}; padding-bottom: 6px">MIN</span></div>'
             f'<div style="display: flex; flex-direction: column; gap: 3px; {mono(13, 600, "#0E0F11")}">'
             f'<span style="display: flex; gap: 6px; align-items: center">{icon("train", 15, 2.2)}the 18:24 · TER 17655, +12</span>'
             f'<span style="display: flex; gap: 6px; align-items: center">{icon("walk", 15, 2.2)}6 min walk to the platform</span></div></div>')
    nxt = (f'<div style="flex: 1; height: 236px; box-sizing: border-box; border-radius: 26px; background: {th["card"]}; border: 1px solid {th["hair"]}; padding: 18px 20px; display: flex; flex-direction: column; justify-content: space-between">'
           f'{caps("NEXT TRAIN", th, 11, None, 2)}'
           f'<div>{flaps("17:42", th, 44, 64, 42, 4)}</div>'
           f'<div style="display: flex; flex-direction: column; gap: 4px"><span style="display: flex; gap: 6px; align-items: center">{chip("TER", th)}<span style="{mono(12, 500, th["ink2"])}">N° 17653 · arr. 18:07</span></span>'
           f'<span style="{mono(15, 700, th["clear"])}">in 2 min · too tight to walk</span></div></div>')
    body.append(abs_div(30, 140, W - 60, f'<div style="display: flex; gap: 14px">{leave}{nxt}</div>'))
    body.append(abs_div(30, 398, W - 60, time_track(th, W - 60, journey_track_deps(), scale=1.15)))
    # lower half: the next trains + controls (it lies on the table, so big targets and one glance per row)
    rows = []
    for i, (dep, arr, num, dur, st) in enumerate(JOURNEY[:5]):
        canc = st[0] == 'canc'
        target = i == 1
        digits = flaps(dep, th, 24, 36, 23, 3, digit=(th['ink2'] if canc else None), bg=(th['raised'] if canc else None))
        if st[0] == 'next':
            right = f'<span style="{mono(15, 700, th["clear"])}">2 min</span>'
        elif st[0] == 'late':
            d = st[1]
            right = f'<span style="display: flex; align-items: center; gap: 8px"><span style="{mono(11.5, 500, th["cau"] if d < 20 else th["stop"])}">leaves {hhmm(mins(dep) + d)}</span>{late_pill(d, th, 13)}</span>'
        elif canc:
            right = canc_pill(th)
        else:
            right = f'<span style="{mono(14, 500, th["ink2"])}">{st[1]}</span>'
        sel = f'background: {th["sel"]}; box-shadow: inset 3px 0 0 {th["amber"]};' if target else ''
        mark = (f'<span style="{mono(9, 800, "#0E0F11", 1.2)}; background: {th["amber"]}; padding: 2px 5px; border-radius: 4px; margin-left: 6px">YOUR TRAIN</span>' if target else '')
        rows.append(f'<div style="display: flex; align-items: center; gap: 16px; height: 56px; padding: 0 30px; border-top: 1px solid {th["hair"]}; {sel}">{digits}'
                    f'<span style="display: flex; flex-direction: column; {"opacity: .6;" if canc else ""}"><span style="font-size: 18px; font-weight: 700; {"text-decoration: line-through;" if canc else ""}">Voiron{mark}</span>'
                    f'<span style="{mono(11, 500, th["ink2"])}">arrives {arr} · TER {num}</span></span><span style="margin-left: auto">{right}</span></div>')
    body.append(abs_div(0, R_START + 14, W, ''.join(rows)))
    ctrl = (f'<div style="display: flex; align-items: center; gap: 10px">'
            f'{glass_btn(th, icon("route", 16) + "Grenoble → Voiron" + icon("down", 13, 2.6), w=0, h=44)}'
            f'{glass_btn(th, icon("walk", 16) + "6 min" + icon("down", 13, 2.6), w=0, h=44, label="Walking time")}'
            f'<span style="margin-left: auto; display: flex; gap: 10px">{glass_btn(th, icon("sun", 18), w=44, h=44, label="Keep the screen awake")}'
            f'{glass_btn(th, icon("x", 16, 2.4), w=44, h=44, label="Leave Wall mode")}</span></div>')
    body.append(abs_div(30, H - 88, W - 60, ctrl))
    tick = (f'<div style="display: flex; align-items: center; gap: 12px; height: 26px; {mono(11.5, 500, th["ink"])}">'
            f'<span style="flex: none; padding: 4px 10px; border-radius: 6px; background: repeating-linear-gradient(-45deg, {th["amber"]} 0 6px, #0E0F11 6px 12px)">'
            f'<span style="display: block; {mono(10, 800, th["amber"], 1.4)}; background: #0E0F11; padding: 2px 6px; border-radius: 4px">INFO</span></span>'
            f'<span style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis">18:42 cancelled · 19:42 runs 24 min late · Chambéry: no service</span></div>')
    body.append(abs_div(30, H - 128, W - 60, tick))
    body.append(home_indicator(th, W / 2, H - 9))
    return device('tabletop', th, ''.join(body))

# ================================================================ pages
def posture_icon(kind):
    s = '#3A3631'
    if kind == 'folded':
        g = f'<rect x="14" y="4" width="20" height="32" rx="4" fill="none" stroke="{s}" stroke-width="2"/><path d="M14 8v24" stroke="{s}" stroke-width="4"/>'
    elif kind == 'flat':
        g = f'<rect x="4" y="8" width="40" height="26" rx="4" fill="none" stroke="{s}" stroke-width="2"/><path d="M24 8v26" stroke="{s}" stroke-width="1.5" stroke-dasharray="2 2"/>'
    else:
        g = f'<path d="M8 36h22M8 36l14-26" stroke="{s}" stroke-width="3" stroke-linecap="round" fill="none"/><path d="M4 38h40" stroke="#A9A69E" stroke-width="1.5"/>'
    return f'<svg width="48" height="40" viewBox="0 0 48 40" aria-hidden="true">{g}</svg>'

def caption_block(eyebrow, title, posture, reused, moved, why, width=None):
    w = f'max-width: {width}px;' if width else ''
    return (f'<header style="display: flex; gap: 28px; align-items: flex-start; {w}">'
            f'<div style="flex: 0 0 300px; display: flex; gap: 12px; align-items: flex-start">{posture_icon(posture)}<div>'
            f'<div style="{mono(11.5, 700, "#66645E", 1.6)}">{eyebrow}</div><h2 style="margin: 3px 0 0; font-size: 30px; line-height: 1.1; color: #16171A">{title}</h2></div></div>'
            f'<dl style="margin: 0; flex: 1; display: grid; grid-template-columns: 76px 1fr; gap: 6px 14px; font-size: 14.5px; line-height: 1.45; color: #16171A">'
            f'<dt style="{mono(10.5, 700, "#66645E", 1.4)}; padding-top: 3px">REUSED</dt><dd style="margin: 0">{reused}</dd>'
            f'<dt style="{mono(10.5, 700, "#66645E", 1.4)}; padding-top: 3px">MOVED</dt><dd style="margin: 0">{moved}</dd>'
            f'<dt style="{mono(10.5, 700, "#66645E", 1.4)}; padding-top: 3px">WHY</dt><dd style="margin: 0">{why}</dd></dl></header>')

def pair(fn, overlay=None):
    frames = []
    for name in ('dark', 'light'):
        th = TH[name]
        res = fn(th)
        ov = ''
        if isinstance(res, tuple):
            res, py = res
            ov = overlay(th, py)
        frames.append(f'<figure style="margin: 0; display: flex; flex-direction: column; gap: 10px"><div style="position: relative">{res}{ov}</div>'
                      f'<figcaption style="{mono(11, 600, "#66645E", 1.4)}">{"BOARD · DARK" if name == "dark" else "TIMETABLE · LIGHT"}</figcaption></figure>')
    return frames

SCREENS = []  # (slug, eyebrow, title, posture, reused, moved, why, frames_fn)

def S_(slug, eyebrow, title, posture, reused, moved, why, frames):
    SCREENS.append(dict(slug=slug, eyebrow=eyebrow, title=title, posture=posture, reused=reused, moved=moved, why=why, frames=frames))

S_('folded-nearme', '1 · FOLDED · OUTER 466×678', 'Near me, folded', 'folded',
   'The iPhone Near me tab as it is: inline “Near me” title and the glass “Find me!” capsule, the split-flap hero, the THEN track rule, the floating three-tab bar.',
   'The hero turns sideways: flaps on the left, destination, N° and “in 6 min” beside them, the station name, distance and freshness folded into one header line. Board rows keep time / destination / status on one line, with the direction swatch from the river and N° underneath.',
   'The outer screen is 64 pt wider and 196 pt shorter than an iPhone 17 Pro. Height is the scarce axis, so everything that can sit side by side does: seven departures are readable above the tab bar.',
   lambda: [f for fn in (folded_nearme,) for f in pair(fn)])
S_('folded-journey', '1 · FOLDED · OUTER 466×678', 'A journey board, folded', 'folded',
   'The Tableau journey board: route glyph header, DIRECT ONLY / REVERSES AT 13:00 chips, flap hero with the time track, rows depart ┄ arrive with NEXT, +12 “leaves 18:24”, CANCELLED and +24.',
   'The chips move from under the title to its right, the hero gains the big-screen Remind me bell in its spare width, and Round trip + Swap become toolbar buttons (they are panes once unfolded).',
   'The extra width pays for the chips and the bell without adding a row; five of the evening’s six trains are on screen above the tab bar.',
   lambda: pair(folded_journey))
S_('unfolded-journey', '2a · UNFOLDED · INNER 951×669', 'Journey: board | inspector', 'flat',
   'Station hall, minus its sidebar: route header, chips, flap hero + time track, the board rows; the inspector with N°, LEAVES / YOU ARRIVE / DELAY tiles, the STOPS rule, the stopping pattern (your leg solid, the rest dashed), Watch train, Share ETA, SNCF Connect.',
   'Board on the left half, the selected train on the right half. Selection keeps the big-screen grammar: full-width amber tint + left bar on the row. The tab bar is the iPhone one, centred on the left half; Round trip moves into the board toolbar.',
   'Each half is almost exactly an outer screen (463 vs 466 pt), so the folded board unfolds into the same column and the inspector, which the iPhone pushes as a sheet, simply opens beside it. Nothing crosses the crease: the inspector is its own card.',
   lambda: pair(unfolded_journey))
S_('unfolded-roundtrip', '2b · UNFOLDED · INNER 951×669', 'Round trip: outbound | way back', 'flat',
   'Duo.dc.html, as designed: ① OUTBOUND with the picked train ringed and checked, THE WHOLE DAY OUT bar; ② WAY BACK with TOO EARLY, FIRST THAT FITS, “+30 there”, LAST TRAIN, the STAY AT LEAST stepper and “Watch both trains”.',
   'The pairing pill is split in two paper tabs on the inner edges of the picked rows: “✓ 2 h 31 THERE” ends before the crease, the 20:42 itself starts after it, and only the dashed tie crosses. The two lists are aligned so both picked rows share one line (a departed 17:16 on the left balances TOO EARLY on the right). The stepper moves under the list.',
   'The Duo mockup was drawn for this hinge, but its pill put text on the fold. On a real crease the middle 24 pt is curved and catches light, so the tie survives and the words step aside.',
   lambda: pair(unfolded_roundtrip, lambda th, py: ''))
S_('unfolded-station', '2c · UNFOLDED · INNER 951×669', 'Station: departures | river', 'flat',
   'Near me (hero flaps, THEN, board rows) on the left; StationLines variant B on the right: the amber source, the S-curves, west above / east below the NOW axis, ghost slots with dashed arcs, the hollow ✕ for the cancelled 19:05.',
   'The river is re-laid for 463 pt: a two-hour window instead of three and a half, terminus names above the end of their lane instead of beside it, “Grenoble Universités-Gières” shortened. The list carries a 3 pt swatch in its lane colour, and the selected row (18:16 +24) rings its dot on the river.',
   'A smart split: the list answers “what leaves next”, the map answers “where and how often”. They are linked by selection, never by a line drawn across the fold.',
   lambda: pair(unfolded_station))
S_('nav-A', '2d · NAVIGATION · OPTION A (RECOMMENDED)', 'Same three tabs, left half', 'flat',
   'The iPhone’s three tabs, unchanged, in the same floating capsule. Journeys cards (route glyph, direction rule in mono caps, next time or NO SERVICE) and Lanes (bars from departure to arrival, ghosts, CANC., the hazard lane).',
   'The capsule is centred on the left half, never on the screen. Lanes is the right half of Journeys, each lane on the same row as its card, so the cards are the label column. Round trip is a button on a board, Wall is the tabletop posture.',
   'Folding and unfolding keeps you in the same tab with the same selection; there is nothing new to learn. The cost is 74 pt of height on the left half, which the fade and the scroll absorb.',
   lambda: pair(lambda th: journeys_home(th, 'A')))
S_('nav-B', '2d · NAVIGATION · OPTION B', 'A compact rail', 'flat',
   'The station-hall sidebar idea, shrunk to icons: Near me, Journeys, Lanes, Round trip, Wall, Settings, with the big-screen selection style (amber tint + left bar) and the freshness dot.',
   'The 280 pt sidebar becomes a 68 pt rail on the left edge. Every view is one tap, including Lanes and Wall; the left half keeps its full height.',
   'More discoverable and nearer the iPad, but it takes 68 pt from a 463 pt half on every screen (cards and boards get tight), and the folded app has no rail, so unfolding changes the navigation under your thumb.',
   lambda: pair(lambda th: journeys_home(th, 'B')))
S_('tabletop', '3 · TABLETOP · INNER 669×951, HINGE HORIZONTAL', 'Wall as a desk clock', 'tabletop',
   'Wall mode: ground #0A0B0C, the split-flap clock in ink digits, the amber LEAVE HOME IN card with 70×100 flaps and the train / walk glyphs, flap rows, cancelled rows with grey tiles and a struck destination, the INFO hazard ticker, and the time track at desk scale.',
   'The upper half stands up and holds what you read from across the room: clock, LEAVE HOME IN, the next train, the evening on the track. The lower half lies on the table and holds the next five trains, the ticker, and the controls (journey, walking time, keep awake, leave) where a finger lands.',
   'The hinge reports partially open, so the posture picks the mode by itself. LEAVE HOME IN skips the 17:42 (2 min, too tight on foot) and targets the late 18:24: the delay is what makes it catchable.',
   lambda: pair(tabletop))

# ---------------------------------------------------------------- geometry block
GEOMETRY = '''
<table style="border-collapse: collapse; font-size: 14px; line-height: 1.45; color: #16171A; width: 100%">
<tr><th style="text-align: left; padding: 6px 12px 6px 0; width: 210px">Item</th><th style="text-align: left; padding: 6px 12px">Value</th><th style="text-align: left; padding: 6px 0">Source</th></tr>
<tr><td>Device</td><td>iPhone Duo, <code>iPhone19,4</code>, model A3447, product class V68, iOS 27.1+, <code>IsLargeFormatPhone</code>, idiom <code>phone</code></td><td><code>iPhone Duo.simdevicetype/…/profile.plist</code>, <code>capabilities.plist</code> (/Library/Developer/CoreSimulator/Profiles/DeviceTypes)</td></tr>
<tr><td>Outer screen</td><td><b>1398×2034 px @3x = 466×678 pt</b>, 460 ppi, P3, Dynamic Island. Corner radii UL/LL <b>8</b>, UR/LR <b>59</b>: the square-ish left edge is the spine</td><td><code>capabilities.displays[0]</code> (“primary”, chrome phone15, sensor_bar_class_04); mask PDF 466×678</td></tr>
<tr><td>Inner screen</td><td><b>2007×2853 px @3x = 669×951 pt</b>, 460 ppi, corners 55 all round, no cutout in its mask. <code>nativeOrientation 270</code>: the panel is mounted rotated, so the natural unfolded view is <b>951×669 landscape</b></td><td><code>capabilities.displays[1]</code> (“primary-1”, surfaceType 2); mask PDF 1252×1780</td></tr>
<tr><td>Fold</td><td><b>Book fold, vertical, centred: x = 475.5 pt</b> on the 951-wide inner screen. Each half is 475.5 pt, i.e. an outer screen (466) plus a little. Held rotated (669×951) the fold is horizontal at y = 475.5: the tabletop posture</td><td>Derived: outer spine on the left edge, inner = 2 × outer width, panel rotation 270. <b>No hinge rectangle is published</b> by the profile or the SDK</td></tr>
<tr><td>Keep-out (assumption)</td><td>24 pt centred on the fold (463.5–487.5). One continuous panel, so it is a crease, not a gap; nothing but backgrounds and the round-trip tie cross it</td><td>Design rule of these mockups, to verify on hardware</td></tr>
<tr><td>Postures</td><td>closed (outer screen) · partially open (tabletop / book) · fully open (flat)</td><td><code>UIHinge.Status</code>: unknown, closed, partiallyOpen, fullyOpen</td></tr>
<tr><td>Hinge API, UIKit</td><td><code>UIHingeInteraction(updateHandler:)</code> added to a view → <code>Update.hinge: UIHinge?</code> (nil when the hierarchy has no hinge) → <code>status</code> + <code>angle</code> (radians, rate is system policy)</td><td><code>UIKit.framework/Headers/UIHinge.h</code>, <code>UIHingeInteraction.h</code>, iOS 27.1 SDK (Xcode 27.1, 27A9275)</td></tr>
<tr><td>Hinge API, SwiftUI</td><td><code>.onHingeChange(isEnabled:) { old, new in }</code> with <code>DeviceHingeContext.hinge: DeviceHinge?</code> → <code>status</code> (.closed / .partiallyOpen / .fullyOpen) + <code>angle: Angle</code></td><td><code>SwiftUICore.swiftinterface</code>, <code>@available(anyAppleOS 27.1)</code></td></tr>
<tr><td>What an app is <i>not</i> told</td><td>No hinge frame, no fold width, no “which screen”. The split has to be inferred from the scene size (951-wide landscape or 951-tall portrait = inner) and the fold taken as the midline</td><td>Absent from both headers</td></tr>
<tr><td>Safe areas drawn</td><td>Outer: 54 pt top (island), home indicator. Inner: 30 pt status bar, home indicator at the bottom centre (system; it sits on the fold). Estimates, not read from the profile</td><td>Not in the profile; simulator not booted (SpringBoard crash-loops on display toggles)</td></tr>
</table>'''

def font_faces(base):
    w = {400: 'Regular', 500: 'Medium', 600: 'SemiBold', 700: 'Bold', 800: 'ExtraBold'}
    return ''.join(f"@font-face{{font-family:'JetBrains Mono';font-weight:{k};src:url('{base}JetBrainsMono-{v}.ttf') format('truetype')}}" for k, v in w.items())

CHECK_JS = '''
<script>
// Collision check: report any text that intersects the crease band of an inner screen.
window.addEventListener('load', () => {
  const bad = [];
  document.querySelectorAll('.screen[data-kind="inner"], .screen[data-kind="tabletop"]').forEach((scr, si) => {
    const r = scr.getBoundingClientRect();
    const vertical = scr.dataset.kind === 'inner';
    const mid = vertical ? r.left + r.width / 2 : r.top + r.height / 2;
    const walker = document.createTreeWalker(scr, NodeFilter.SHOW_TEXT);
    let n;
    while ((n = walker.nextNode())) {
      if (!n.textContent.trim()) continue;
      const range = document.createRange(); range.selectNodeContents(n);
      for (const b of range.getClientRects()) {
        const a0 = vertical ? b.left : b.top, a1 = vertical ? b.right : b.bottom;
        if (a1 > mid - 12 && a0 < mid + 12) bad.push(si + ':' + n.textContent.trim().slice(0, 30));
      }
    }
  });
  // pairing pills live outside .screen
  document.querySelectorAll('figure').forEach(f => {
    const scr = f.querySelector('.screen[data-kind="inner"]'); if (!scr) return;
    const r = scr.getBoundingClientRect(); const mid = r.left + r.width / 2;
    f.querySelectorAll(':scope > div > div:not([style*="background: #050506"])').forEach(el => {
      const b = el.getBoundingClientRect();
      if (b.right > mid - 12 && b.left < mid + 12 && el.textContent.trim()) bad.push('pill:' + el.textContent.trim());
    });
  });
  const pre = document.createElement('pre');
  document.body.dataset.size = Math.ceil(document.body.scrollWidth) + 'x' + Math.ceil(document.body.scrollHeight); pre.id = 'crease-check'; pre.style.display = 'none';
  pre.textContent = 'SIZE ' + Math.ceil(document.body.firstElementChild.getBoundingClientRect().width) + 'x' + Math.ceil(document.body.firstElementChild.getBoundingClientRect().height) + ' ' + (bad.length ? 'CREASE ' + bad.join(' | ') : 'CREASE OK');
  document.body.appendChild(pre);
});
</script>'''

def html_doc(title, body, font_base, bg='#DCD8CF'):
    return (f'<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n<title>{title}</title>\n<style>{font_faces(font_base)}\n'
            f'body{{margin:0;background:{bg};font-family:{SANS};-webkit-font-smoothing:antialiased}} code{{font: 500 12.5px {MONO}}} '
            f'td{{padding: 6px 12px 6px 0; border-top: 1px solid #C9C2B4; vertical-align: top}} td+td{{padding-left: 12px}}</style>\n</head>\n<body>\n{body}\n{CHECK_JS}\n</body>\n</html>\n')

def section(s):
    frames = s['frames']()
    fw = {'folded': 2 * (OUT_W + 22) + 44, 'flat': 2 * (IN_W + 22) + 44, 'tabletop': 2 * (669 + 22) + 44}[s['posture']]
    return (f'<section id="{s["slug"]}" style="padding: 36px 40px 44px; display: flex; flex-direction: column; gap: 22px; width: {fw}px">'
            + caption_block(s['eyebrow'], s['title'], s['posture'], s['reused'], s['moved'], s['why'], width=None)
            + f'<div style="display: flex; gap: 44px; align-items: flex-start">{"".join(frames)}</div></section>')

def main():
    os.makedirs(OUTDIR, exist_ok=True); os.makedirs(TMP, exist_ok=True)
    secs = {s['slug']: section(s) for s in SCREENS}
    intro = (f'<header style="padding: 40px 40px 8px; max-width: 1900px; color: #16171A">'
             f'<div style="{mono(12, 700, "#66645E", 1.6)}">BIG SCREEN · IPHONE DUO · IOS 27.1</div>'
             f'<h1 style="margin: 6px 0 10px; font-size: 44px">Duo layouts</h1>'
             f'<p style="font-size: 16px; line-height: 1.5; max-width: 1200px; margin: 0 0 22px">The iPad/Mac station hall does not fit a foldable: no room for a 280 pt sidebar, and a fold down the middle of the inner screen. '
             f'These screens keep the Tableau pieces (tokens, flaps, route glyph, track rule, time track, river, lanes, wall) and reorganise them around the device: the outer screen is a wide, short iPhone; the inner screen is two outer screens side by side; tabletop is a desk clock. '
             f'All screens are drawn at real point size, now 17:40.</p>'
             f'<h2 style="font-size: 22px; margin: 0 0 8px">Geometry</h2>{GEOMETRY}'
             f'<p style="font-size: 14px; color: #3A3631; margin: 18px 0 0">The faint band and the grey ticks on the frame mark the fold. A load-time check in this page lists any text that intersects the 24 pt band (<code>#crease-check</code>).</p></header>')
    toc = '<nav style="padding: 10px 40px; display: flex; gap: 18px; flex-wrap: wrap; font: 600 13px ' + MONO + '">' + ''.join(f'<a href="#{s["slug"]}" style="color: #16171A">{s["eyebrow"].split(" · ")[0]} {s["title"]}</a>' for s in SCREENS) + '</nav>'
    full = intro + toc + ''.join(secs.values())
    with open(OUTDIR + '/DuoLayouts.html', 'w') as f:
        f.write(html_doc('Duo layouts', full, FONTDIR_REL))
    for slug, sec in secs.items():
        with open(f'{TMP}/{slug}.html', 'w') as f:
            f.write(html_doc(slug, sec, FONTDIR_ABS))
    fold = '<div style="display: flex; width: max-content">' + secs['folded-nearme'] + secs['folded-journey'] + '</div>'
    with open(f'{TMP}/folded.html', 'w') as f:
        f.write(html_doc('folded', fold, FONTDIR_ABS))
    print('ok', len(secs))

if __name__ == '__main__':
    main()
