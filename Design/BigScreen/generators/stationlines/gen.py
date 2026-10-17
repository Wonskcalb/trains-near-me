import sys, os
REPO = '/Users/valz/Documents/perso/trains-near-me'
OUT = REPO + '/Design/BigScreen/StationLines.html'
TMP = '/tmp/stationlines'

MONO = "'JetBrains Mono', ui-monospace, monospace"
SANS = "-apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif"

TH = {
  'dark': dict(ground='#0E0F11', card='#17191C', raised='#23262B', ink='#F2EFE8', ink2='#8F8D86',
               amber='#FFC23D', clear='#46C27A', cau='#FF9A55', caubg='rgba(255,138,61,0.16)',
               stop='#FF6B5F', stopbg='rgba(255,90,78,0.16)', W='#B5AD9F', E='#7D8A98',
               hair='rgba(255,255,255,0.07)', grid='rgba(255,255,255,0.05)', flap='#23262B',
               seam='#0E0F11', ring='#0E0F11', chipink='#16171A', faint='#3A3631', colon='#FFC23D'),
  'light': dict(ground='#F2EFE8', card='#FBFAF7', raised='#ECE8DF', ink='#16171A', ink2='#66645E',
               amber='#FFC23D', clear='#2B7F4C', cau='#9A4808', caubg='#FBE3CC',
               stop='#A3231A', stopbg='#F8D9D4', W='#3A3631', E='#55606D',
               hair='rgba(22,23,26,0.08)', grid='#E6E1D6', flap='#16171A',
               seam='rgba(242,239,232,0.16)', ring='#16171A', chipink='#16171A', faint='#D6D0C4', colon='#16171A'),
}

NOW = 17 * 60 + 40
def mins(t):
    h, m = t.split(':'); return int(h) * 60 + int(m)
def hhmm(m):
    return f'{m // 60:02d}:{m % 60:02d}'

# (time, delay | 'X' cancelled)
LINES = {
  'lyon': dict(name='Lyon Part-Dieu', side='W', num='17614', sub=('1 DELAYED · EVERY 30 MIN', 'cau'),
               trains=[('17:51', 0), ('18:21', 12), ('18:51', 0), ('19:21', 0)]),
  'sag':  dict(name='St-André-le-Gaz', side='W', num='17710', sub=('1 CANCELLED · HOURLY', 'stop'),
               trains=[('18:05', 0), ('19:05', 'X'), ('20:05', 0)]),
  'gre':  dict(name='Grenoble', side='E', num='17613', sub=('1 DELAYED · EVERY 15 MIN', 'stop'),
               trains=[('17:46', 0), ('17:58', 0), ('18:16', 24), ('18:28', 0), ('18:46', 0)]),
  'ugg':  dict(name='Grenoble Universités-Gières', side='E', num='17717', sub=('HOURLY', 'ink2'),
               trains=[('18:10', 0), ('19:10', 0)]),
  'val':  dict(name='Valence Ville', side='E', num='17853', sub=('VIA MOIRANS · HOURLY', 'ink2'),
               trains=[('18:02', 0), ('19:02', 0), ('20:02', 0)]),
}
def next_min(k):
    return mins(LINES[k]['trains'][0][0]) - NOW

# ---------------------------------------------------------------- pieces
def pill(text, fg, bg, size=12.5):
    return (f'<span style="font: 700 {size}px {MONO}; color: {fg}; background: {bg}; padding: 3px 7px; '
            f'border-radius: 7px; white-space: nowrap">{text}</span>')

def flaps(t, th, w=26, h=38, fs=25):
    tile = lambda d: (f'<span style="width: {w}px; height: {h}px; border-radius: 5px; background: {th["flap"]}; position: relative; '
                      f'display: flex; align-items: center; justify-content: center; font: 700 {fs}px {MONO}; color: {th["amber"]}">{d}'
                      f'<span style="position: absolute; left: 0; right: 0; top: {h/2 - .5}px; height: 1px; background: {th["seam"]}"></span></span>')
    return (f'<span style="display: inline-flex; align-items: center; gap: 3px" role="img" aria-label="{t}">'
            f'{tile(t[0])}{tile(t[1])}<span style="width: 8px; text-align: center; font: 700 {fs*0.8:.0f}px {MONO}; color: {th["colon"]}">:</span>'
            f'{tile(t[3])}{tile(t[4])}</span>')

