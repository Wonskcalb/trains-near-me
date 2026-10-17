# Round 2: the Duo mockups with the system chrome where iOS 27.1 puts it.
# Reuses the round-one components from gen.py; only the chrome, the frames and the screens are new.
import os, sys
sys.path.insert(0, '/tmp/duo')
import gen as g
from gen import (TH, MONO, SANS, mono, caps, chip, tag, pill, flaps, glyph, route_head, icon, ICONS, track_rule,
                 time_track, hero_journey, hero_station, journey_row, station_row, station_departures, inspector,
                 river, rt_list, OUT_ROWS, BACK_ROWS, JLIST, LANE_T0, LANE_SPAN, lane_track, journey_card,
                 journey_track_deps, late_pill, canc_pill, hhmm, mins, NOW, JOURNEY, font_faces, abs_div, status_bar)

OUTDIR = g.OUTDIR
TMP = g.TMP

# ---------------------------------------------------------------- geometry (points)
OUT_W, OUT_H = 466, 678          # outer display, folded
IN_W, IN_H = 951, 669            # inner display, landscape
P_W, P_H = 669, 951              # inner display, portrait
FOLD = 475.5                     # x in landscape, y in portrait
GUTTER = 12                      # half of the gutter kept clear for partial opening (our choice)
STRIP_IN = 84                    # trailing inset of the vertical strip: content's safe edge is 466 - 84 = 382
SAFE_OUT = OUT_W - STRIP_IN      # 382
SAFE_IN = IN_W - STRIP_IN        # 867
CX_OUT = OUT_W - 48              # 418: strip centre, measured on the folded screenshot
CX_IN = IN_W - 48                # 903
TAB_H = 162                      # vertical tab capsule, 492-654 on the outer display
L0, L1 = 20, FOLD - 20           # leading column content
R0, R1 = FOLD + 20, SAFE_IN      # trailing column content (372 pt: one outer screen's content width)

ICONS.update({
  'lines': '<circle cx="5" cy="18" r="2.3"/><circle cx="12" cy="5.5" r="2.3"/><circle cx="19" cy="18" r="2.3"/><path d="M6.3 15.8l4.4-8M13.3 7.8l4.4 8M7.6 18h8.8" stroke-dasharray="2.2 2.2"/>',
  'lanes': '<rect x="3" y="4" width="11" height="4" rx="2"/><rect x="9" y="10" width="12" height="4" rx="2"/><rect x="4" y="16" width="9" height="4" rx="2"/>',
  'tv': '<rect x="3" y="5" width="18" height="12" rx="2"/><path d="M8 21h8M12 17v4"/>',
  'antenna': '<circle cx="12" cy="10" r="1.6"/><path d="M12 12v9M8.5 6.5a5 5 0 0 0 0 7M15.5 6.5a5 5 0 0 1 0 7M5.6 3.6a9 9 0 0 0 0 12.8M18.4 3.6a9 9 0 0 1 0 12.8"/>',
  'sidebar': '<rect x="3" y="4" width="18" height="16" rx="3"/><path d="M9 4v16"/>',
  'cal': '<rect x="4" y="5" width="16" height="15" rx="2.5"/><path d="M4 10h16M9 3v4M15 3v4"/>',
})

def T(th): return th['amber']   # the app's .tint(.amber): system controls draw their tint in amber

# ---------------------------------------------------------------- system chrome (iOS 27 glass)
def glass(th, prominent=False):
    if prominent:
        return f'background: {th["amber"]}; color: #0E0F11; border: 1px solid rgba(0,0,0,0.08);'
    sh = '0 6px 18px rgba(0,0,0,0.40)' if th['name'] == 'dark' else '0 6px 18px rgba(22,23,26,0.10)'
    return f'background: {th["glass"]}; color: {th["ink"]}; border: 1px solid {th["glassline"]}; box-shadow: {sh}; backdrop-filter: blur(18px);'

def circle_item(th, ic, label, x, y, d=48, prominent=False):
    col = '#0E0F11' if prominent else th['ink']
    return (f'<span class="chrome" aria-label="{label}" title="{label}" style="position: absolute; left: {x}px; top: {y}px; width: {d}px; height: {d}px; border-radius: {d / 2}px; '
            f'{glass(th, prominent)} display: flex; align-items: center; justify-content: center; box-sizing: border-box">{icon(ic, d * 0.42, 2.2, col)}</span>')

def text_item(th, label, right, y, h=44, lead_icon=None):
    """A text-only toolbar button: the system keeps these horizontal, top trailing of the content."""
    ic = icon(lead_icon, 15, 2.4, T(th)) if lead_icon else ''
    return (f'<span class="chrome" style="position: absolute; right: {right}px; top: {y}px; height: {h}px; padding: 0 17px; border-radius: {h / 2}px; {glass(th)} '
            f'color: {T(th)}; display: inline-flex; align-items: center; gap: 6px; font: 500 17px {SANS}; box-sizing: border-box; white-space: nowrap">{ic}{label}</span>')

def status_glyph(th, cx, y):
    """iOS 27's vertical status block: Wi-Fi inside the battery ring, the four signal dots under it."""
    ink = th['ink']
    return (f'<svg class="chrome" width="44" height="46" viewBox="0 0 44 46" style="position: absolute; left: {cx - 22}px; top: {y}px" aria-label="Wi-Fi, battery">'
            f'<path d="M7.2 30A17 17 0 1 1 36.8 30" fill="none" stroke="{ink}" stroke-width="3.6" stroke-linecap="round"/>'
            f'<path d="M22 27l3.6-4.2a5.5 5.5 0 0 0-7.2 0zM14.6 18.7a11.3 11.3 0 0 1 14.8 0l2.2-2.6a14.8 14.8 0 0 0-19.2 0z" fill="{ink}"/>'
            + ''.join(f'<circle cx="{x}" cy="{40 if x in (16, 28) else 38.4}" r="2" fill="{th["ink2"]}"/>' for x in (10, 16, 28, 34)) + '</svg>')

def vstrip(th, W, H, items=(), tab=None, island=False, loc=False):
    """The trailing system strip: (island), status, toolbar items top-down, the tab capsule at the bottom."""
    cx = W - 48
    out = []
    if island:   # camera corner + Dynamic Island: drawn in the 0-75 pt gap the screenshot leaves (assumption)
        out.append(f'<span class="chrome" title="Dynamic Island" style="position: absolute; left: {cx - 16}px; top: 14px; width: 32px; height: 50px; border-radius: 16px; background: #000"></span>')
    ty = 92 if island else 38
    if loc:
        out.append(f'<span class="chrome" style="position: absolute; left: {cx - 7}px; top: {ty - 24}px">{icon("loc", 13, 2.4, th["ink"]).replace("fill=\"none\"", f"fill=\"{th["ink"]}\"")}</span>')
    out.append(f'<span class="chrome" style="position: absolute; left: {cx - 30}px; width: 60px; top: {ty - 10}px; text-align: center; font: 700 16px {SANS}; color: {th["ink"]}">17:40</span>')
    out.append(status_glyph(th, cx, ty + 14))
    y = ty + 82
    for it in items:
        ic, label = it[0], it[1]
        out.append(circle_item(th, ic, label, cx - 24, y, prominent=len(it) > 2 and it[2]))
        y += 58
    assert y - 10 <= H - 24 - TAB_H, 'toolbar items run into the tab capsule'
    if tab:
        out.append(vtabs(th, tab, cx, H - 24 - TAB_H))
    return ''.join(out)

TABS = [('antenna', 'Near me'), ('route', 'Journeys'), ('sliders', 'Settings')]

def vtabs(th, active, cx, y):
    cells = []
    for ic, lab in TABS:
        on = lab == active
        bg = f'background: {th["tabsel"]};' if on else ''
        cells.append(f'<span aria-label="{lab}" style="height: 50px; border-radius: 25px; {bg} display: flex; align-items: center; justify-content: center">'
                     f'{icon(ic, 22, 2.1, T(th) if on else th["ink"])}</span>')
    return (f'<div class="chrome" role="tablist" style="position: absolute; left: {cx - 24}px; top: {y}px; width: 48px; height: {TAB_H}px; box-sizing: border-box; padding: 4px 3px; '
            f'border-radius: 24px; {glass(th)} display: flex; flex-direction: column; justify-content: space-between">{"".join(cells)}</div>')

