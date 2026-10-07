"""Genera ilustraciones PNG (fondo transparente) de las prendas del catálogo demo.

Cada prenda se exporta en dos vistas (frente y espalda, mismo recorte) junto con
su "rig": los puntos clave normalizados que usa el probador de realidad
aumentada para deformar la prenda con el esqueleto (torso, mangas, piernas).

Uso:  python tools/garments/generate.py   (requiere pillow y numpy)
"""

import json
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[1] / "seed" / "images"
S = 2400  # lienzo de trabajo (se reduce a la mitad para antialias)


def P(pts):
    return [(x * S, y * S) for x, y in pts]


def bezier(p0, p1, p2, n=16):
    return [
        ((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t**2 * p2[0],
         (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t**2 * p2[1])
        for t in (i / n for i in range(n + 1))
    ]


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def shade(rgb, f):
    return tuple(max(0, min(255, int(c * f))) for c in rgb)


class Garment:
    def __init__(self, color, anchors, back=False):
        self.base = hex_rgb(color)
        self.anchors = anchors
        self.back = back
        self.rig = None
        self.mask = Image.new("L", (S, S), 0)
        self.detail = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        self.md = ImageDraw.Draw(self.mask)
        self.dd = ImageDraw.Draw(self.detail)

    def shape(self, pts):
        self.md.polygon(P(pts), fill=255)

    def line(self, pts, f=0.72, w=6, alpha=255):
        self.dd.line(P(pts), fill=shade(self.base, f) + (alpha,), width=w, joint="curve")

    def stitch(self, pts, f=1.25, w=4, dash=18, color=None):
        pts = P(pts)
        c = (color or shade(self.base, f)) + (230,)
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            dist = math.hypot(x1 - x0, y1 - y0)
            steps = max(1, int(dist // dash))
            for i in range(0, steps, 2):
                a, b = i / steps, min(1, (i + 1) / steps)
                self.dd.line([(x0 + (x1 - x0) * a, y0 + (y1 - y0) * a),
                              (x0 + (x1 - x0) * b, y0 + (y1 - y0) * b)], fill=c, width=w)

    def poly(self, pts, f=0.85, alpha=255, outline=None):
        self.dd.polygon(P(pts), fill=shade(self.base, f) + (alpha,),
                        outline=None if outline is None else shade(self.base, outline) + (255,))

    def circle(self, x, y, r, rgb, alpha=255):
        x, y, r = x * S, y * S, r * S
        self.dd.ellipse([x - r, y - r, x + r, y + r], fill=rgb + (alpha,))

    def render(self, pattern=None, texture=0.0, name="x", box=None):
        mask = np.array(self.mask, dtype=np.float32) / 255
        ys, xs = np.nonzero(mask)
        x0, x1, y0, y1 = box or (xs.min(), xs.max(), ys.min(), ys.max())

        rgb = np.zeros((S, S, 3), np.float32) + np.array(self.base, np.float32)
        if pattern:
            rgb = pattern(rgb)
        # sombreado cilíndrico horizontal + luz desde arriba
        xx = np.linspace(-1, 1, S)[None, :]
        cx = ((x0 + x1) / 2) / S * 2 - 1
        half = (x1 - x0) / S
        horiz = 1 - 0.22 * np.clip(np.abs(xx - cx) / max(half, 1e-3), 0, 1) ** 2
        yy = np.linspace(0, 1, S)[:, None]
        vert = 1.06 - 0.12 * np.clip((yy - y0 / S) / max((y1 - y0) / S, 1e-3), 0, 1)
        light = horiz * vert
        if texture:
            rng = np.random.default_rng(len(name))
            noise = rng.normal(0, texture, (S // 4, S // 4)).astype(np.float32)
            noise = np.array(Image.fromarray(noise).resize((S, S), Image.BILINEAR))
            light = light * (1 + noise)
        rgb = np.clip(rgb * light[..., None], 0, 255)

        # borde interior oscuro para dar volumen
        edge = np.array(self.mask.filter(ImageFilter.GaussianBlur(14)), np.float32) / 255
        rim = np.clip((1 - edge) * 2.2, 0, 1) * mask
        rgb = rgb * (1 - 0.35 * rim[..., None])

        img = Image.fromarray(np.dstack([rgb, mask * 255]).astype(np.uint8), "RGBA")
        details = Image.new("RGBA", (S, S))
        details.paste(self.detail, (0, 0), self.mask)  # detalles solo dentro de la prenda
        img = Image.alpha_composite(img, details)
        img = img.crop((x0, y0, x1 + 1, y1 + 1))
        w, h = img.size
        img = img.resize((w // 2, h // 2), Image.LANCZOS)
        def norm(pt):
            return [round(float((pt[0] * S - x0) / w), 4), round(float((pt[1] * S - y0) / h), 4)]

        def norm_y(y):
            return round(float((y * S - y0) / h), 4)

        anchors = {k: norm(v) for k, v in self.anchors.items()}
        if self.rig:
            r = self.rig
            anchors["rig"] = {
                "type": r["type"],
                "top": norm_y(r["top"]),
                "bottom": norm_y(r["bottom"]),
                "region_bottom": norm_y(r.get("region_bottom", r["bottom"])),
                "anchor_l": norm(r["anchor_l"]),
                "anchor_r": norm(r["anchor_r"]),
                "edge_l": [norm(q) for q in r["edge_l"]],
                "edge_r": [norm(q) for q in r["edge_r"]],
                "limbs": [
                    {"side": l["side"], "kind": l["kind"],
                     "outer": [norm(q) for q in l["outer"]], "inner": [norm(q) for q in l["inner"]]}
                    for l in r.get("limbs", [])
                ],
            }
        return img, anchors, (x0, x1, y0, y1)


# ------------------------------------------------------------------ patrones
def stripes(color, period=0.035, width=0.012, vertical=False):
    c = np.array(hex_rgb(color), np.float32)

    def f(rgb):
        coord = np.arange(S) / S
        band = ((coord % period) < width).astype(np.float32)
        band = band[None, :, None] if vertical else band[:, None, None]
        return rgb * (1 - band) + c * band
    return f


def checks(color, period=0.06):
    c = np.array(hex_rgb(color), np.float32)

    def f(rgb):
        coord = (np.arange(S) / S % period) < period / 2
        a = coord[None, :].astype(np.float32)
        b = coord[:, None].astype(np.float32)
        m = (0.45 * a + 0.45 * b)[..., None]
        return rgb * (1 - m) + c * m
    return f


def dots(color, period=0.05, r=0.009):
    c = np.array(hex_rgb(color), np.float32)

    def f(rgb):
        yy, xx = np.mgrid[0:S, 0:S] / S
        off = (np.floor(yy / period) % 2) * period / 2
        dx = (xx + off) % period - period / 2
        dy = yy % period - period / 2
        m = (np.hypot(dx, dy) < r).astype(np.float32)[..., None]
        return rgb * (1 - m) + c * m
    return f


def florals(colors, n=160, seed=3):
    def f(rgb):
        img = Image.fromarray(rgb.astype(np.uint8))
        d = ImageDraw.Draw(img)
        rnd = random.Random(seed)
        for _ in range(n):
            x, y = rnd.random() * S, rnd.random() * S
            col = hex_rgb(rnd.choice(colors))
            r = S * 0.012
            for k in range(5):
                a = k * 2 * math.pi / 5
                px, py = x + math.cos(a) * r, y + math.sin(a) * r
                d.ellipse([px - r * 0.8, py - r * 0.8, px + r * 0.8, py + r * 0.8], fill=col)
            d.ellipse([x - r * 0.5, y - r * 0.5, x + r * 0.5, y + r * 0.5], fill=(250, 220, 90))
        return np.array(img, np.float32)
    return f


# ------------------------------------------------------------------- prendas
def mx(pts):
    """Refleja puntos respecto al eje vertical central (lado izquierdo → derecho)."""
    return [(1 - x, y) for x, y in pts]


def top_rig(kind, top, bottom, anchor, edge, arm_outer=None, arm_inner=None):
    rig = {"type": kind, "top": top, "bottom": bottom, "anchor_l": anchor, "anchor_r": mx([anchor])[0],
           "edge_l": edge, "edge_r": mx(edge), "limbs": []}
    if arm_outer:
        rig["limbs"] = [
            {"side": "l", "kind": "arm", "outer": arm_outer, "inner": arm_inner},
            {"side": "r", "kind": "arm", "outer": mx(arm_outer), "inner": mx(arm_inner)},
        ]
    return rig


def tee(color, pattern=None, pocket=False, back=False):
    g = Garment(color, {"l": (0.35, 0.125), "r": (0.65, 0.125)}, back)
    g.rig = top_rig("top", 0.10, 0.655, (0.35, 0.125), [(0.35, 0.125), (0.355, 0.285), (0.35, 0.655)],
                    [(0.35, 0.125), (0.19, 0.30)], [(0.355, 0.285), (0.275, 0.35)])
    neck = bezier((0.57, 0.10), (0.5, 0.13 if back else 0.19), (0.43, 0.10))
    hem = bezier((0.35, 0.64), (0.5, 0.655), (0.65, 0.64))
    g.shape([(0.43, 0.10), (0.35, 0.125), (0.19, 0.30), (0.275, 0.35), (0.355, 0.285)] + hem
            + [(0.645, 0.285), (0.725, 0.35), (0.81, 0.30), (0.65, 0.125), (0.57, 0.10)] + neck)
    g.line(neck, 0.8, 26)
    if not back:
        g.stitch(bezier((0.555, 0.117), (0.5, 0.19), (0.445, 0.117)), 1.2)
    g.line([(0.355, 0.285), (0.355, 0.30)], 0.7, 5)
    g.stitch([(0.205, 0.315), (0.285, 0.36)], 0.8)
    g.stitch([(0.795, 0.315), (0.715, 0.36)], 0.8)
    g.stitch(bezier((0.355, 0.62), (0.5, 0.635), (0.645, 0.62)), 0.8)
    g.line([(0.40, 0.35), (0.42, 0.50)], 0.9, 5, 120)
    g.line([(0.60, 0.38), (0.58, 0.52)], 0.9, 5, 120)
    if pocket and not back:
        g.poly([(0.54, 0.26), (0.61, 0.26), (0.61, 0.34), (0.575, 0.355), (0.54, 0.34)], 0.95, outline=0.75)
    return g


def long_sleeve_body(g, sh=0.12, hem_y=0.70, cuff=0.64, wide=0.0):
    hem = bezier((0.345 - wide, hem_y), (0.5, hem_y + 0.03), (0.655 + wide, hem_y))
    left = [(0.36, sh), (0.27 - wide, sh + 0.08), (0.215 - wide, cuff), (0.29 - wide / 2, cuff + 0.02), (0.335 - wide / 2, 0.33)]
    right = [(0.665 + wide / 2, 0.33), (0.71 + wide / 2, cuff + 0.02), (0.785 + wide, cuff), (0.73 + wide, sh + 0.08), (0.64, sh)]
    return left, hem, right


def shirt(color, pattern=None, back=False):
    g = Garment(color, {"l": (0.36, 0.12), "r": (0.64, 0.12)}, back)
    g.rig = top_rig("top", 0.095, 0.715, (0.36, 0.12), [(0.36, 0.12), (0.345, 0.33), (0.345, 0.715)],
                    [(0.36, 0.12), (0.27, 0.20), (0.215, 0.64)], [(0.345, 0.33), (0.29, 0.66)])
    left, hem, right = long_sleeve_body(g)
    g.shape([(0.44, 0.095)] + left + [(0.35, 0.33)] + hem + [(0.65, 0.33)] + right + [(0.56, 0.095), (0.5, 0.13)])
    if back:
        # cuello por detrás y canesú
        g.poly([(0.44, 0.095), (0.56, 0.095), (0.555, 0.125), (0.445, 0.125)], 1.08, outline=0.7)
        g.line([(0.37, 0.19), (0.63, 0.19)], 0.75, 5)
    else:
        g.poly([(0.44, 0.095), (0.5, 0.135), (0.47, 0.175), (0.425, 0.13)], 1.08, outline=0.7)
        g.poly([(0.56, 0.095), (0.5, 0.135), (0.53, 0.175), (0.575, 0.13)], 1.08, outline=0.7)
        g.line([(0.5, 0.135), (0.5, 0.72)], 0.7, 5)
        for y in np.linspace(0.19, 0.66, 6):
            g.circle(0.51, y, 0.0075, (240, 240, 235))
            g.circle(0.51, y, 0.0075 * 0.4, (190, 190, 185))
        g.poly([(0.39, 0.25), (0.46, 0.25), (0.46, 0.33), (0.425, 0.345), (0.39, 0.33)], 0.97, outline=0.72)
    g.line([(0.215, 0.62), (0.29, 0.64)], 0.7, 7)
    g.line([(0.785, 0.62), (0.71, 0.64)], 0.7, 7)
    g.line([(0.335, 0.33), (0.35, 0.33)], 0.7, 4)
    return g


def hoodie(color, pattern=None, back=False):
    g = Garment(color, {"l": (0.36, 0.13), "r": (0.64, 0.13)}, back)
    g.rig = top_rig("top", 0.02, 0.74, (0.36, 0.13), [(0.36, 0.13), (0.335, 0.33), (0.32, 0.74)],
                    [(0.36, 0.13), (0.25, 0.21), (0.195, 0.64)], [(0.335, 0.33), (0.28, 0.66)])
    left, hem, right = long_sleeve_body(g, sh=0.13, hem_y=0.70, cuff=0.64, wide=0.02)
    g.shape([(0.42, 0.10)] + left + [(0.345, 0.33)] + hem + [(0.655, 0.33)] + right + [(0.58, 0.10)]
            + bezier((0.58, 0.10), (0.5, 0.03), (0.42, 0.10)))
    if back:
        # capucha vista por detrás (cae sobre la espalda)
        g.poly(bezier((0.585, 0.105), (0.5, 0.02), (0.415, 0.105)) + bezier((0.42, 0.12), (0.5, 0.26), (0.58, 0.12)), 0.9)
        g.line(bezier((0.42, 0.12), (0.5, 0.26), (0.58, 0.12)), 0.7, 7)
        g.line([(0.5, 0.03), (0.5, 0.25)], 0.8, 5)
    else:
        # capucha y abertura
        g.poly(bezier((0.585, 0.105), (0.5, 0.02), (0.415, 0.105)) + bezier((0.43, 0.13), (0.5, 0.20), (0.57, 0.13)), 0.8)
        g.line(bezier((0.43, 0.13), (0.5, 0.20), (0.57, 0.13)), 0.65, 10)
        g.line([(0.475, 0.175), (0.47, 0.34)], 1.35, 7)
        g.line([(0.525, 0.175), (0.53, 0.34)], 1.35, 7)
        # bolsillo canguro
        g.poly([(0.40, 0.49), (0.60, 0.49), (0.64, 0.64), (0.36, 0.64)], 0.93)
        g.line([(0.40, 0.49), (0.36, 0.64)], 0.7, 6)
        g.line([(0.60, 0.49), (0.64, 0.64)], 0.7, 6)
        g.line([(0.40, 0.49), (0.60, 0.49)], 0.75, 5)
    # puños y pretina acanalados
    for x0, x1 in ((0.195, 0.27), (0.73, 0.805)):
        g.poly([(x0, 0.60), (x1, 0.615), (x1, 0.66), (x0, 0.645)], 0.85)
    g.poly(bezier((0.32, 0.665), (0.5, 0.69), (0.68, 0.665)) + [(0.68, 0.74), (0.32, 0.74)], 0.85)
    return g


def jacket(color, pattern=None, denim=False, texture=0.0, back=False):
    g = Garment(color, {"l": (0.36, 0.12), "r": (0.64, 0.12)}, back)
    g.rig = top_rig("top", 0.09, 0.70, (0.36, 0.12), [(0.36, 0.12), (0.3375, 0.33), (0.33, 0.70)],
                    [(0.36, 0.12), (0.255, 0.20), (0.20, 0.64)], [(0.3375, 0.33), (0.2825, 0.66)])
    left, hem, right = long_sleeve_body(g, hem_y=0.68, cuff=0.64, wide=0.015)
    g.shape([(0.43, 0.09)] + left + [(0.345, 0.33)] + hem + [(0.655, 0.33)] + right + [(0.57, 0.09), (0.5, 0.12)])
    sc = (214, 150, 60) if denim else None
    if back:
        g.poly([(0.43, 0.09), (0.57, 0.09), (0.565, 0.125), (0.435, 0.125)], 1.1, outline=0.65)
        g.line([(0.36, 0.22), (0.5, 0.26), (0.64, 0.22)], 0.7, 5)
        if denim:
            g.stitch([(0.36, 0.23), (0.5, 0.27), (0.64, 0.23)], color=sc)
            g.stitch([(0.345, 0.64), (0.655, 0.64)], color=sc)
        g.line([(0.21, 0.61), (0.29, 0.63)], 0.7, 7)
        g.line([(0.79, 0.61), (0.71, 0.63)], 0.7, 7)
        return g
    # interior visible (camiseta) y solapas
    g.dd.polygon(P([(0.46, 0.11), (0.54, 0.11), (0.52, 0.40), (0.48, 0.40)]), fill=(235, 232, 225, 255))
    g.poly([(0.43, 0.09), (0.47, 0.11), (0.49, 0.38), (0.40, 0.20)], 1.1, outline=0.65)
    g.poly([(0.57, 0.09), (0.53, 0.11), (0.51, 0.38), (0.60, 0.20)], 1.1, outline=0.65)
    g.line([(0.49, 0.38), (0.495, 0.70)], 0.6, 6)
    g.line([(0.51, 0.38), (0.505, 0.70)], 0.6, 6)
    if denim:
        for y in np.linspace(0.30, 0.62, 5):
            g.circle(0.47, y, 0.008, (180, 140, 70))
        for x0 in (0.38, 0.54):
            g.poly([(x0, 0.24), (x0 + 0.08, 0.24), (x0 + 0.08, 0.30), (x0 + 0.04, 0.315), (x0, 0.30)], 1.02, outline=0.7)
            g.stitch([(x0 + 0.005, 0.245), (x0 + 0.075, 0.245)], color=sc)
        g.stitch([(0.35, 0.36), (0.65, 0.36)], color=sc)
        g.stitch([(0.345, 0.64), (0.655, 0.64)], color=sc)
    else:
        g.line([(0.37, 0.52), (0.44, 0.50)], 0.6, 6)
        g.line([(0.63, 0.52), (0.56, 0.50)], 0.6, 6)
    g.line([(0.21, 0.61), (0.29, 0.63)], 0.7, 7)
    g.line([(0.79, 0.61), (0.71, 0.63)], 0.7, 7)
    return g


def dress(color, sleeves=True, neckline="v", back=False):
    g = Garment(color, {"l": (0.37, 0.10), "r": (0.63, 0.10)}, back)
    g.rig = top_rig("full", 0.095, 0.97, (0.37, 0.10),
                    [(0.37, 0.10), (0.375, 0.22), (0.385, 0.37), (0.36, 0.42), (0.21, 0.94)],
                    [(0.37, 0.10), (0.30, 0.17)] if sleeves else None, [(0.375, 0.22), (0.34, 0.215)] if sleeves else None)
    if back:
        neck = bezier((0.56, 0.095), (0.5, 0.125), (0.44, 0.095))
    elif neckline == "v":
        neck = [(0.56, 0.095), (0.5, 0.20), (0.44, 0.095)]
    else:
        neck = bezier((0.565, 0.095), (0.5, 0.17), (0.435, 0.095))
    hem = bezier((0.21, 0.94), (0.5, 0.97), (0.79, 0.94))
    body_l = [(0.44, 0.095), (0.37, 0.10)]
    if sleeves:
        body_l += [(0.30, 0.17), (0.34, 0.215)]
    body_l += [(0.375, 0.22), (0.385, 0.37), (0.36, 0.42)]
    body_r = [(0.64, 0.42), (0.615, 0.37), (0.625, 0.22)]
    if sleeves:
        body_r += [(0.66, 0.215), (0.70, 0.17)]
    body_r += [(0.63, 0.10), (0.56, 0.095)]
    g.shape(body_l + hem[::-1][::-1] + body_r + neck)
    g.line(neck, 0.75, 8)
    g.poly([(0.385, 0.365), (0.615, 0.365), (0.62, 0.40), (0.38, 0.40)], 0.8)
    for x in (0.30, 0.40, 0.5, 0.60, 0.70):
        g.line([(0.5 + (x - 0.5) * 0.35, 0.42), (x, 0.93)], 0.85, 6, 150)
    return g


def bottom_rig(top, bottom, crotch_y, edge_l, leg_outer=None, leg_inner=None):
    rig = {"type": "bottom", "top": top, "bottom": bottom, "region_bottom": crotch_y,
           "anchor_l": edge_l[0], "anchor_r": mx([edge_l[0]])[0], "edge_l": edge_l, "edge_r": mx(edge_l), "limbs": []}
    if leg_outer:
        rig["limbs"] = [
            {"side": "l", "kind": "leg", "outer": leg_outer, "inner": leg_inner},
            {"side": "r", "kind": "leg", "outer": mx(leg_outer), "inner": mx(leg_inner)},
        ]
    return rig


def pants(color, texture=0.0, jeans=False, wide=0.0, back=False):
    g = Garment(color, {"l": (0.33, 0.05), "r": (0.67, 0.05)}, back)
    g.rig = bottom_rig(0.045, 0.95, 0.30, [(0.33, 0.05), (0.31, 0.25), (0.31 - wide * 0.07, 0.30)],
                       [(0.31 - wide * 0.07, 0.30), (0.31 - wide, 0.95)], [(0.5, 0.30), (0.485 + wide * 0.2, 0.95)])
    g.shape([(0.33, 0.05), (0.67, 0.05), (0.69, 0.25), (0.69 + wide, 0.95), (0.515 - wide * 0.2, 0.95),
             (0.5, 0.30), (0.485 + wide * 0.2, 0.95), (0.31 - wide, 0.95), (0.31, 0.25)])
    g.poly([(0.33, 0.05), (0.67, 0.05), (0.672, 0.09), (0.328, 0.09)], 0.85)
    for x in (0.36, 0.44, 0.56, 0.64):
        g.poly([(x - 0.007, 0.045), (x + 0.007, 0.045), (x + 0.007, 0.10), (x - 0.007, 0.10)], 0.8)
    sc = (214, 150, 60) if jeans else None
    if back:
        # bolsillos traseros y costura central
        g.line([(0.5, 0.09), (0.5, 0.29)], 0.7, 5)
        for x0 in (0.36, 0.53):
            g.poly([(x0, 0.13), (x0 + 0.11, 0.13), (x0 + 0.105, 0.22), (x0 + 0.055, 0.24), (x0 + 0.005, 0.22)], 0.95, outline=0.7)
    else:
        g.line(bezier((0.5, 0.09), (0.505, 0.21), (0.47, 0.24)), 0.7, 5)
        g.line(bezier((0.345, 0.10), (0.38, 0.16), (0.42, 0.10)), 0.7, 5)
        g.line(bezier((0.655, 0.10), (0.62, 0.16), (0.58, 0.10)), 0.7, 5)
        g.circle(0.5, 0.07, 0.009, (190, 160, 90) if jeans else shade(g.base, 0.6))
    g.line([(0.40, 0.30), (0.40 - wide / 2, 0.94)], 0.88, 5, 140)
    g.line([(0.60, 0.30), (0.60 + wide / 2, 0.94)], 0.88, 5, 140)
    if jeans:
        g.stitch([(0.335, 0.095), (0.665, 0.095)], color=sc)
        g.stitch([(0.315, 0.93), (0.48, 0.93)], color=sc)
        g.stitch([(0.52, 0.93), (0.685, 0.93)], color=sc)
        if not back:
            g.stitch([(0.51, 0.10), (0.51, 0.22)], color=sc)
    return g


def shorts(color, jeans=False, back=False):
    g = Garment(color, {"l": (0.33, 0.05), "r": (0.67, 0.05)}, back)
    g.rig = bottom_rig(0.05, 0.43, 0.30, [(0.33, 0.05), (0.31, 0.25), (0.308, 0.30)],
                       [(0.308, 0.30), (0.29, 0.42)], [(0.5, 0.30), (0.48, 0.43)])
    g.shape([(0.33, 0.05), (0.67, 0.05), (0.69, 0.25), (0.71, 0.42), (0.52, 0.43), (0.5, 0.30),
             (0.48, 0.43), (0.29, 0.42), (0.31, 0.25)])
    g.poly([(0.33, 0.05), (0.67, 0.05), (0.672, 0.09), (0.328, 0.09)], 0.85)
    if back:
        g.line([(0.5, 0.09), (0.5, 0.28)], 0.7, 5)
        for x0 in (0.36, 0.53):
            g.poly([(x0, 0.13), (x0 + 0.11, 0.13), (x0 + 0.105, 0.22), (x0 + 0.055, 0.24), (x0 + 0.005, 0.22)], 0.95, outline=0.7)
    else:
        g.line(bezier((0.5, 0.09), (0.505, 0.22), (0.47, 0.25)), 0.7, 5)
        g.line(bezier((0.345, 0.10), (0.38, 0.16), (0.42, 0.10)), 0.7, 5)
        g.line(bezier((0.655, 0.10), (0.62, 0.16), (0.58, 0.10)), 0.7, 5)
    sc = (214, 150, 60) if jeans else None
    g.stitch([(0.295, 0.40), (0.48, 0.41)], color=sc)
    g.stitch([(0.52, 0.41), (0.705, 0.40)], color=sc)
    return g


def skirt(color, pleats=True, back=False):
    g = Garment(color, {"l": (0.36, 0.05), "r": (0.64, 0.05)}, back)
    g.rig = bottom_rig(0.05, 0.51, 0.51, [(0.36, 0.05), (0.25, 0.48)])
    hem = bezier((0.75, 0.48), (0.5, 0.51), (0.25, 0.48))
    g.shape([(0.36, 0.05), (0.64, 0.05)] + hem)
    g.poly([(0.36, 0.05), (0.64, 0.05), (0.645, 0.095), (0.355, 0.095)], 0.82)
    if pleats:
        for k in range(1, 10):
            t = k / 10
            g.line([(0.36 + 0.28 * t, 0.10), (0.26 + 0.48 * t, 0.49)], 0.78, 6, 200)
    return g


# ------------------------------------------------------------------ catálogo
CATALOG = [
    # (archivo, fábrica)
    ("polo-blanco", lambda back: (tee("#F2F0EB", back=back), {})),
    ("polo-negro", lambda back: (tee("#26272B", back=back), {})),
    ("polo-mostaza", lambda back: (tee("#D9A441", pocket=True, back=back), {})),
    ("polo-rayas", lambda back: (tee("#F4F1EA", back=back), {"pattern": stripes("#1F3B66")})),
    ("polo-verde", lambda back: (tee("#6B7A4B", back=back), {})),
    ("camisa-celeste", lambda back: (shirt("#A9C7E6", back=back), {})),
    ("camisa-blanca", lambda back: (shirt("#F5F5F2", back=back), {})),
    ("camisa-cuadros", lambda back: (shirt("#B8342F", back=back), {"pattern": checks("#2A2A3A")})),
    ("polera-gris", lambda back: (hoodie("#9A9EA6", back=back), {"texture": 0.02})),
    ("polera-lila", lambda back: (hoodie("#B7A3D6", back=back), {})),
    ("polera-negra", lambda back: (hoodie("#2B2C30", back=back), {})),
    ("casaca-denim", lambda back: (jacket("#4F6E9C", denim=True, back=back), {"texture": 0.06})),
    ("casaca-cuero", lambda back: (jacket("#1E1C1B", back=back), {"texture": 0.03})),
    ("casaca-beige", lambda back: (jacket("#C8B08A", back=back), {})),
    ("vestido-rojo", lambda back: (dress("#B3262E", back=back), {})),
    ("vestido-negro", lambda back: (dress("#1F1F24", sleeves=False, neckline="round", back=back), {})),
    ("vestido-lunares", lambda back: (dress("#1E3A5F", neckline="round", back=back), {"pattern": dots("#F4F1EA")})),
    ("vestido-floral", lambda back: (dress("#F3E4D0", back=back), {"pattern": florals(["#D9657A", "#7A9E7E", "#E7A04B"])})),
    ("pantalon-jean", lambda back: (pants("#3F5E8C", jeans=True, back=back), {"texture": 0.07})),
    ("pantalon-negro", lambda back: (pants("#232428", back=back), {})),
    ("pantalon-chino", lambda back: (pants("#C9B28C", back=back), {})),
    ("pantalon-palazzo", lambda back: (pants("#7A4E3A", wide=0.05, back=back), {})),
    ("falda-plisada", lambda back: (skirt("#E7A9B8", back=back), {})),
    ("falda-negra", lambda back: (skirt("#232326", pleats=False, back=back), {})),
    ("short-denim", lambda back: (shorts("#6D8DB8", jeans=True, back=back), {"texture": 0.07})),
    ("short-caqui", lambda back: (shorts("#B9A57A", back=back), {})),
]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    anchors = {}
    for name, factory in CATALOG:
        garment, opts = factory(False)
        img, anc, box = garment.render(name=name, **opts)
        img.save(OUT / f"{name}.png", optimize=True)
        # la espalda usa el mismo recorte para compartir el rig
        back, opts_b = factory(True)
        back_img, _, _ = back.render(name=name, box=box, **opts_b)
        back_img.save(OUT / f"{name}-back.png", optimize=True)
        anchors[name] = anc
        print(f"{name:20s} {img.size}  limbs={len(anc.get('rig', {}).get('limbs', []))}")
    (OUT / "anchors.json").write_text(json.dumps(anchors, indent=1))


if __name__ == "__main__":
    main()