def in_min(m, th, size=17):
    col = th['clear'] if m <= 10 else th['ink']
    return f'<span style="font: 700 {size}px {MONO}; color: {col}; white-space: nowrap">in {m}′</span>'

def train_row(t, d, th, align):
    """One later train. align: left | right | center."""
    if d == 'X':
        parts = [f'<span style="font: 500 17px {MONO}; color: {th["ink2"]}; text-decoration: line-through; text-decoration-thickness: 1.5px">{t}</span>',
                 pill('CANCELLED', th['stop'], th['stopbg'], 11)]
    elif d:
        fg, bg = (th['cau'], th['caubg']) if d < 20 else (th['stop'], th['stopbg'])
        parts = [f'<span style="font: 500 17px {MONO}; color: {th["ink"]}">{t}</span>',
                 pill(f'+{d}', fg, bg),
                 f'<span style="font: 500 12px {MONO}; color: {th["ink2"]}; white-space: nowrap">leaves {hhmm(mins(t) + d)}</span>']
    else:
        parts = [f'<span style="font: 500 17px {MONO}; color: {th["ink"]}">{t}</span>']
    direction = 'row-reverse' if align == 'right' else 'row'
    just = 'center' if align == 'center' else 'flex-start'
    return (f'<div style="display: flex; flex-direction: {direction}; justify-content: {just}; align-items: center; gap: 9px; height: 31px">'
            + ''.join(parts) + '</div>')

def card(k, th, x, y, w, align='left', boxed=True, name_size=24, name_lines=1):
    L = LINES[k]
    first, rest = L['trains'][0], L['trains'][1:]
    m = next_min(k)
    sub_txt, sub_col = L['sub']
    ta = {'left': 'left', 'right': 'right', 'center': 'center'}[align]
    items = {'left': 'flex-start', 'right': 'flex-end', 'center': 'center'}[align]
    direction = 'row-reverse' if align == 'right' else 'row'
    box = (f'background: {th["card"]}; border: 1px solid {th["hair"]}; border-radius: 18px; padding: 16px 20px 12px;'
           if boxed else 'padding: 0 6px;')
    meta = (f'<span style="display: flex; flex-direction: column; gap: 4px; align-items: {items}">{in_min(m, th)}'
            f'<span style="font: 600 11px {MONO}; letter-spacing: 0.6px; color: {th["ink2"]}; white-space: nowrap">'
            f'<span style="padding: 1px 5px; border-radius: 5px; border: 1px solid {th["hair"].replace("0.07", "0.22").replace("0.08", "0.22")}">TER</span> N° {L["num"]}</span></span>')
    return f'''<div style="position: absolute; left: {x}px; top: {y}px; width: {w}px; box-sizing: border-box; {box} display: flex; flex-direction: column; align-items: {items}; text-align: {ta}">
  <div style="font-size: {name_size}px; font-weight: 700; line-height: 1.15; letter-spacing: 0.1px; min-height: {name_lines * 1.15 * name_size:.0f}px">{L["name"]}</div>
  <div style="margin-top: 5px; font: 600 11px {MONO}; letter-spacing: 1.2px; color: {th[sub_col]}">{sub_txt}</div>
  <div style="margin-top: 14px; display: flex; flex-direction: {direction}; align-items: center; gap: 14px">{flaps(first[0], th)}{meta}</div>
  <div style="align-self: stretch; height: 1px; background: {th["hair"]}; margin: 13px 0 5px"></div>
  <div style="align-self: stretch; display: flex; flex-direction: column">{''.join(train_row(t, d, th, align) for t, d in rest)}</div>
</div>'''