def htabs(th, active, cx, y, w=318):
    """The iOS tab bar, horizontal: inner display in portrait."""
    cells = []
    for ic, lab in TABS:
        on = lab == active
        col = T(th) if on else th['ink']
        bg = f'background: {th["tabsel"]};' if on else ''
        cells.append(f'<span style="flex: 1; height: 52px; border-radius: 26px; {bg} display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 2px; color: {col}">'
                     f'{icon(ic, 21, 2.1)}<span style="font: 600 10px {SANS}">{lab}</span></span>')
    return (f'<div class="chrome" role="tablist" style="position: absolute; left: {cx - w / 2}px; top: {y}px; width: {w}px; height: 62px; box-sizing: border-box; padding: 5px; border-radius: 31px; '
            f'{glass(th)} display: flex; gap: 2px">{"".join(cells)}</div>')

def hbar_back(th, label, x, y, h=44):
    return (f'<span class="chrome" style="position: absolute; left: {x}px; top: {y}px; height: {h}px; padding: 0 16px 0 11px; border-radius: {h / 2}px; {glass(th)} '
            f'display: inline-flex; align-items: center; gap: 4px; font: 500 17px {SANS}; box-sizing: border-box; white-space: nowrap">{icon("back", 18, 2.6, th["ink"])}{label}</span>')

def hbar_icons(th, items, right, y, d=44):
    """Toolbar items in a horizontal bar: one glass capsule per group, right-aligned at `right` (an x)."""
    out, x = [], right
    for it in reversed(items):
        x -= d
        out.append(circle_item(th, it[0], it[1], x, y, d, prominent=len(it) > 2 and it[2]))
        x -= 8
    return ''.join(out)

def home_indicator(th, cx, y):
    return f'<span class="chrome" style="position: absolute; left: {cx - 70}px; top: {y}px; width: 140px; height: 5px; border-radius: 3px; background: {th["ink"]}; opacity: .5"></span>'

def column_rule(th, x=FOLD, H=IN_H):
    """NavigationSplitView's column separator. A hairline may cross the fold; text may not."""
    return f'<div style="position: absolute; left: {x - 0.5}px; top: 0; width: 1px; height: {H}px; background: {th["hair2"]}"></div>'

def h_rule(th, y, W=P_W):
    return f'<div style="position: absolute; top: {y - 0.5}px; left: 0; height: 1px; width: {W}px; background: {th["hair2"]}"></div>'

# ---------------------------------------------------------------- device frames
def device(kind, th, content):
    """kind: outer | inner (landscape, fold vertical) | portrait (fold horizontal) | tabletop (portrait, partially open)."""
    bez = 11
    w, h = {'outer': (OUT_W, OUT_H), 'inner': (IN_W, IN_H)}.get(kind, (P_W, P_H))
    marks = spine = band = ''
    if kind == 'outer':
        rad, frad = 'border-radius: 8px 59px 59px 8px', 'border-radius: 16px 68px 68px 16px'
        spine = (f'<div style="position: absolute; left: -9px; top: 26px; bottom: 26px; width: 9px; border-radius: 5px 0 0 5px; '
                 f'background: repeating-linear-gradient(180deg, #2A2C30 0 14px, #1B1C1F 14px 16px)" title="spine (hinge)"></div>')
    else:
        rad, frad = 'border-radius: 55px', 'border-radius: 64px'
        if kind == 'inner':
            marks = (f'<div style="position: absolute; left: {bez + FOLD - 1}px; top: -7px; width: 2px; height: 9px; background: #8F8D86"></div>'
                     f'<div style="position: absolute; left: {bez + FOLD - 1}px; bottom: -7px; width: 2px; height: 9px; background: #8F8D86"></div>')
            band = (f'<div style="position: absolute; left: {FOLD - GUTTER}px; width: {2 * GUTTER}px; top: 0; bottom: 0; '
                    f'background: linear-gradient(90deg, transparent, {th["crease"]} 40%, {th["crease"]} 60%, transparent); pointer-events: none"></div>')
        else:
            marks = (f'<div style="position: absolute; top: {bez + FOLD - 1}px; left: -7px; height: 2px; width: 9px; background: #8F8D86"></div>'
                     f'<div style="position: absolute; top: {bez + FOLD - 1}px; right: -7px; height: 2px; width: 9px; background: #8F8D86"></div>')
            if kind == 'portrait':
                band = (f'<div style="position: absolute; top: {FOLD - GUTTER}px; height: {2 * GUTTER}px; left: 0; right: 0; '
                        f'background: linear-gradient(180deg, transparent, {th["crease"]} 40%, {th["crease"]} 60%, transparent); pointer-events: none"></div>')
            else:   # tabletop: the division is active and excluded from layout
                band = (f'<div title="division (reserved region)" style="position: absolute; top: {FOLD - GUTTER}px; height: {2 * GUTTER}px; left: 0; right: 0; '
                        f'background: repeating-linear-gradient(-45deg, {th["creaseline"]} 0 2px, transparent 2px 9px), {th["crease"]}; pointer-events: none"></div>')
    return (f'<div style="position: relative; flex: none; width: {w + 2 * bez}px; height: {h + 2 * bez}px; background: #050506; {frad}; '
            f'box-shadow: 0 30px 60px rgba(22,23,26,0.30), inset 0 0 0 1.5px #2A2C30">{spine}{marks}'
            f'<div class="screen" data-kind="{kind}" style="position: absolute; left: {bez}px; top: {bez}px; width: {w}px; height: {h}px; {rad}; overflow: hidden; '
            f'background: {th["ground"]}; color: {th["ink"]}; font-family: {SANS}">{content}{band}</div></div>')

def large_title(th, text, x, y, size=34, lead=None):
    ic = f'{icon(lead, size * 0.86, 2.3, T(th))}' if lead else ''
    return abs_div(x, y, 360, f'<span style="display: inline-flex; align-items: center; gap: 12px; font-size: {size}px; font-weight: 800; letter-spacing: -0.4px; white-space: nowrap">{ic}{text}</span>')

def updated(th, x, y, text='Updated at 17:40'):
    return abs_div(x, y, 360, f'<span style="display: flex; align-items: center; gap: 7px; {mono(11.5, 500, th["ink2"])}"><span style="width: 7px; height: 7px; border-radius: 4px; background: {th["clear"]}"></span>{text}</span>')

def scroll(x, y, w, inner):
    """A scrolling list: it may run across the fold (lists stay put); the check reports it apart."""
    return f'<div data-scroll="1" style="position: absolute; left: {x}px; top: {y}px; width: {w}px">{inner}</div>'

def route_header(th, x, y, w, size=28, chips_size=9.5):
    return abs_div(x, y, w, f'<div style="display: flex; align-items: flex-end; justify-content: space-between">{route_head("Grenoble", "Voiron", th, size)}'
                   f'<span style="display: flex; flex-direction: column; align-items: flex-end; gap: 5px">{chip("DIRECT ONLY", th, chips_size)}{chip("REVERSES AT 13:00", th, chips_size)}</span></div>')

# ================================================================ 1. folded: Near me
def folded_nearme(th):
    W = OUT_W
    b = [vstrip(th, W, OUT_H, items=[('lines', 'Lines')], tab='Near me', island=True, loc=True)]
    b.append(text_item(th, 'Find me!', W - SAFE_OUT, 24))
    b.append(large_title(th, 'Near me', L0, 80, lead='antenna'))
    b.append(abs_div(L0, 134, SAFE_OUT - L0, hero_station(th, SAFE_OUT - L0, flap=(30, 44, 28), track=False)))
    b.append(abs_div(L0, 270, SAFE_OUT - L0, track_rule('THEN', th)))
    rows = station_departures()[1:9]
    b.append(scroll(4, 290, SAFE_OUT - 4, ''.join(station_row(r, th, pad=16) for r in rows)))
    return device('outer', th, ''.join(b))

# ================================================================ 2. folded: a journey board
def folded_journey(th):
    W = OUT_W
    b = [vstrip(th, W, OUT_H, items=[('back', 'Journeys'), ('pair', 'Round trip', True), ('swap', 'Swap direction'), ('tv', 'Wall')], tab='Journeys', island=True)]
    cw = SAFE_OUT - L0
    b.append(route_header(th, L0, 24, cw))
    b.append(abs_div(L0, 92, cw, narrow_hero(th, cw, (30, 44, 28), 'NEXT · ARRIVES 18:07')))
    b.append(scroll(4, 248, SAFE_OUT - 4, ''.join(journey_row(r, th, pad=16, num=None) for r in JOURNEY + EVENING[:2])
             + f'<div style="padding: 14px 16px">{updated(th, 0, 0).replace("position: absolute; ", "")}</div>'))
    return device('outer', th, ''.join(b))

