"""Synthetic captures for the README screenshots and demo (conventions/readme-guide.md §4).

    python3 tool/readme/demo_assets.py <store dir> <samples dir> [--count N]

Writes N sample captures into a throwaway Snapdock store (index.json + files) and three
PNGs the demo runner adds live. Everything is drawn here, so no real screen content or
personal data ends up in the README. Needs Pillow.
"""
import json, math, shutil, sys, time
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

store = Path(sys.argv[1])
samples = Path(sys.argv[2])
shutil.rmtree(store, ignore_errors=True)
shutil.rmtree(samples, ignore_errors=True)
store.mkdir(parents=True)
samples.mkdir(parents=True)

def font(size, bold=False):
    for p in ('/System/Library/Fonts/Helvetica.ttc', '/System/Library/Fonts/SFNS.ttf'):
        try: return ImageFont.truetype(p, size, index=1 if bold else 0)
        except Exception: pass
    return ImageFont.load_default()

W, H = 1280, 800

def gradient(c1, c2, size=(W, H)):
    img = Image.new('RGB', size)
    px = img.load()
    for y in range(size[1]):
        t = y / (size[1] - 1)
        for x in range(size[0]):
            s = (t + x / (size[0] - 1)) / 2
            px[x, y] = tuple(round(c1[i] + (c2[i] - c1[i]) * s) for i in range(3))
    return img

def card(img, box, fill=(255, 255, 255), r=18):
    ImageDraw.Draw(img).rounded_rectangle(box, r, fill=fill)

def chart():
    img = gradient((236, 241, 250), (214, 224, 244))
    d = ImageDraw.Draw(img)
    card(img, (90, 80, W - 90, H - 80))
    d.text((140, 120), 'Weekly active users', font=font(40, True), fill=(30, 41, 59))
    d.text((140, 176), 'Last 7 days', font=font(26), fill=(100, 116, 139))
    vals = [38, 52, 47, 66, 74, 69, 88]
    for i, v in enumerate(vals):
        x = 180 + i * 140
        top = H - 170 - v * 4.4
        d.rounded_rectangle((x, top, x + 84, H - 170), 10, fill=(76, 157, 255) if i < 6 else (124, 92, 255))
        d.text((x + 8, H - 150), 'MTWTFSS'[i] + str(i + 1), font=font(24), fill=(100, 116, 139))
    return img

def document():
    img = Image.new('RGB', (W, H), (245, 246, 248))
    card(img, (150, 60, W - 150, H - 40), r=10)
    d = ImageDraw.Draw(img)
    d.text((210, 110), 'Release notes', font=font(54, True), fill=(16, 24, 40))
    y = 200
    for i, wd in enumerate([760, 700, 790, 520, 0, 740, 690, 610, 0, 780, 560]):
        if wd:
            d.rounded_rectangle((210, y, 210 + wd, y + 16), 8, fill=(203, 213, 225))
        y += 40
    d.rounded_rectangle((210, 640, 470, 700), 14, fill=(76, 157, 255))
    d.text((250, 653), 'Download', font=font(30, True), fill=(255, 255, 255))
    return img

def code():
    img = Image.new('RGB', (W, H), (21, 29, 39))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, W, 54), fill=(29, 39, 51))
    for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        d.ellipse((24 + i * 34, 18, 42 + i * 34, 36), fill=c)
    mono = font(30)
    colors = [(124, 92, 255), (76, 157, 255), (52, 211, 153), (169, 180, 196), (255, 176, 32)]
    lines = [[(0, 'final'), (1, ' capture '), (3, '= await '), (1, 'service.captureRegion')],
             [(3, '  shape: '), (2, 'CaptureShape.circle'), (3, ',')],
             [(3, ');')], [], [(0, 'if '), (3, '(result == '), (4, 'null'), (3, ') return;')],
             [(1, 'items'), (3, '.insert('), (4, '0'), (3, ', item);')], [(2, '// lands in the dock')],
             [(0, 'await '), (1, 'controller.copy'), (3, '(item);')]]
    y = 110
    for ln in lines:
        x = 70
        for ci, txt in ln:
            d.text((x, y), txt, font=mono, fill=colors[ci])
            x += d.textlength(txt, font=mono)
        y += 56
    return img