# ---------------------------------------------------------------- paths
def d_of(segs):
    out = []
    for s in segs:
        out.append(s[0] + ' ' + ' '.join(f'{v:g}' for v in s[1:]))
    return ' '.join(out)

def cubic_at(p0, c1, c2, p1, t):
    u = 1 - t
    return tuple(u**3 * a + 3*u*u*t * b + 3*u*t*t * c + t**3 * d for a, b, c, d in zip(p0, c1, c2, p1))

def first_curve(segs):
    x = y = 0
    for s in segs:
        if s[0] == 'M': x, y = s[1], s[2]
        elif s[0] == 'H': x = s[1]
        elif s[0] == 'V': y = s[1]
        elif s[0] == 'C': return (x, y), (s[1], s[2]), (s[3], s[4]), (s[5], s[6])

def S(x0, y0, x1, y1, k=0.5):
    """Horizontal-in, horizontal-out S bend."""
    mx = x0 + (x1 - x0) * k
    return ('C', mx, y0, x1 - (x1 - x0) * k + (mx - x0) * 0, y1, x1, y1) if False else ('C', x0 + (x1-x0)*k, y0, x1 - (x1-x0)*k, y1, x1, y1)

def quarter(x0, y0, x1, y1):
    """Horizontal-in, vertical-out quarter bend (circle-ish)."""
    K = 0.5523
    return ('C', x0 + (x1 - x0) * K, y0, x1, y1 - (y1 - y0) * K, x1, y1)

def line_svg(segs, col, w=8):
    return f'<path d="{d_of(segs)}" fill="none" stroke="{col}" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"/>'

def next_dot(segs, k, th, r=7.5):
    m = next_min(k)
    t = 0.18 + 0.62 * min(m, 30) / 30
    x, y = cubic_at(*first_curve(segs), t)
    return f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="{th["amber"]}" stroke="{th["ring"]}" stroke-width="2.5"/>'

def end_bar(x, y, col, vertical=True, half=13):
    if vertical:
        return f'<path d="M {x} {y-half} V {y+half}" stroke="{col}" stroke-width="5" stroke-linecap="round"/>'
    return f'<path d="M {x-half} {y} H {x+half}" stroke="{col}" stroke-width="5" stroke-linecap="round"/>'

def tick(x, y0, y1, th, label, horizontal_bundle=True, above=True):
    pad = 9
    rect = (f'<rect x="{x-7}" y="{y0-pad}" width="14" height="{y1-y0+2*pad}" rx="7" fill="{th["card"]}" stroke="{th["ink2"]}" stroke-width="2"/>')
    ly = y0 - pad - 10 if above else y1 + pad + 20
    txt = (f'<text x="{x}" y="{ly}" text-anchor="middle" style="font: 600 11px {MONO}; letter-spacing: 1.2px" fill="{th["ink2"]}">{label}</text>')
    return rect + txt

def capsule(cx, cy, w, h, th):
    sw = 3 if th is TH['light'] else 5
    stroke = th['ink'] if th is TH['light'] else th['ground']
    return f'<rect x="{cx-w/2}" y="{cy-h/2}" width="{w}" height="{h}" rx="{min(w,h)/2}" fill="{th["amber"]}" stroke="{stroke}" stroke-width="{sw}"/>'

def caps_label(x, y, text, th, anchor='middle', col=None, size=11, weight=600, ls=1.3):
    return (f'<text x="{x}" y="{y}" text-anchor="{anchor}" style="font: {weight} {size}px {MONO}; letter-spacing: {ls}px" '
            f'fill="{col or th["ink2"]}">{text}</text>')