# ================================================================ 3. inner landscape: journey, board | train
def narrow_hero(th, w, flap, caption, sub=None):
    h = hero_journey(th, w, flap=flap).replace('NEXT TRAIN · ARRIVES 18:07', caption)
    return h.replace('N° 17653 · 25 min', sub) if sub else h

EVENING = [('21:12', '21:37', '17665', '25 min', ('wait', '3 h 32')), ('21:42', '22:07', '17667', '25 min', ('wait', '4 h 02')),
           ('22:42', '23:07', '17669', '25 min', ('wait', '5 h 02'))]

def board_column(th, x0, x1, top, flap=(36, 52, 34), num=True, selected=1, rows_pad=16, hero=None, rows=JOURNEY):
    w = x1 - x0
    out = [route_header(th, x0, top, w)]
    out.append(abs_div(x0, top + 66, w, hero or hero_journey(th, w, flap=flap)))
    hero_h = flap[1] + 106
    out.append(scroll(x0 - rows_pad, top + 66 + hero_h + 12, w + 2 * rows_pad,
                      ''.join(journey_row(r, th, selected=(i == selected), pad=rows_pad, num=num) for i, r in enumerate(rows))))
    return ''.join(out)

def inner_journey(th):
    b = [column_rule(th)]
    # leading column: its bar stays horizontal
    b.append(hbar_back(th, 'Journeys', L0, 20))
    b.append(hbar_icons(th, [('pair', 'Round trip'), ('swap', 'Swap direction'), ('tv', 'Wall')], L1, 20))
    b.append(board_column(th, L0, L1, 82))
    # detail column: its bar is the vertical strip
    b.append(inspector(th, R0, R1, 30, close=False, actions=False))
    b.append(vstrip(th, IN_W, IN_H, items=[('bell', 'Watch train', True), ('share', 'Share ETA')], tab='Journeys'))
    return device('inner', th, ''.join(b))

# ================================================================ 4. inner landscape: round trip
def inner_roundtrip(th):
    b = []
    acc = th['amber'] if th['name'] == 'dark' else th['ink']
    lw, rw = L1 - L0, R1 - R0
    b.append(abs_div(L0, 30, lw, f'<span style="{mono(12, 700, acc, 1.8)}">① OUTBOUND</span><div style="margin-top: 10px">{route_head("Voiron", "Grenoble", th, 26)}</div>'))
    b.append(abs_div(R0, 30, rw, f'<span style="{mono(12, 700, acc, 1.8)}">② WAY BACK</span><div style="margin-top: 10px">{route_head("Grenoble", "Voiron", th, 26)}</div>'))
    b.append(text_item(th, 'Today', IN_W - SAFE_IN, 22, lead_icon='cal'))
    ly = 132
    b.append(abs_div(L0, ly, lw, rt_list(OUT_ROWS[:5], th)))
    b.append(abs_div(R0, ly, rw, rt_list(BACK_ROWS, th)))
    py = ly + 40 + 29
    b.append(f'<div style="position: absolute; left: {L1}px; width: {R0 - L1}px; top: {py - 1}px; height: 0; border-top: 2px dashed {th["paper"]}; opacity: .9"></div>')
    day = (f'<div style="display: flex; flex-direction: column; gap: 6px; padding: 11px 14px; border-radius: 18px; background: {th["card"]}; border: 1px solid {th["hair"]}">'
           f'{caps("THE WHOLE DAY OUT", th, 10)}'
           f'<svg width="{lw - 30}" height="32" viewBox="0 0 {lw - 30} 32" role="img" aria-label="17:46 to 18:11 on the train, 2 h 31 in Grenoble, 20:42 to 21:07 back">'
           f'<rect x="0" y="12" width="{lw - 30}" height="9" rx="4.5" fill="{th["raised"]}"/>'
           f'<rect x="0" y="12" width="40" height="9" rx="4.5" fill="{th["amber"]}"/><rect x="{lw - 70}" y="12" width="40" height="9" rx="4.5" fill="{th["amber"]}"/>'
           f'<text x="0" y="8" font-family="JetBrains Mono" font-size="10" font-weight="600" fill="{th["ink2"]}">17:46</text>'
           f'<text x="{(lw - 30) / 2}" y="8" text-anchor="middle" font-family="JetBrains Mono" font-size="10" font-weight="700" fill="{th["ink"]}">2 h 31 IN GRENOBLE</text>'
           f'<text x="{lw - 30}" y="8" text-anchor="end" font-family="JetBrains Mono" font-size="10" font-weight="600" fill="{th["ink2"]}">21:07</text>'
           f'<text x="0" y="31" font-family="JetBrains Mono" font-size="9.5" fill="{th["ink2"]}">25 min</text>'
           f'<text x="{lw - 30}" y="31" text-anchor="end" font-family="JetBrains Mono" font-size="9.5" fill="{th["ink2"]}">25 min</text></svg></div>')
    b.append(abs_div(L0, 440, lw, day))
    step = (f'<div style="display: flex; align-items: center; justify-content: space-between; padding: 9px 10px 9px 16px; border-radius: 18px; background: {th["card"]}; border: 1px solid {th["hair"]}">'
            f'<span style="display: flex; flex-direction: column; gap: 1px">{caps("STAY AT LEAST", th, 10)}<span style="{mono(22, 700)}">2 h 30</span></span>'
            f'<span style="display: flex; gap: 6px">'
            + ''.join(f'<span style="width: 42px; height: 42px; border-radius: 21px; background: {th["raised"]}; display: flex; align-items: center; justify-content: center">{icon(i, 16, 2.6)}</span>' for i in ('minus', 'plus'))
            + f'</span></div><div style="font-size: 11.5px; line-height: 1.4; color: {th["ink2"]}; margin-top: 8px">Watch both trains (the bell): if the 20:42 is cancelled or late, you get the next one that fits.</div>')
    b.append(abs_div(R0, 440, rw, step))
    b.append(vstrip(th, IN_W, IN_H, items=[('back', 'Grenoble → Voiron'), ('bell', 'Watch both trains', True), ('share', 'Share the plan')], tab='Journeys'))
    return device('inner', th, ''.join(b))

# ================================================================ 5. inner landscape: station, list | river
def inner_station(th):
    b = [column_rule(th)]
    lw = L1 - L0
    b.append(text_item(th, 'Find me!', IN_W - L1, 20))
    b.append(large_title(th, 'Near me', L0, 74, lead='antenna'))
    b.append(abs_div(L0, 126, lw, hero_station(th, lw, track=False)))
    b.append(abs_div(L0, 266, lw, track_rule('THEN', th)))
    rows = station_departures()[1:9]
    b.append(scroll(L0 - 16, 286, lw + 32, ''.join(station_row(r, th, selected=(r['t'] == '18:16'), pad=16) for r in rows)))
    rw = R1 - R0
    b.append(abs_div(R0, 30, rw, f'<div style="display: flex; align-items: center; justify-content: space-between">'
             f'<span style="display: flex; flex-direction: column; gap: 2px">{caps("LINES FROM VOIRON", th, 10)}'
             f'<span style="{mono(10.5, 500, th["ink2"])}">5 directions · next 90 min</span></span>'
             f'<span style="display: flex; border-radius: 10px; background: {th["raised"]}; padding: 3px">'
             f'<span style="padding: 5px 9px; border-radius: 7px; background: {th["card"]}; {mono(10.5, 700, th["ink"], 1)}; white-space: nowrap">NEXT 90′</span>'
             f'<span style="padding: 5px 9px; {mono(10.5, 600, th["ink2"], 1)}">TONIGHT</span></span></div>'))
    b.append(river(th, R0 - 4, 86, rw + 6, 540, span=90))
    b.append(abs_div(R0, IN_H - 34, rw, f'<div style="display: flex; justify-content: space-between; {mono(9.5, 500, th["ink2"])}">'
             f'<span>Tap a train or a terminus</span><span>Data © SNCF · not affiliated</span></div>'))
    b.append(vstrip(th, IN_W, IN_H, items=[('refresh', 'Refresh'), ('tv', 'Wall')], tab='Near me'))
    return device('inner', th, ''.join(b))