def circle():
    base = gradient((255, 176, 32), (232, 70, 120), (720, 720))
    d = ImageDraw.Draw(base)
    d.ellipse((190, 150, 330, 290), fill=(255, 255, 255))
    d.rounded_rectangle((110, 330, 610, 700), 160, fill=(255, 255, 255))
    out = Image.new('RGBA', (720, 720), (0, 0, 0, 0))
    mask = Image.new('L', (720, 720), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, 719, 719), fill=255)
    out.paste(base, (0, 0), mask)
    return out

def dashboard():
    img = gradient((18, 24, 38), (32, 44, 70))
    d = ImageDraw.Draw(img)
    for i in range(3):
        x = 80 + i * 380
        card(img, (x, 100, x + 340, 300), fill=(37, 48, 72))
        d.text((x + 30, 130), ['Requests', 'Latency', 'Errors'][i], font=font(26), fill=(148, 163, 184))
        d.text((x + 30, 190), ['12.4k', '84 ms', '0.2 %'][i], font=font(64, True), fill=(241, 245, 249))
    card(img, (80, 340, W - 80, H - 90), fill=(37, 48, 72))
    pts = [(140 + i * 100, 640 - 120 * (math.sin(i / 1.6) + 1) - i * 6) for i in range(12)]
    d.line(pts, fill=(76, 157, 255), width=8, joint='curve')
    return img

def gif_frames():
    frames = []
    for i in range(14):
        im = gradient((124, 92, 255), (76, 157, 255), (480, 300))
        d = ImageDraw.Draw(im)
        d.rounded_rectangle((60, 120, 420, 160), 20, fill=(255, 255, 255, 80))
        d.rounded_rectangle((60, 120, 60 + 360 * (i + 1) / 14, 160), 20, fill=(255, 255, 255))
        frames.append(im)
    return frames

items = []
now = int(time.time() * 1000) - 3600_000


def swap(img):
    if img.mode == 'RGBA':
        r, g, b, a = img.split()
        return Image.merge('RGBA', (b, r, g, a))
    r, g, b = img.convert('RGB').split()
    return Image.merge('RGB', (g, b, r))


def add(i, kind, shape, preview, w, h, **extra):
    thumb = store / (f'{i}.png' if kind == 'image' else f'{i}.thumb.png')
    pv = preview.copy()
    pv.thumbnail((640, 640))
    pv.save(thumb)
    path = thumb
    if kind == 'image':
        preview.save(store / f'{i}.png')
    elif kind == 'gif':
        fr = gif_frames()
        path = store / f'{i}.gif'
        fr[0].save(path, save_all=True, append_images=fr[1:], duration=100, loop=0)
    else:
        path = store / f'{i}.mp4'
        path.write_bytes(bytes(32))
    items.append({'id': i, 'kind': kind, 'path': str(path), 'preview': str(thumb), 'width': w, 'height': h,
                  'shape': shape, 'createdAt': now + i * 60_000, 'durationMs': extra.get('d'), 'savedPath': None})


add(1, 'image', 'window', document(), W, H)
add(2, 'gif', 'rect', gif_frames()[9], 480, 300, d=1400)
add(3, 'video', 'rect', dashboard(), W, H, d=8000)
add(4, 'image', 'rect', code(), W, H)
add(5, 'image', 'rect', chart(), W, H)
add(6, 'image', 'circle', circle(), 720, 720)
add(7, 'video', 'rect', swap(dashboard()), W, H, d=5000)
add(8, 'image', 'circle', swap(circle()), 720, 720)
add(9, 'image', 'rect', swap(chart()), W, H)
count = int(sys.argv[sys.argv.index('--count') + 1]) if '--count' in sys.argv else len(items)
items.sort(key=lambda x: -x['id'])
# Keep the lowest ids (oldest first): the demo adds newer ones on top.
items = [i for i in items if i['id'] <= count]
(store / 'index.json').write_text(json.dumps({'version': 1, 'nextId': 100, 'items': items}))

# Live arrivals for the demo: file names sort in the order they appear.
chart().save(samples / '1-chart.png')
circle().save(samples / '2-circle.png')
swap(dashboard()).save(samples / '3-dashboard.png')
print(f'seeded {len(items)} items in {store}; samples in {samples}')