# ---------------------------------------------------------------- frame
def frame(th, mode, svg, html, title='Lines'):
    seg_on = f'background: {th["card"]}; color: {th["ink"]}; box-shadow: 0 1px 2px rgba(0,0,0,0.18)'
    seg_off = f'background: transparent; color: {th["ink2"]}'
    leg = lambda sw, label: f'<span style="display: flex; align-items: center; gap: 6px">{sw}{label}</span>'
    legend = ''.join([
        leg(f'<span style="width: 11px; height: 11px; border-radius: 6px; background: {th["amber"]}; box-shadow: inset 0 0 0 2px {th["ring"]}"></span>', 'next'),
        leg(pill('+12', th['cau'], th['caubg'], 10.5), 'late'),
        leg(pill('+24', th['stop'], th['stopbg'], 10.5), 'very late'),
        leg(f'<span style="text-decoration: line-through; color: {th["ink2"]}">19:05</span>', 'cancelled'),
    ])
    return f'''<div style="position: relative; width: 1376px; height: 1032px; overflow: hidden; flex: none; box-sizing: border-box; background: {th["ground"]}; color: {th["ink"]}; font-family: {SANS}; -webkit-font-smoothing: antialiased" aria-label="Voiron station lines, {mode}">
  <div style="position: absolute; left: 44px; right: 44px; top: 28px; display: flex; justify-content: space-between; align-items: flex-start">
    <div style="display: flex; flex-direction: column; gap: 4px">
      <span style="font: 600 11px {MONO}; letter-spacing: 1.4px; color: {th["ink2"]}">DEPARTURES · STATION</span>
      <span style="font-size: 40px; font-weight: 700; letter-spacing: 0.2px; line-height: 1.1">Voiron</span>
    </div>
    <div style="display: flex; flex-direction: column; align-items: flex-end; gap: 14px">
      <div style="display: flex; align-items: center; gap: 14px">
        <span style="display: flex; align-items: center; gap: 7px; font: 500 12px {MONO}; color: {th["ink2"]}"><span style="width: 7px; height: 7px; border-radius: 4px; background: {th["clear"]}"></span>Updated 17:40</span>
        <div style="display: flex; padding: 3px; border-radius: 12px; background: {th["raised"]}">
          <span style="height: 32px; padding: 0 14px; border-radius: 9px; font: 600 13px {SANS}; display: flex; align-items: center; {seg_off}">Board</span>
          <span style="height: 32px; padding: 0 14px; border-radius: 9px; font: 600 13px {SANS}; display: flex; align-items: center; {seg_on}">{title}</span>
        </div>
      </div>
      <div style="display: flex; gap: 16px; font: 500 11.5px {MONO}; color: {th["ink2"]}">{legend}</div>
    </div>
  </div>
  <svg width="1376" height="1032" viewBox="0 0 1376 1032" style="position: absolute; left: 0; top: 0" aria-hidden="true">{svg}</svg>
  {html}
  <div style="position: absolute; left: 44px; right: 44px; bottom: 18px; display: flex; justify-content: space-between; font: 500 11px {MONO}; color: {th["ink2"]}; letter-spacing: 0.3px">
    <span>Data © SNCF · Not affiliated with SNCF</span><span>Tap a terminus to open its journey · ⌘R</span>
  </div>
</div>'''