# ================================================================ 6. inner portrait, flat: the journey again
def portrait_journey(th):
    W, H = P_W, P_H
    half = W / 2
    b = [status_bar(th, 'portrait', 34), column_rule(th, half, H)]
    b.append(hbar_back(th, 'Journeys', 16, 36))
    b.append(hbar_icons(th, [('pair', 'Round trip'), ('swap', 'Swap direction'), ('tv', 'Wall')], half - 16, 36))
    b.append(hbar_icons(th, [('bell', 'Watch train', True), ('share', 'Share ETA')], W - 16, 36))
    b.append(board_column(th, 16, half - 16, 96, flap=(28, 42, 26), num=False, rows_pad=12,
                          hero=narrow_hero(th, half - 32, (28, 42, 26), 'ARRIVES 18:07', '25 min on board').replace(f'{chip("TER", th)}<span', '<span'),
                          rows=JOURNEY + EVENING))
    # the stopping pattern sits in TrainInspector's ScrollView, so it may cross the fold like a list
    b.append('<div data-scroll="1">' + inspector(th, half + 16, W - 16, 96, close=False, actions=False, H=H - 86) + '</div>')
    b.append(htabs(th, 'Journeys', W / 2, H - 92))
    b.append(home_indicator(th, W / 2, H - 9))
    return device('portrait', th, ''.join(b))

# ================================================================ 7. tabletop: Wall as a desk clock
def tabletop(th):
    W, H = P_W, P_H
    b = []
    dark = th['name'] == 'dark'
    top_end, bot_start = FOLD - GUTTER, FOLD + GUTTER
    b.append(f'<div style="position: absolute; left: 0; top: 0; width: {W}px; height: {H}px; background: {th["wall"]}"></div>')
    head = (f'<div style="display: flex; align-items: flex-start; justify-content: space-between">'
            f'<div style="display: flex; flex-direction: column; gap: 4px">{caps("→ DEPARTURES · YOUR JOURNEY", th, 11, None, 2)}'
            f'<span style="font-size: 40px; font-weight: 800; letter-spacing: -0.8px; line-height: 1.05">Grenoble → Voiron</span></div>'
            f'<div style="display: flex; flex-direction: column; align-items: flex-end; gap: 6px">'
            f'{flaps("17:40", th, 34, 48, 32, 3, digit=th["clockdigit"], bg="#23262B" if dark else "#16171A", colon=th["ink2"])}'
            f'{caps("FRI 16 OCT", th, 10, None, 1.6)}</div></div>')
    b.append(abs_div(30, 36, W - 60, head))
    leave = (f'<div style="width: 300px; height: 236px; box-sizing: border-box; border-radius: 26px; background: #F5C04F; color: #0E0F11; padding: 18px 20px; display: flex; flex-direction: column; justify-content: space-between">'
             f'<span style="{mono(12, 800, "#0E0F11", 2.2)}">LEAVE HOME IN</span>'
             f'<div style="display: flex; align-items: flex-end; gap: 12px">{flaps("38", th, 70, 100, 70, 6, digit="#FFC23D", bg="#0E0F11")}'
             f'<span style="{mono(13, 800, "#0E0F11", 1.6)}; padding-bottom: 6px">MIN</span></div>'
             f'<div style="display: flex; flex-direction: column; gap: 3px; {mono(13, 600, "#0E0F11")}">'
             f'<span style="display: flex; gap: 6px; align-items: center">{icon("train", 15, 2.2)}the 18:24 · TER 17655, +12</span>'
             f'<span style="display: flex; gap: 6px; align-items: center">{icon("walk", 15, 2.2)}6 min walk to the platform</span></div></div>')
    nxt = (f'<div style="flex: 1; height: 236px; box-sizing: border-box; border-radius: 26px; background: {th["card"]}; border: 1px solid {th["hair"]}; padding: 18px 20px; display: flex; flex-direction: column; justify-content: space-between">'
           f'{caps("NEXT TRAIN", th, 11, None, 2)}<div>{flaps("17:42", th, 44, 64, 42, 4)}</div>'
           f'<div style="display: flex; flex-direction: column; gap: 4px"><span style="display: flex; gap: 6px; align-items: center">{chip("TER", th)}<span style="{mono(12, 500, th["ink2"])}">N° 17653 · arr. 18:07</span></span>'
           f'<span style="{mono(15, 700, th["clear"])}">in 2 min · too tight to walk</span></div></div>')
    b.append(abs_div(30, 128, W - 60, f'<div style="display: flex; gap: 14px">{leave}{nxt}</div>'))
    b.append(abs_div(30, 392, W - 60, time_track(th, W - 60, journey_track_deps(), scale=1.15)))
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
        rows.append(f'<div style="display: flex; align-items: center; gap: 16px; height: 56px; padding: 0 30px; border-top: {"0" if i == 0 else "1px"} solid {th["hair"]}; {sel}">{digits}'
                    f'<span style="display: flex; flex-direction: column; {"opacity: .6;" if canc else ""}"><span style="font-size: 18px; font-weight: 700; {"text-decoration: line-through;" if canc else ""}">Voiron{mark}</span>'
                    f'<span style="{mono(11, 500, th["ink2"])}">arrives {arr} · TER {num}</span></span><span style="margin-left: auto">{right}</span></div>')
    b.append(scroll(0, bot_start + 10, W, ''.join(rows)))
    tick = (f'<div style="display: flex; align-items: center; gap: 12px; height: 26px; {mono(11.5, 500, th["ink"])}">'
            f'<span style="flex: none; padding: 4px 10px; border-radius: 6px; background: repeating-linear-gradient(-45deg, {th["amber"]} 0 6px, #0E0F11 6px 12px)">'
            f'<span style="display: block; {mono(10, 800, th["amber"], 1.4)}; background: #0E0F11; padding: 2px 6px; border-radius: 4px">INFO</span></span>'
            f'<span style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis">18:42 cancelled · 19:42 runs 24 min late · Chambéry: no service</span></div>')
    b.append(abs_div(30, bot_start + 10 + 5 * 56 + 18, W - 60, tick))
    # .toolbar(placement: .bottomBar): system glass, horizontal because this is the inner display in portrait
    by = H - 24 - 50
    def pillbtn(inner, label=''):
        return (f'<span aria-label="{label}" style="height: 50px; padding: 0 16px; border-radius: 25px; {glass(th)} display: inline-flex; align-items: center; gap: 7px; '
                f'font: 600 15px {SANS}; box-sizing: border-box; white-space: nowrap">{inner}</span>')
    ctrl = (f'<div class="chrome" style="position: absolute; left: 24px; right: 24px; top: {by}px; display: flex; align-items: center; gap: 10px">'
            f'{pillbtn(icon("route", 17) + "Grenoble → Voiron" + icon("down", 13, 2.6), "Journey")}'
            f'{pillbtn(icon("walk", 17) + "6 min" + icon("down", 13, 2.6), "Walking time")}'
            f'<span style="margin-left: auto; display: flex; gap: 10px">'
            f'<span style="width: 50px; height: 50px; border-radius: 25px; {glass(th)} display: flex; align-items: center; justify-content: center" aria-label="Keep the screen awake">{icon("sun", 20)}</span>'
            f'<span style="width: 50px; height: 50px; border-radius: 25px; {glass(th)} display: flex; align-items: center; justify-content: center" aria-label="Leave Wall">{icon("x", 18, 2.4)}</span></span></div>')
    b.append(ctrl)
    b.append(home_indicator(th, W / 2, H - 9))
    return device('tabletop', th, ''.join(b))

