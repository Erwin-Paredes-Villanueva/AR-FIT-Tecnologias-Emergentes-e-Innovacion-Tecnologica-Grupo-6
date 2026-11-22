"""Genera etiquetas imprimibles (PNG) a partir de tools/labels/out/labels.json.

Además de las etiquetas reales crea dos de DEMOSTRACIÓN para la exposición:
  * "firma falsa": un QR con el mismo formato pero firmado por otra clave
    (simula una etiqueta fabricada por un falsificador)  → la app la marca en rojo
  * "código cambiado": el QR real con el código de barras de otra talla
    (simula una etiqueta de otra prenda cosida encima)   → rojo en el paso 2

Uso:  python3 tools/labels/render.py      (requiere: pip install qrcode pillow eth-account)
Salida: tools/labels/out/etiquetas.png y una imagen por etiqueta.
"""
import json
import os
import sys

import qrcode
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out')

# ---------------------------------------------------------------- EAN-13
L = ['0001101', '0011001', '0010011', '0111101', '0100011', '0110001', '0101111', '0111011', '0110111', '0001011']
G = ['0100111', '0110011', '0011011', '0100001', '0011101', '0111001', '0000101', '0010001', '0001001', '0010111']
R = ['1110010', '1100110', '1101100', '1000010', '1011100', '1001110', '1010000', '1000100', '1001000', '1110100']
PARITY = ['LLLLLL', 'LLGLGG', 'LLGGLG', 'LLGGGL', 'LGLLGG', 'LGGLLG', 'LGGGLL', 'LGLGLG', 'LGLGGL', 'LGGLGL']


def check_digit(first12: str) -> int:
    return (10 - sum(int(d) * (3 if i % 2 else 1) for i, d in enumerate(first12)) % 10) % 10


def ean13_modules(code: str) -> str:
    assert len(code) == 13 and check_digit(code[:12]) == int(code[12]), f'EAN-13 inválido: {code}'
    first = int(code[0])
    s = '101'
    for i in range(1, 7):
        s += (L if PARITY[first][i - 1] == 'L' else G)[int(code[i])]
    s += '01010'
    for i in range(7, 13):
        s += R[int(code[i])]
    return s + '101'