# ================================================================ Variant A
def variant_a(th, mode):
    svg, html = [], []
    cx, cy = 688, 580
    # cards: (key, top) ; west x 44..364 right-aligned, east 1012..1332
    WX, WW, EX, EW = 44, 330, 1002, 330
    tops = {'lyon': 318, 'sag': 640, 'gre': 166, 'ugg': 500, 'val': 742}
    NAME = 30  # line meets the card at the name's centre
    ys = {'lyon': cy - 7, 'sag': cy + 7, 'gre': cy - 14, 'ugg': cy, 'val': cy + 14}
    peel = {'lyon': 596, 'sag': 572, 'gre': 790, 'ugg': 870, 'val': 830}
    wend, eend = WX + WW + 12, EX - 12
    paths = {}
    for k in ('lyon', 'sag'):
        ty = tops[k] + NAME
        paths[k] = [('M', cx, ys[k]), ('H', peel[k]), S(peel[k], ys[k], wend, ty), ('H', wend)]
    for k in ('gre', 'ugg', 'val'):
        ty = tops[k] + NAME
        paths[k] = [('M', cx, ys[k]), ('H', peel[k]), S(peel[k], ys[k], eend, ty), ('H', eend)]
    for k, p in paths.items():
        col = th[LINES[k]['side']]
        svg.append(line_svg(p, col))
        ex = p[-1][1]; ey = p[-2][6]
        svg.append(end_bar(ex, ey, col))
    svg.append(tick(664 - 6, cy - 7, cy + 7, th, 'RIVES') if False else '')
    svg.append(tick(624, cy - 7, cy + 7, th, 'RIVES'))
    svg.append(tick(756, cy - 14, cy + 14, th, 'MOIRANS'))
    for k, p in paths.items():
        svg.append(next_dot(p, k, th))
    svg.append(capsule(cx, cy, 30, 62, th) if False else '')
    svg.append(capsule(cx, cy, 52, 84, th))
    svg.append(caps_label(cx, cy + 70, 'VOIRON', th, col=th['ink'], size=13, weight=700, ls=1.6))
    svg.append(caps_label(cx, cy + 88, '5 LINES · 16 TRAINS', th, size=10.5))
    svg.append(caps_label(WX + WW, tops['lyon'] - 18, '← WEST · TOWARDS LYON', th, anchor='end'))
    svg.append(caps_label(EX, tops['gre'] - 16, 'EAST · TOWARDS GRENOBLE →', th, anchor='start'))
    html.append(card('lyon', th, WX, tops['lyon'], WW, 'right'))
    html.append(card('sag', th, WX, tops['sag'], WW, 'right'))
    for k in ('gre', 'ugg', 'val'):
        html.append(card(k, th, EX, tops[k], EW, 'left', name_size=24 if k != 'ugg' else 22))
    return frame(th, mode, ''.join(svg), '\n'.join(html), 'Lines')