# ================================================================ 8. navigation
def lanes_detail(th, x0, x1, lane_top, lane_h, gap, head_y=30):
    rw = x1 - x0
    k = rw / LANE_SPAN
    out = []
    axis = []
    for m in (NOW, 18 * 60, 18 * 60 + 30, 19 * 60, 19 * 60 + 30):
        x = (m - LANE_T0) * k
        if m == NOW:
            axis.append(f'<span style="position: absolute; left: {max(x - 32, 0)}px; top: 0; {mono(9.5, 700, th["papertext"] if th["name"] == "dark" else "#16171A")}; background: {th["paper"] if th["name"] == "dark" else th["amber"]}; padding: 2px 5px; border-radius: 4px; white-space: nowrap">NOW 17:40</span>')
        elif (m - NOW) * k > 62:
            axis.append(f'<span style="position: absolute; left: {x - 20}px; width: 40px; text-align: center; top: 2px; {mono(9.5, 500, th["ink2"])}">{hhmm(m)}</span>')
    out.append(abs_div(x0, head_y, rw, f'<div style="display: flex; align-items: center; justify-content: space-between">'
               f'<span style="display: flex; flex-direction: column; gap: 2px">{caps("LANES", th, 10.5, th["ink"], 1.8)}<span style="{mono(10.5, 500, th["ink2"])}; white-space: nowrap">departure → arrival</span></span>'
               f'<span style="display: flex; border-radius: 10px; background: {th["raised"]}; padding: 3px">'
               f'<span style="padding: 5px 9px; border-radius: 7px; background: {th["card"]}; {mono(10.5, 700, th["ink"], 1)}; white-space: nowrap">NEXT 2 H</span>'
               f'<span style="padding: 5px 9px; {mono(10.5, 600, th["ink2"], 1)}">TONIGHT</span></span></div>'))
    out.append(abs_div(x0, lane_top - 26, rw, ''.join(axis), h=18, extra='position: absolute'))
    n = len(JLIST)
    out.append(''.join(f'<div style="position: absolute; left: {x0 + (m - LANE_T0) * k:.1f}px; top: {lane_top - 6}px; width: 1px; height: {n * (lane_h + gap)}px; background: {th["grid"]}"></div>' for m in (18 * 60, 18 * 60 + 30, 19 * 60, 19 * 60 + 30)))
    out.append(f'<div style="position: absolute; left: {x0 + (NOW - LANE_T0) * k:.1f}px; top: {lane_top - 6}px; height: {n * (lane_h + gap)}px; border-left: 1.5px dashed {th["ink2"]}; opacity: .7"></div>')
    for i, j in enumerate(JLIST):
        y = lane_top + i * (lane_h + gap)
        selbg = f'background: {th["sel"]};' if i == 0 else ''
        out.append(f'<div style="position: absolute; left: {x0 - 8}px; width: {rw + 16}px; top: {y}px; height: {lane_h}px; border-radius: 14px; {selbg}"></div>')
        out.append(abs_div(x0, y, rw, lane_track(th, j, x0, rw, lane_h), h=lane_h, extra='position: absolute; overflow: hidden'))
    sw = lambda st: f'<span style="width: 14px; height: 9px; border-radius: 3px; {st}; box-sizing: border-box"></span>'
    leg = (f'<div style="display: flex; flex-wrap: wrap; gap: 6px 12px; align-items: center; white-space: nowrap; {mono(9.5, 500, th["ink2"])}">'
           + ''.join(f'<span style="display: inline-flex; gap: 4px; align-items: center">{sw(st)}{lab}</span>' for st, lab in (
               (f'background: {th["amber"]}', 'next'), (f'background: {th["barink"]}', 'on time'),
               (f'background: {th["caubg"]}; box-shadow: inset 0 0 0 1.5px {th["cau"]}', 'late'),
               (f'border: 1.2px dashed {th["ink2"]}', 'timetabled'), (f'border: 1.2px dashed {th["stop"]}; background: {th["stopbg"]}', 'cancelled')))
           + '</div>')
    out.append(abs_div(x0, IN_H - 40, rw, leg))
    return ''.join(out)

def journeys_cards(th, x0, w, top, lane_h, gap):
    return ''.join(abs_div(x0, top + i * (lane_h + gap), w, journey_card(th, j, w, lane_h, selected=(i == 0))) for i, j in enumerate(JLIST))

def nav_a(th):
    b = [column_rule(th)]
    lane_top, lane_h, gap = 132, 96, 10
    b.append(hbar_icons(th, [('plus', 'Add a journey')], L1, 20))
    b.append(text_item(th, 'Edit', IN_W - (L1 - 52), 20))
    b.append(large_title(th, 'Journeys', L0, 22))
    b.append(updated(th, L0, 84))
    b.append(scroll(L0, lane_top, L1 - L0, journeys_cards(th, 0, L1 - L0, 0, lane_h, gap).replace('position: absolute; left: 0px; top: ', 'position: absolute; left: 0px; top: ')))
    b.append(lanes_detail(th, R0, R1, lane_top, lane_h, gap))
    b.append(vstrip(th, IN_W, IN_H, items=[('tv', 'Wall'), ('pair', 'Round trip')], tab='Journeys'))
    return device('inner', th, ''.join(b))

def nav_a_folded(th):
    W = OUT_W
    b = [vstrip(th, W, OUT_H, items=[('plus', 'Add a journey'), ('lanes', 'Lanes')], tab='Journeys', island=True)]
    b.append(text_item(th, 'Edit', W - SAFE_OUT, 24))
    b.append(large_title(th, 'Journeys', L0, 26))
    b.append(updated(th, L0, 92))
    b.append(scroll(L0, 122, SAFE_OUT - L0, ''.join(f'<div style="margin-bottom: 10px">{journey_card(th, j, SAFE_OUT - L0, 92, selected=False)}</div>' for j in JLIST)))
    return device('outer', th, ''.join(b))

def nav_b(th):
    b = []
    sw = FOLD   # sidebar pinned to the fold so the columns stay even
    bg = th['card'] if th['name'] == 'light' else '#141518'
    b.append(f'<div style="position: absolute; left: 0; top: 0; width: {sw}px; height: {IN_H}px; background: {bg}"></div>')
    b.append(column_rule(th))
    b.append(circle_item(th, 'sidebar', 'Hide sidebar', L1 - 44, 20, 44))
    def row(ic, lab, on=False, sub=None):
        col = T(th) if on else th['ink']
        sel = f'background: {th["tabsel"]};' if on else ''
        s = f'<span style="margin-left: auto; {mono(10.5, 500, th["ink2"])}">{sub}</span>' if sub else ''
        return (f'<div style="display: flex; align-items: center; gap: 12px; height: 42px; padding: 0 12px; border-radius: 12px; {sel}">'
                f'<span style="color: {col}; display: flex">{icon(ic, 20, 2.1)}</span><span style="font-size: 16px; font-weight: {600 if on else 500}; color: {th["ink"]}">{lab}</span>{s}</div>')
    head = lambda t: f'<div style="{mono(10.5, 700, th["ink2"], 1.4)}; padding: 16px 12px 6px">{t}</div>'
    side = (f'<div style="font-size: 30px; font-weight: 800; letter-spacing: -0.3px; padding: 0 12px 6px">Trains</div>'
            + row('antenna', 'Near me', sub='Voiron · 400 m') + row('route', 'Journeys') + row('sliders', 'Settings')
            + head('VIEWS') + row('rectangle' if 'rectangle' in ICONS else 'wall', 'Station hall') + row('lanes', 'Lanes', True) + row('pair', 'Round trip') + row('tv', 'Wall')
            + head('JOURNEYS') + ''.join(row('route', f'{j["o"]} → {j["d"]}', sub=j['nxt'] or '—') for j in JLIST))
    b.append(abs_div(L0 - 12, 72, L1 - L0 + 24, side))
    b.append(lanes_detail(th, R0, R1, 132, 96, 10))
    b.append(vstrip(th, IN_W, IN_H, items=[('tv', 'Wall')], tab=None))
    return device('inner', th, ''.join(b))

# ================================================================ captions, facts, pages
def posture_icon(kind):
    s = '#3A3631'
    if kind == 'outer':
        gl = f'<rect x="14" y="4" width="20" height="32" rx="4" fill="none" stroke="{s}" stroke-width="2"/><path d="M14 8v24" stroke="{s}" stroke-width="4"/><rect x="29" y="9" width="3" height="22" rx="1.5" fill="{s}"/>'
    elif kind == 'inner':
        gl = f'<rect x="4" y="8" width="40" height="26" rx="4" fill="none" stroke="{s}" stroke-width="2"/><path d="M24 8v26" stroke="{s}" stroke-width="1.5" stroke-dasharray="2 2"/><rect x="39" y="12" width="2.6" height="18" rx="1.3" fill="{s}"/>'
    elif kind == 'portrait':
        gl = f'<rect x="10" y="2" width="28" height="36" rx="4" fill="none" stroke="{s}" stroke-width="2"/><path d="M10 20h28" stroke="{s}" stroke-width="1.5" stroke-dasharray="2 2"/><rect x="16" y="33" width="16" height="2.4" rx="1.2" fill="{s}"/>'
    else:
        gl = f'<path d="M8 36h22M8 36l14-26" stroke="{s}" stroke-width="3" stroke-linecap="round" fill="none"/><path d="M4 38h40" stroke="#A9A69E" stroke-width="1.5"/>'
    return f'<svg width="48" height="40" viewBox="0 0 48 40" aria-hidden="true">{gl}</svg>'