def font(size, bold=False):
    for name in (['Arial Bold.ttf', 'Helvetica-Bold.ttf'] if bold else ['Arial.ttf', 'Helvetica.ttf']) + ['DejaVuSans.ttf']:
        for d in ('/System/Library/Fonts/Supplemental', '/System/Library/Fonts', '/Library/Fonts', '/usr/share/fonts/truetype/dejavu'):
            p = os.path.join(d, name)
            if os.path.exists(p):
                return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def mono(size):
    for p in ('/System/Library/Fonts/Menlo.ttc', '/System/Library/Fonts/Courier.ttc', '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return font(size)


def draw_barcode(d: ImageDraw.ImageDraw, x0: int, y0: int, code: str, mw: int = 6, h: int = 150):
    mods = ean13_modules(code)
    left = x0 + mw * 11
    for i, m in enumerate(mods):
        if m == '1':
            guard = i < 3 or 45 <= i < 50 or i >= 92
            d.rectangle([left + i * mw, y0, left + (i + 1) * mw - 1, y0 + h + (22 if guard else 0)], fill='black')
    f = mono(int(mw * 6.5))
    d.text((x0, y0 + h + 4), code[0], font=f, fill='black')
    d.text((left + 6 * mw, y0 + h + 4), ' '.join(code[1:7]).replace(' ', ''), font=f, fill='black')
    d.text((left + 53 * mw, y0 + h + 4), code[7:], font=f, fill='black')
    return (95 + 22) * mw


def label_image(u: dict, banner: str | None = None) -> Image.Image:
    W, H = 900, 1260
    img = Image.new('RGB', (W, H), 'white')
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([6, 6, W - 7, H - 7], radius=28, outline=(180, 180, 180), width=4)
    d.text((48, 40), 'AR-FIT', font=font(64, True), fill='black')
    t = f"TALLA {u['size']}"
    d.text((W - 48 - d.textlength(t, font=font(46, True)), 52), t, font=font(46, True), fill='black')
    d.text((48, 122), f"{u['product_name']} · {u['brand']}", font=font(34), fill='black')

    qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=10, border=2)
    qr.add_data(u['qr_payload'])
    qr.make(fit=True)
    q = qr.make_image(fill_color='black', back_color='white').convert('RGB').resize((600, 600), Image.NEAREST)
    img.paste(q, ((W - 600) // 2, 185))

    s = u['serial']
    d.text(((W - d.textlength(s, font=mono(52))) / 2, 795), s, font=mono(52), fill='black')
    t = 'Escanea con la app AR-FIT para verificar'
    d.text(((W - d.textlength(t, font=font(28))) / 2, 865), t, font=font(28), fill=(60, 60, 60))
    bw = (95 + 22) * 6
    draw_barcode(d, (W - bw) // 2, 935, u['gtin'])
    if banner:
        d.rectangle([0, H - 110, W, H], fill=(200, 30, 30))
        d.text(((W - d.textlength(banner, font=font(40, True))) / 2, H - 85), banner, font=font(40, True), fill='white')
    return img


def forged(u: dict) -> dict:
    """Misma prenda y formato, pero firmada por una clave que no es la de AR-FIT."""
    try:
        from eth_account import Account
        from eth_account.messages import encode_defunct
    except ImportError:
        sys.exit('Para la etiqueta falsa instala eth-account:  pip install eth-account')
    import secrets
    alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'
    raw = ''.join(alphabet[b % 32] for b in secrets.token_bytes(12))
    serial = f'{raw[:4]}-{raw[4:8]}-{raw[8:]}'
    msg = f"ARFIT|{serial}|{u['product_id']}|{u['size']}|{u['gtin']}"
    sig = Account.sign_message(encode_defunct(text=msg), Account.create().key).signature.hex()
    sig = sig if sig.startswith('0x') else '0x' + sig
    payload = f"arfit://u/{serial}?p={u['product_id']}&t={u['size']}&g={u['gtin']}&s={sig}"
    return {**u, 'serial': serial, 'qr_payload': payload}


def other_size_gtin(u: dict) -> str:
    first12 = u['gtin'][:11] + str((int(u['gtin'][11]) + 1) % 10)
    return first12 + str(check_digit(first12))


def main():
    labels = json.load(open(os.path.join(OUT, 'labels.json')))
    if not labels:
        sys.exit('No hay etiquetas emitidas (ejecuta tools/seed/labels.mjs)')
    cards = [(u, None) for u in labels]
    base = labels[0]
    cards.append((forged(base), 'DEMO: FIRMA FALSA'))
    cards.append(({**base, 'gtin': other_size_gtin(base)}, 'DEMO: CÓDIGO CAMBIADO'))

    for u, banner in cards:
        name = u['serial'] + ('-' + banner.split(': ')[1].lower().replace(' ', '-').replace('ó', 'o') if banner else '')
        label_image(u, banner).save(os.path.join(OUT, f'{name}.png'))

    # hoja A4 a 150 ppp: 3 columnas de etiquetas de ~6 cm
    cols, cw, ch, pad = 3, 400, 560, 30
    rows = (len(cards) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * cw + (cols + 1) * pad, rows * ch + (rows + 1) * pad + 80), 'white')
    ImageDraw.Draw(sheet).text((pad, 25), 'AR-FIT · Etiquetas anti-fraude (recorta por el borde gris)', font=font(30, True), fill='black')
    for i, (u, banner) in enumerate(cards):
        im = label_image(u, banner).resize((cw, ch), Image.LANCZOS)
        r, c = divmod(i, cols)
        sheet.paste(im, (pad + c * (cw + pad), 80 + pad + r * (ch + pad)))
    sheet.save(os.path.join(OUT, 'etiquetas.png'))
    print(f'{len(cards)} etiquetas → {os.path.join(OUT, "etiquetas.png")}')


if __name__ == '__main__':
    main()