# ================================================================ Variant B
def variant_b(th, mode):
    svg, html = [], []
    X0, X1, T0, T1 = 430, 1080, NOW, NOW + 150
    px = lambda m: X0 + (m - T0) * (X1 - X0) / (T1 - T0)
    lanes = {'lyon': 236, 'sag': 366, 'gre': 616, 'ugg': 746, 'val': 876}
    sx, sy = 78, 491
    exit_y = {'lyon': sy - 31, 'sag': sy - 17, 'gre': sy + 3 + 0, 'ugg': sy + 17, 'val': sy + 31}
    exit_y['gre'] = sy + 3
    peel = {'lyon': 110, 'sag': 150, 'gre': 160, 'ugg': 130, 'val': 104}
    CURVE_END, LANE_END = 400, 1110
    # time grid
    for h in (18, 19, 20):
        x = px(h * 60)
        svg.append(f'<path d="M {x:.1f} 176 V 930" stroke="{th["grid"]}" stroke-width="1.5"/>')
        svg.append(caps_label(x, sy + 5, f'{h}:00', th, size=12.5, weight=600, ls=0.3))
        for q in (15, 30, 45):
            xq = px(h * 60 + q)
            if xq < X1:
                svg.append(f'<path d="M {xq:.1f} {sy-4} V {sy+4}" stroke="{th["faint"]}" stroke-width="2" stroke-linecap="round"/>')
    svg.append(f'<path d="M {X0} 176 V 930" stroke="{th["ink2"]}" stroke-width="1.5" stroke-dasharray="3 4"/>')
    html.append(f'<div style="position: absolute; left: {X0 - 46}px; top: {sy - 13}px; width: 92px; text-align: center"><span style="font: 700 11px {MONO}; letter-spacing: 0.8px; color: {th["ground"]}; background: {th["ink"]}; padding: 4px 7px; border-radius: 6px">NOW 17:40</span></div>')
    for xm in (35, 65, 95, 125):
        pass
    for k, y in lanes.items():
        side = LINES[k]['side']
        col = th[side]
        p = [('M', sx, exit_y[k]), ('H', peel[k]), S(peel[k], exit_y[k], CURVE_END, y), ('H', LANE_END)]
        svg.append(line_svg(p, col, 7))
        svg.append(end_bar(LANE_END, y, col, half=14))
        # terminus name at the end of the line
        L = LINES[k]
        sub_txt, sub_col = L['sub']
        html.append(f'''<div style="position: absolute; left: {LANE_END + 18}px; top: {y}px; transform: translateY(-50%); width: 216px">
  <div style="font-size: {21 if k != 'ugg' else 19}px; font-weight: 700; line-height: 1.15">{L["name"]}</div>
  <div style="margin-top: 5px; font: 600 10.5px {MONO}; letter-spacing: 1.1px; color: {th[sub_col]}">{sub_txt}</div></div>''')
        # trains as stops
        rows = {'below': [], 'above': []}
        def place(x0, x1):
            for r in ('below', 'above'):
                if all(x1 + 10 < a or x0 > b + 10 for a, b in rows[r]):
                    rows[r].append((x0, x1)); return r
            rows['below'].append((x0, x1)); return 'below'
        marks = []
        for i, (t, d) in enumerate(L['trains']):
            sched = mins(t)
            if d == 'X':
                x = px(sched)
                marks.append(f'<circle cx="{x:.1f}" cy="{y}" r="8" fill="{th["card"]}" stroke="{th["stop"]}" stroke-width="2.2"/>'
                             f'<path d="M {x-3.5:.1f} {y-3.5} l 7 7 M {x+3.5:.1f} {y-3.5} l -7 7" stroke="{th["stop"]}" stroke-width="2" stroke-linecap="round"/>')
                w = 5 * 9.6 + 8 + 6 * 6.6 + 14
                label = (f'<span style="font: 600 16px {MONO}; color: {th["stop"]}; text-decoration: line-through">{t}</span>'
                         + pill('CANC.', th['stop'], th['stopbg'], 11))
            elif d:
                exp = sched + d
                x, gx = px(exp), px(sched)
                fg = th['cau'] if d < 20 else th['stop']
                bg = th['caubg'] if d < 20 else th['stopbg']
                mid = (x + gx) / 2
                marks.append(f'<path d="M {gx:.1f} {y-7} Q {mid:.1f} {y-34} {x:.1f} {y-9}" fill="none" stroke="{fg}" stroke-width="1.6" stroke-dasharray="3 3"/>'
                             f'<circle cx="{gx:.1f}" cy="{y}" r="5" fill="{th["card"]}" stroke="{fg}" stroke-width="1.8"/>'
                             f'<circle cx="{x:.1f}" cy="{y}" r="8" fill="{fg}" stroke="{th["ground"]}" stroke-width="2.5"/>')
                w = 5 * 9.6 + 8 + 3 * 7.5 + 14
                label = (f'<span style="font: 600 16px {MONO}; color: {fg}">{hhmm(exp)}</span>' + pill(f'+{d}', fg, bg, 12))
            elif i == 0:
                x = px(sched)
                marks.append(f'<circle cx="{x:.1f}" cy="{y}" r="10" fill="{th["amber"]}" stroke="{th["ring"]}" stroke-width="3"/>')
                m = sched - NOW
                w = 5 * 10.2 + 16 + 10 + len(f'in {m}′') * 9.6
                label = (f'<span style="font: 700 17px {MONO}; color: {th["chipink"]}; background: {th["amber"]}; padding: 3px 8px; border-radius: 7px">{t}</span>'
                         + in_min(m, th, 16))
            else:
                x = px(sched)
                marks.append(f'<circle cx="{x:.1f}" cy="{y}" r="7" fill="{th["card"]}" stroke="{col}" stroke-width="3"/>')
                w = 5 * 9.6
                label = f'<span style="font: 500 16px {MONO}; color: {th["ink"]}">{t}</span>'
            x0 = x - (w / 2 if i else 14)
            r = place(x0, x0 + w)
            top = y + 16 if r == 'below' else y - 44
            html.append(f'<div style="position: absolute; left: {x0:.1f}px; top: {top}px; width: {w + 30:.0f}px; display: flex; align-items: center; gap: 7px; height: 28px">{label}</div>')
        svg.extend(marks)
    svg.append(capsule(sx, sy, 40, 96, th))
    svg.append(caps_label(sx, sy + 72, 'VOIRON', th, col=th['ink'], size=13, weight=700, ls=1.6))
    svg.append(caps_label(sx - 30, lanes['lyon'] - 70, 'WEST · TOWARDS LYON', th, anchor='start') if False else '')
    svg.append(caps_label(44, 196, 'WEST · TOWARDS LYON', th, anchor='start'))
    svg.append(caps_label(44, 916, 'EAST · TOWARDS GRENOBLE', th, anchor='start'))
    return frame(th, mode, ''.join(svg), '\n'.join(html), 'Lines')