def caption_block(s):
    lab = lambda t: f'<dt style="{mono(10.5, 700, "#66645E", 1.4)}; padding-top: 3px">{t}</dt>'
    rows = ''.join(lab(k) + f'<dd style="margin: 0">{s[k.lower()]}</dd>' for k in ('REUSED', 'MOVED', 'RULE', 'BUILD'))
    return (f'<header style="display: flex; gap: 28px; align-items: flex-start">'
            f'<div style="flex: 0 0 320px; display: flex; gap: 12px; align-items: flex-start">{posture_icon(s["posture"])}<div>'
            f'<div style="{mono(11.5, 700, "#66645E", 1.6)}">{s["eyebrow"]}</div><h2 style="margin: 3px 0 0; font-size: 30px; line-height: 1.1; color: #16171A">{s["title"]}</h2></div></div>'
            f'<dl style="margin: 0; flex: 1; display: grid; grid-template-columns: 70px 1fr; gap: 6px 14px; font-size: 14.5px; line-height: 1.45; color: #16171A">{rows}</dl></header>')

def figure(res, label):
    return (f'<figure style="margin: 0; display: flex; flex-direction: column; gap: 10px"><div style="position: relative">{res}</div>'
            f'<figcaption style="{mono(11, 600, "#66645E", 1.4)}">{label}</figcaption></figure>')

def pair(fn):
    return [figure(fn(TH['dark']), 'BOARD · DARK'), figure(fn(TH['light']), 'TIMETABLE · LIGHT')]

SCREENS = []
FW = {'outer': OUT_W + 22, 'inner': IN_W + 22, 'portrait': P_W + 22, 'tabletop': P_W + 22}
def S_(slug, eyebrow, title, posture, reused, moved, rule, build, frames, fw=None):
    SCREENS.append(dict(slug=slug, eyebrow=eyebrow, title=title, posture=posture, reused=reused, moved=moved, rule=rule, build=build, frames=frames,
                        fw=max(fw or 2 * FW[posture] + 44, 1100)))

S_('folded-nearme', '1 · FOLDED · OUTER 466×678', 'Near me, folded', 'outer',
   'The Near me tab as it ships: the antenna title, “Find me!”, the split-flap hero (nearest station, distance, freshness), the THEN rule and the board rows with their direction swatch.',
   'Nothing of ours moved; the system did. Status, the Lines toolbar item and the three tabs sit in the trailing strip, so the content column is 20 → 382 pt (362 wide, a little less than an iPhone 17 Pro). The hero goes sideways (flaps left, destination beside) because height is the scarce axis: eight departures stay visible.',
   'Fact 1: compact width, vertical strip on the trailing edge, tab capsule at 492–654. “Find me!” is text-only, so it stays horizontal at the top trailing corner of the content, exactly as on the device screenshot. Rows scroll under the strip’s background, never under its controls.',
   '<code>RootView</code> unchanged (<code>TabView</code> + <code>NavigationStack</code>). The river becomes a toolbar item: <code>ToolbarItem { Button { … } label: { Label("Lines", systemImage: "point.3.connected.trianglepath.dotted") } }</code>; a <code>Label</code> is what lets the system stand it up in the strip.',
   lambda: pair(folded_nearme))
S_('folded-journey', '2 · FOLDED · OUTER 466×678', 'A journey board, folded', 'outer',
   'The Tableau journey board: route glyph, DIRECT ONLY / REVERSES AT 13:00 chips, the flap hero with the time track, rows depart ┄ arrive with NEXT, +12 “leaves 18:24”, CANCELLED, +24.',
   'Back, Round trip, Swap and Wall are toolbar items, so they stack in the strip in navigation order: Back first, then the prominent action (Round trip, amber glass), then the rest. The route header takes the top of the content because no horizontal bar is left there. Rows drop the train number (the inspector has it) so status never truncates at 362 pt. All six of the evening’s trains fit.',
   'Fact 1 and 7: icon-only circles, primary navigation first. The hero’s own bell is gone; “Watch” lives on the train, one tap further.',
   '<code>.toolbar { ToolbarItem(placement: .primaryAction) { Button("Round trip", systemImage: "arrow.left.arrow.right") { … }.buttonStyle(.glassProminent) } … }</code>. No layout code reads the strip: <code>.safeAreaInset</code> comes from the system. Read <code>@Environment(\\.toolbarVerticalEdge)</code> only if a custom control has to mirror it.',
   lambda: pair(folded_journey))
S_('inner-journey', '3 · INNER · LANDSCAPE 951×669 · FLAT', 'Journey: board | train', 'inner',
   'The station hall’s board (route header, chips, flap hero + time track, rows with the amber selection bar) and the <code>TrainInspector</code> (N°, LEAVES / YOU ARRIVE / DELAY tiles, STOPS, your leg solid, SNCF Connect link).',
   'Two columns split at the fold, 475.5 pt each. The board column keeps a horizontal bar: Back on the leading side, Round trip and Swap on the trailing side. The train is the detail column: its bar is the vertical strip, with Watch train as the prominent item, then Share ETA and Wall, and the three tabs below. The inspector’s Watch / Share buttons left its body, since the strip now carries them.',
   'Fact 2: in a split view only the detail column’s bar goes vertical. Even columns, nothing on the fold but the column hairline. The detail column’s content (495 → 867, 372 pt) is the same width as the folded content, so the train screen pushed on the outer display and this column are one layout.',
   '<code>NavigationSplitView(columnVisibility: .constant(.all)) { board.navigationSplitViewColumnWidth(half) } detail: { TrainInspector(…) }</code>, with <code>half</code> from <code>GeometryReader</code> + <code>proxy.reservedRegions(kind: .division, options: .includeInactive)</code> (the flat fold is inactive with zero width, so use its <code>frame.midX</code>). Compact width collapses it to the folded push.',
   lambda: pair(inner_journey))
S_('inner-roundtrip', '4 · INNER · LANDSCAPE 951×669 · FLAT', 'Round trip: outbound | way back', 'inner',
   'Round trip as designed: ① OUTBOUND with the picked train and “✓ 2 h 31 THERE”, THE WHOLE DAY OUT; ② WAY BACK with TOO EARLY, FIRST THAT FITS, “+30 there”, LAST TRAIN, the STAY AT LEAST stepper. The paper tabs on the inner edges of the two picked rows, and only the dashed tie crosses the fold.',
   'The screen’s actions are toolbar items in the strip: Back, Watch both trains (prominent, it replaces the big amber button), Share the plan. The day picker “Today” has a title, so it stays horizontal at the content’s top trailing corner. The way-back column is 372 pt (the strip’s safe area), the outbound 435: the columns are even, their safe areas are not.',
   'Fact 2 and 5: symmetric columns either side of the fold, nothing important across the centre. In book posture this split is unchanged; the share sheet moves to the trailing side by itself.',
   '<code>ArrangementView { OutboundPane() } secondary: { ReturnPane() }.arrangementViewStyle(.split.axes(.horizontal))</code> replaces <code>RoundTripView.twoPane</code>’s <code>HStack</code> + <code>minTwoPaneWidth</code>; folded, it is the existing <code>narrow</code> push. The tie is the only thing placed by hand, at the division’s <code>frame</code>.',
   lambda: pair(inner_roundtrip))
S_('inner-station', '5 · INNER · LANDSCAPE 951×669 · FLAT', 'Station: departures | river', 'inner',
   'Near me (title, Find me!, hero flaps, THEN, board rows) on the left; StationLines variant B on the right: the amber source, the S-curves, west above and east below the NOW axis, ghost slots with dashed arcs, the hollow ✕.',
   'The Near me tab becomes a split: departures | lines. Find me! stays a horizontal text button in the leading column’s bar. The river is the detail, so its Refresh and Wall items stand in the strip with the tabs. The river window shrinks to 90 min to keep a train label every 2.5 pt per minute at 372 pt; the selected row (18:16 +24) rings its dot on the map.',
   'Fact 2: detail bar vertical, leading bar horizontal; the two columns are linked by selection, never by a line across the fold.',
   'Same <code>NavigationSplitView</code> as screen 3 inside the Near me tab. <code>StationLinesBoard</code> is reused; its <code>MapGeometry</code> already lays out from the size it gets, only the time span becomes a parameter.',
   lambda: pair(inner_station))
S_('portrait-journey', '6 · INNER · PORTRAIT 669×951 · FLAT', 'The journey again, standing up', 'portrait',
   'Screen 3, item for item: the same two columns, the same board, the same train, the same toolbar items in the same columns.',
   'Only the bars change. The strip’s items fold back into the detail column’s own horizontal bar (Watch, Share, Wall, top trailing of the train column), the tabs go to the bottom bar, the status bar returns to the top. The columns narrow to 334.5 pt, so the rows drop the train number and the hero uses 28 pt flaps. The fold is now horizontal at y 475.5 and only crosses the scrolling lists.',
   'Fact 3: regular width in portrait brings back standard horizontal bars; “move only what’s necessary”. Columns stay left / right rather than stacking, so the train you tapped is where it was.',
   'No code: the same <code>NavigationSplitView</code>, the system re-lays the bars. The column width is <code>proxy.size.width / 2</code> here, the division being horizontal.',
   lambda: pair(portrait_journey))
S_('tabletop', '7 · TABLETOP · INNER PORTRAIT, PARTIALLY OPEN', 'Wall as a desk clock', 'tabletop',
   'Wall mode as built: the split-flap clock, LEAVE HOME IN with 70×100 flaps, the next-train card, the time track at desk scale, flap rows with grey tiles for the cancelled 18:42, the INFO hazard ticker.',
   'The standing half holds what you read from across the room: clock, LEAVE HOME IN, the next train, the evening on the track. The lying half holds the five next trains, the ticker and the controls (journey, walking time, keep awake, leave) as a system bottom bar where a finger lands. The division band is excluded from layout; nothing is drawn in it.',
   'Fact 4: glanceable top, interactive bottom, the scrolling list stays put. Fact 6: Wall is immersive and full-bleed, so the status bar is hidden and the clock replaces it; the background runs edge to edge, content keeps a 24 pt inset.',
   '<code>WallModeView</code> in a <code>.fullScreenCover</code>, <code>.statusBarHidden()</code>, <code>.persistentSystemOverlays(.hidden)</code>, controls in <code>ToolbarItemGroup(placement: .bottomBar)</code>. <code>ArrangementView { WallGlance() } secondary: { WallBoard() }</code> splits at the active division; <code>.onHingeChange</code> only animates the flaps when the angle settles, never picks the layout.',
   lambda: pair(tabletop))
S_('nav-A', '8A · NAVIGATION · RECOMMENDED', 'Three tabs; the big views are the detail column', 'inner',
   'The three tabs, unchanged. Journeys cards (route glyph, direction rule, next time or NO SERVICE) and Lanes, each lane on the row of its card.',
   'Every big-screen view lives inside a tab instead of beside them: Station hall is a board with its train (screen 3), Lanes is the detail of the Journeys list, the river is the detail of Near me, Round trip and Wall are toolbar items. Folded, the split collapses: Lanes becomes a strip item next to “+”, the same way Lines does on Near me.',
   'Fact 8: the system already answers navigation, so the app adds no bar of its own. Folding and unfolding keep you in the same tab, on the same journey, with the same selection.',
   'Journeys tab: <code>NavigationSplitView { JourneysList() } detail: { selection == nil ? LanesView() : TrainInspector() }</code>. Wall: <code>.fullScreenCover</code> from a toolbar <code>Label("Wall", systemImage: "tv")</code>.',
   lambda: pair(nav_a) + [figure(nav_a_folded(TH['light']), 'FOLDED · LIGHT')], fw=2 * FW['inner'] + FW['outer'] + 88)
S_('nav-B', '8B · NAVIGATION · CONSIDERED', 'A sidebar tab view', 'inner',
   'The station-hall sidebar idea, as the system draws it: <code>TabView</code> with <code>.tabViewStyle(.sidebarAdaptable)</code>, a VIEWS section (Station hall, Lanes, Round trip, Wall) and the saved journeys.',
   'On the inner display the tab capsule disappears into a sidebar pinned to the leading half; the strip keeps only status and the detail’s items. Every view is one tap away.',
   'It obeys the rules (even columns, detail bar vertical), but every big view now gets one half: the board and its train cannot be side by side any more, so the train goes back to a sheet. Folded, the same tabs must fit the 162 pt capsule: seven tabs do not, so they fall back to a More tab. Rejected.',
   '<code>TabView { Tab("Near me", …) … TabSection("Views") { Tab("Lanes", …) … } }.tabViewStyle(.sidebarAdaptable)</code>, the shape of <code>BigScreenSidebar</code> rebuilt as tabs.',
   lambda: pair(nav_b))

SOURCES = [
  ('Human Interface Guidelines · Designing for iPhone Duo', None),
  ('Apple Developer documentation · Preparing your app for iPhone Duo', None),
  ('Tech Talk 111462', 'https://developer.apple.com/videos/play/tech-talks/111462/'),
  ('Tech Talk 111463 · Strike a pose with adaptive layouts on iPhone Duo', 'https://developer.apple.com/videos/play/tech-talks/111463/'),
  ('iOS 27.1 SDK · SwiftUICore.swiftinterface (Xcode 27.1)', None),
  ('Device screenshots of this app, folded (11-clean-tab0/1, 10-clean-settings)', None),
]

FACTS = [
  ('Outer display, folded', '466×678 pt (1398×2034 px @3x), compact width. System chrome is a full-height strip on the trailing edge, ~48 pt wide, centred at x ≈ 418; the content’s trailing safe edge is ~382 pt; the leading margin ~20 pt.',
   'Top to bottom: camera corner + Dynamic Island, status (time over Wi-Fi/battery), toolbar items as 48 pt icon-only circles (primary navigation first: Back/Close, then the prominent action), and the tab bar as a vertical capsule at y ≈ 492–654. Text-only toolbar buttons (“Edit”, “Find me!”) stay horizontal, top trailing of the content.', 'Screenshots; HIG; Tech Talk 111462'),
  ('Inner display, landscape, flat', '951×669 pt, regular width. Controls stay on the side: the same vertical trailing strip (not a sidebar, not a bottom bar). The fold at x = 475.5 is a .division region, inactive with zero width when flat: no inset, but keep the centre clear for partial opening.',
   'Use even column counts. In split views only the detail column’s bar goes vertical; other columns and inspectors keep horizontal bars.', 'HIG; Tech Talk 111463'),
  ('Inner display, portrait', '669×951 pt, regular width. Standard horizontal bars come back: navigation bar on top, the iOS tab bar at the bottom. The fold is horizontal at y = 475.5.',
   'Keep controls’ relative positions across poses: “don’t reinvent your app when it resizes”, “move only what’s necessary”.', 'HIG'),
  ('Tabletop', 'Inner portrait, partially open. The fold is an active .division reserved region, excluded from layout.',
   'Glanceable content (read from a distance) in the top region, interactive controls in the bottom region. Scrolling lists stay put.', 'HIG; Tech Talk 111463'),
  ('Book', 'Partially open, landscape.', 'Alerts and sheets move to the trailing side. Split views keep symmetric columns either side of the fold.', 'HIG'),
  ('Full-bleed', 'Allowed for immersive, non-scrolling views (our Wall).', 'Nothing may collide with the camera, the Dynamic Island or the status bar. Backgrounds may run under the strip; content stays inset.', 'HIG'),
  ('No custom bars', 'TabView / NavigationSplitView / .toolbar only, so the system can stand bars up.', 'Every toolbar item has a title and an SF Symbol (Label) so it can go vertical; a hand-made HStack of buttons does not move.', 'Preparing your app; Tech Talk 111462'),
  ('Layout APIs', 'ArrangementView(primary:secondary:) with .split (side by side when wider, stacked when taller; .axes to pin) or .overlay; GeometryProxy.reservedRegions(kind: .division | .occlusion, options: .includeInactive) → frame, margins, isActive; @Environment(\\.toolbarVerticalEdge): HorizontalEdge?.',
   'onHingeChange(isEnabled:) { old, new in } → DeviceHingeContext.hinge?.status (.closed / .partiallyOpen / .fullyOpen) and .angle. The hinge is for animation, not layout: layout follows size classes and regions.', 'SwiftUICore.swiftinterface, iOS 27.1 SDK; Tech Talk 111463'),
]