# ================================================================ Variant C
def variant_c(th, mode):
    svg, html = [], []
    cx, cy = 562, 318
    cols = {'lyon': 48, 'sag': 300, 'gre': 592, 'ugg': 844, 'val': 1096}
    CW = 232
    ys = {'lyon': cy - 7, 'sag': cy + 7, 'val': cy - 14, 'ugg': cy, 'gre': cy + 14}
    END = 560
    for k, x0 in cols.items():
        col = th[LINES[k]['side']]
        xc = x0 + CW / 2
        y0 = ys[k]
        dx = abs(xc - cx)
        R = min(dx - 4, END - y0 - 30, 150 + dx * 0.12)
        sgn = -1 if xc < cx else 1
        xb = xc - sgn * R
        p = [('M', cx, y0), ('H', xb), quarter(xb, y0, xc, y0 + R), ('V', END)]
        svg.append(line_svg(p, col))
        svg.append(end_bar(xc, END, col, vertical=False, half=16))
        svg.append(next_dot(p, k, th))
        html.append(card(k, th, x0, END + 18, CW, 'center', boxed=False, name_size=22, name_lines=2))
    svg.append(capsule(cx, cy, 44, 64, th))
    svg.append(caps_label(cx, cy - 50, 'VOIRON', th, col=th['ink'], size=13, weight=700, ls=1.6))
    svg.append(caps_label(cx - 70, cy - 24, '← WEST · LYON', th, anchor='end'))
    svg.append(caps_label(cx + 70, cy - 31, 'EAST · GRENOBLE →', th, anchor='start'))
    # a calm divider between the two sides, under the station
    svg.append(f'<path d="M {cx} {cy + 60} V 940" stroke="{th["hair"]}" stroke-width="1.5" stroke-dasharray="2 6" stroke-linecap="round"/>')
    return frame(th, mode, ''.join(svg), '\n'.join(html), 'Lines')