ASSUMPTIONS = [
  'The Dynamic Island is drawn as a 32×50 pt pill at the top of the outer strip (y 14–64): the screenshots leave that 0–75 pt gap empty, they cannot show the hardware.',
  'On the inner display the strip has no island; status starts at y ≈ 28 and items at y ≈ 120. Where the inner camera’s .occlusion region sits is not known; nothing of ours is placed in the strip anyway.',
  'The inner landscape strip uses the outer metrics (48 pt wide, 84 pt trailing inset, capsule 24 pt above the bottom).',
  'The home indicator is drawn only in portrait; in the strip poses it is not visible in screenshots and its position is unconfirmed.',
  'The 24 pt gutter around the fold is our margin for partial opening, not a system value. In tabletop the active division is drawn 24 pt tall; the real height comes from reservedRegions.',
  'Prominent toolbar items are drawn as amber glass because the app tints with .tint(.amber).',
]

def facts_html():
    rows = ''.join(f'<tr><td><b>{a}</b></td><td>{b}</td><td>{c}</td><td style="color: #66645E">{d}</td></tr>' for a, b, c, d in FACTS)
    src = ''.join(f'<li>{f"<a href=\"{u}\" style=\"color: #16171A\">{t}</a>" if u else t}</li>' for t, u in SOURCES)
    asm = ''.join(f'<li>{a}</li>' for a in ASSUMPTIONS)
    return (f'<h2 style="font-size: 22px; margin: 0 0 8px">Fact sheet</h2>'
            f'<table style="border-collapse: collapse; font-size: 14px; line-height: 1.45; color: #16171A; width: 100%">'
            f'<tr><th style="text-align: left; width: 170px">Pose</th><th style="text-align: left; width: 34%">Geometry</th><th style="text-align: left">Rules</th><th style="text-align: left; width: 210px">Source</th></tr>{rows}</table>'
            f'<div style="display: flex; gap: 60px; margin-top: 18px; font-size: 14px; line-height: 1.5; color: #16171A">'
            f'<div style="flex: 1"><h3 style="font-size: 16px; margin: 0 0 4px">Sources</h3><ul style="margin: 0; padding-left: 18px">{src}</ul></div>'
            f'<div style="flex: 1.4"><h3 style="font-size: 16px; margin: 0 0 4px">What these mockups assume</h3><ul style="margin: 0; padding-left: 18px">{asm}</ul></div></div>')

CHECK_JS = '''
<script>
// Load-time checks, reported in #crease-check:
//  FOLD  - text inside the 24 pt gutter around the fold (scrolling lists are reported apart, as LIST, and allowed);
//  STRIP - non-chrome text past the content's trailing safe edge (382 pt folded, 867 pt inner landscape);
//  OVERLAP - non-chrome text under a piece of system chrome.
window.addEventListener('load', () => {
  const bad = [], lists = [];
  document.querySelectorAll('.screen').forEach((scr, si) => {
    const r = scr.getBoundingClientRect(), kind = scr.dataset.kind;
    const vertical = kind === 'inner', horizontal = kind === 'portrait' || kind === 'tabletop';
    const safe = kind === 'outer' ? r.left + 382 : kind === 'inner' ? r.left + 867 : null;
    const chrome = [...scr.querySelectorAll('.chrome')].map(e => e.getBoundingClientRect());
    const walker = document.createTreeWalker(scr, NodeFilter.SHOW_TEXT);
    let n;
    while ((n = walker.nextNode())) {
      const t = n.textContent.trim(); if (!t) continue;
      const el = n.parentElement; if (el.closest('.chrome')) continue;
      const range = document.createRange(); range.selectNodeContents(n);
      for (const b of range.getClientRects()) {
        if (b.width < 1) continue;
        const tag = si + ':' + t.slice(0, 24);
        if (vertical || horizontal) {
          const mid = vertical ? r.left + r.width / 2 : r.top + r.height / 2;
          const a0 = vertical ? b.left : b.top, a1 = vertical ? b.right : b.bottom;
          if (a1 > mid - 12 && a0 < mid + 12) (el.closest('[data-scroll]') && kind !== 'tabletop' ? lists : bad).push('FOLD ' + tag);
        }
        if (safe !== null && b.right > safe + 0.5 && b.top < r.bottom && b.bottom > r.top) bad.push('STRIP ' + tag);
        for (const c of chrome) if (b.right > c.left && b.left < c.right && b.bottom > c.top && b.top < c.bottom && b.top < r.bottom) { bad.push('OVERLAP ' + tag); break; }
      }
    }
  });
  const pre = document.createElement('pre'); pre.id = 'crease-check'; pre.style.display = 'none';
  const box = document.body.firstElementChild.getBoundingClientRect();
  pre.textContent = 'SIZE ' + Math.ceil(box.width) + 'x' + Math.ceil(box.height) + ' ' + (bad.length ? 'FAIL ' + [...new Set(bad)].join(' | ') : 'OK') + (lists.length ? ' (lists across the fold: ' + lists.length + ')' : '');
  document.body.appendChild(pre);
});
</script>'''

def html_doc(title, body, font_base, bg='#DCD8CF'):
    return (f'<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n<title>{title}</title>\n<style>{font_faces(font_base)}\n'
            f'body{{margin:0;background:{bg};font-family:{SANS};-webkit-font-smoothing:antialiased}} code{{font: 500 12.5px {MONO}}} '
            f'td,th{{padding: 7px 14px 7px 0; border-top: 1px solid #C9C2B4; vertical-align: top}}</style>\n</head>\n<body>\n{body}\n{CHECK_JS}\n</body>\n</html>\n')

def section(s):
    frames = s['frames']()
    return (f'<section id="{s["slug"]}" style="padding: 36px 40px 44px; display: flex; flex-direction: column; gap: 22px; width: {s["fw"]}px">'
            + caption_block(s) + f'<div style="display: flex; gap: 44px; align-items: flex-start">{"".join(frames)}</div></section>')

def main():
    os.makedirs(OUTDIR, exist_ok=True)
    secs = {s['slug']: section(s) for s in SCREENS}
    intro = (f'<header style="padding: 40px 40px 8px; max-width: 1900px; color: #16171A">'
             f'<div style="{mono(12, 700, "#66645E", 1.6)}">BIG SCREEN · IPHONE DUO · IOS 27.1 · ROUND 2</div>'
             f'<h1 style="margin: 6px 0 10px; font-size: 44px">Duo layouts</h1>'
             f'<p style="font-size: 16px; line-height: 1.5; max-width: 1250px; margin: 0 0 22px">Round 1 drew an iPhone tab bar centred at the bottom. On the Duo, iOS stands the status bar, the toolbar items and the tab bar up in a strip on the trailing edge, '
             f'folded and unfolded in landscape, and lays them flat again only on the inner display in portrait. These screens keep round 1’s components and screen ideas and draw the chrome where the system puts it, as system glass, not as our design. '
             f'All frames are at real point size; now is 17:40.</p>{facts_html()}'
             f'<p style="font-size: 14px; color: #3A3631; margin: 18px 0 0">The faint band and the grey ticks on each inner frame mark the fold. A load-time check (<code>#crease-check</code>) lists any text in the 24 pt fold gutter, past the strip’s safe edge, or under system chrome.</p></header>')
    toc = '<nav style="padding: 10px 40px; display: flex; gap: 18px; flex-wrap: wrap; font: 600 13px ' + MONO + '">' + ''.join(f'<a href="#{s["slug"]}" style="color: #16171A">{s["eyebrow"].split(" · ")[0]} {s["title"]}</a>' for s in SCREENS) + '</nav>'
    with open(OUTDIR + '/DuoLayouts.html', 'w') as f:
        f.write(html_doc('Duo layouts', intro + toc + ''.join(secs.values()), g.FONTDIR_REL))
    for slug, sec in secs.items():
        with open(f'{TMP}/{slug}.html', 'w') as f:
            f.write(html_doc(slug, sec, g.FONTDIR_ABS))
    with open(f'{TMP}/facts.html', 'w') as f:
        f.write(html_doc('facts', f'<div style="width: 1900px">{intro}</div>', g.FONTDIR_ABS))
    print(' '.join(secs))

if __name__ == '__main__':
    main()