VARIANTS = [
  ('A', 'Two-sided metro', variant_a,
   'The station sits in the middle as an interchange; each side leaves as one bundled trunk and fans out with S-bends, so every terminus ends on its own line, with its card at the line end.',
   'Good at: geography. Left really is the Lyon side, right the Grenoble side, and the junctions (Rives, Moirans) read like a real line map. Mirrored cards keep each name tight against its line end.',
   'Weak spot: the centre third of the pane is lines only, so the cards get about 330 pt each and the long names wrap. The S-bend steepens when a card sits far from the station.',
   'Scales: 4 cards per side fit at this height if each list is cut to 2 more trains. Past that, a side needs two card columns, and the bends nest.'),
  ('B', 'Horizontal river', variant_b,
   'The station is the source on the left edge. The line splits into five horizontal lanes with S-curves, the west side above and the east side below, and the time axis runs through the middle like a river bank. Trains are stops on their lane, placed at their time, and the terminus is written at the end of the lane.',
   'Good at: time. Gaps, bunching and the +24 that overtakes the 18:28 show at a glance, and it reuses the time-track grammar (ghost slot, dashed arc, hollow ✕).',
   'Weak spot: labels can collide when trains are minutes apart (17:46 / 17:58 need two label rows), and the lane labels the trains, not the terminus card, so the "list under the name" turns into a row along the line.',
   'Scales: 8 lanes fit at about 90 pt pitch. The S-curves just get steeper. It is the most robust layout for a big station.'),
  ('C', 'Delta', variant_c,
   'A vertical tree. The station hangs at the top, the two sides leave left and right, and each line bends down into its own column with a rounded quarter-turn. The terminus name sits at the foot of the line, and its trains are listed straight under it, like the column of a departure board.',
   'Good at: the brief, literally. Each line ends on its terminus and the list falls under it. Columns are equal, so every terminus gets the same weight, and it is the calmest of the three.',
   'Weak spot: the station is not centred (2 columns west, 3 east), and the space inside the bends is empty. Five columns of 232 pt make the long names wrap to two lines.',
   'Scales: 6 columns fit at about 200 pt. For 7–8, stack two rows of columns per side, or let a side fold its smallest branch into a "+2 more" chip.'),
]

def page(font_base, only=None):
    faces = ''.join(f"@font-face{{font-family:'JetBrains Mono';font-weight:{w};src:url('{font_base}/JetBrainsMono-{n}.ttf') format('truetype')}}"
                    for w, n in ((400, 'Regular'), (500, 'Medium'), (600, 'SemiBold'), (700, 'Bold'), (800, 'ExtraBold')))
    sections = []
    for key, name, fn, desc, good, weak, scale in VARIANTS:
        if only and key != only: continue
        sections.append(f'''<section style="display: flex; flex-direction: column; gap: 22px; padding: 40px">
  <div style="display: flex; gap: 40px; align-items: flex-start; max-width: 2792px">
    <div style="flex: 0 0 420px"><div style="font: 700 12px {MONO}; letter-spacing: 1.6px; color: #66645E">VARIANT {key}</div>
      <h2 style="margin: 4px 0 0; font-size: 34px; color: #16171A">{name}</h2></div>
    <p style="margin: 0; flex: 1; font-size: 17px; line-height: 1.5; color: #16171A">{desc}</p>
    <ul style="margin: 0; flex: 1.3; padding-left: 18px; font-size: 15px; line-height: 1.5; color: #3A3631"><li>{good}</li><li>{weak}</li><li>{scale}</li></ul>
  </div>
  <div style="display: flex; gap: 40px">{fn(TH['dark'], 'dark')}{fn(TH['light'], 'light')}</div>
</section>''')
    header = '' if only else f'''<header style="padding: 40px 40px 0; font-size: 15px; color: #3A3631; max-width: 1500px">
  <div style="font: 700 12px {MONO}; letter-spacing: 1.6px; color: #66645E">BIG SCREEN · STATION BOARD AS A LINE MAP</div>
  <h1 style="margin: 6px 0 8px; font-size: 44px; color: #16171A">Station lines</h1>
  Three ways to draw Voiron's departures as a line map, each in Board (dark) and Timetable (light). Pane 1376×1032, the 280 pt sidebar sits outside. Now is 17:40. Lines are drawn with cubic curves only. The amber marks only the station and each line's next train.
</header>'''
    return f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Station lines — Voiron</title>
<style>
{faces}
body{{margin:0;background:#DCD8CF;font-family:{SANS};-webkit-font-smoothing:antialiased}}
</style>
</head>
<body>
{header}
{''.join(sections)}
</body>
</html>'''

open(OUT, 'w').write(page('../../SNCFCore/Sources/SNCFCore/Theme/Fonts'))
for key, *_ in VARIANTS:
    open(f'{TMP}/{key}.html', 'w').write(page(REPO + '/SNCFCore/Sources/SNCFCore/Theme/Fonts', key))
print('ok')
