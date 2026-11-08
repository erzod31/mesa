"""Export original Mesa vector geometry to SVG, Android resources and Windows icons."""
import json
import re
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / 'branding'
SPEC = json.loads((BRAND / 'mesa-mark.json').read_text(encoding='utf-8'))
COLORS = {k: SPEC[k] for k in ['background', 'foreground', 'accent']}


def parse(data):
    tokens = re.findall(r'[MLCZ]|-?\d+(?:\.\d+)?', data)
    i = 0
    while i < len(tokens):
        command = tokens[i]
        i += 1
        count = {'M': 2, 'L': 2, 'C': 6, 'Z': 0}[command]
        yield command, [float(x) for x in tokens[i:i+count]]
        i += count


def contours(data):
    current = []
    point = (0, 0)
    for command, v in parse(data):
        if command == 'M':
            if current:
                yield current
            current = [(v[0], v[1])]
            point = current[-1]
        elif command == 'L':
            point = (v[0], v[1])
            current.append(point)
        elif command == 'C':
            x0, y0 = point
            x1, y1, x2, y2, x3, y3 = v
            for n in range(1, 41):
                t = n/40
                u = 1-t
                current.append((u**3*x0 + 3*u*u*t*x1 + 3*u*t*t*x2 + t**3*x3,
                                u**3*y0 + 3*u*u*t*y1 + 3*u*t*t*y2 + t**3*y3))
            point = (x3, y3)
        elif command == 'Z':
            current.append(current[0])
    if current:
        yield current


def raster(size=512, background=True, rounded=True, mono=False):
    scale = 12
    image = Image.new('RGBA', (96*scale, 96*scale))
    draw = ImageDraw.Draw(image)
    if background:
        if rounded:
            draw.rounded_rectangle((0, 0, 96*scale-1, 96*scale-1), radius=26*scale, fill=COLORS['background'])
        else:
            draw.rectangle((0, 0, 96*scale-1, 96*scale-1), fill=COLORS['background'])
    for item in SPEC['paths']:
        color = '#FFFFFF' if mono else COLORS[item.get('fill') or item['stroke']]
        for contour in contours(item['d']):
            points = [(x*scale, y*scale) for x, y in contour]
            if 'fill' in item:
                draw.polygon(points, fill=color)
            else:
                width = item['width']*scale
                draw.line(points, fill=color, width=width, joint='curve')
                # Union of round stroke samples avoids raster seams at joins.
                for x, y in points:
                    draw.ellipse((x-width/2, y-width/2, x+width/2, y+width/2), fill=color)
    return image.resize((size, size), Image.Resampling.LANCZOS)


def svg(background=True, mono=False):
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96" role="img" aria-label="Mesa"><title>Mesa · recetas para compartir</title>']
    if background:
        parts.append(f'<rect width="96" height="96" rx="26" fill="{COLORS["background"]}"/>')
    for item in SPEC['paths']:
        fill = ('#25634B' if mono else COLORS[item['fill']]) if 'fill' in item else 'none'
        extra = ''
        if 'stroke' in item:
            stroke = '#25634B' if mono else COLORS[item['stroke']]
            extra = f' stroke="{stroke}" stroke-width="{item["width"]}" stroke-linecap="round" stroke-linejoin="round"'
        parts.append(f'<path d="{item["d"]}" fill="{fill}"{extra}/>')
    return ''.join(parts) + '</svg>'


def android_vector(mono=False):
    parts = ['<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108"><group android:translateX="6" android:translateY="6">']
    for item in SPEC['paths']:
        fill = ('#FFFFFFFF' if mono else COLORS[item['fill']]) if 'fill' in item else '#00000000'
        extra = ''
        if 'stroke' in item:
            stroke = '#FFFFFFFF' if mono else COLORS[item['stroke']]
            extra = f' android:strokeColor="{stroke}" android:strokeWidth="{item["width"]}" android:strokeLineCap="round" android:strokeLineJoin="round"'
        parts.append(f'<path android:pathData="{item["d"]}" android:fillColor="{fill}"{extra}/>')
    return ''.join(parts) + '</group></vector>'


def main():
    for name, args in [('mesa-icon.svg', {}), ('mesa-symbol.svg', {'background': False}),
                       ('mesa-monochrome.svg', {'background': False, 'mono': True})]:
        (BRAND / name).write_text(svg(**args), encoding='utf-8')
    wordmark = svg().replace('viewBox="0 0 96 96"', 'viewBox="0 0 360 96"').replace(
        '</svg>', '<text x="116" y="69" fill="#25634B" font-family="Segoe UI,Arial,sans-serif" font-size="72" font-weight="700" letter-spacing="-2">mesa</text></svg>')
    (BRAND / 'mesa-logo.svg').write_text(wordmark, encoding='utf-8')
    image = raster()
    image.save(BRAND / 'mesa-icon-512.png')
    raster(512, rounded=False).save(BRAND / 'mesa-store-icon-512.png')
    raster(512, background=False).save(BRAND / 'mesa-symbol-512.png')
    image.save(ROOT / 'client/windows/runner/resources/app_icon.ico',
               sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    resources = ROOT / 'client/android/app/src/main/res'
    for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        image.resize((size, size), Image.Resampling.LANCZOS).save(resources / f'mipmap-{density}/ic_launcher.png')
    (resources / 'drawable/mesa_icon_foreground.xml').write_text(android_vector(), encoding='utf-8')
    (resources / 'drawable/mesa_icon_monochrome.xml').write_text(android_vector(mono=True), encoding='utf-8')
    for folder, content in [
        ('mipmap-anydpi-v26', '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/mesa_brand_green"/><foreground android:drawable="@drawable/mesa_icon_foreground"/></adaptive-icon>'),
        ('mipmap-anydpi-v33', '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/mesa_brand_green"/><foreground android:drawable="@drawable/mesa_icon_foreground"/><monochrome android:drawable="@drawable/mesa_icon_monochrome"/></adaptive-icon>')]:
        (resources / folder).mkdir(parents=True, exist_ok=True)
        (resources / folder / 'ic_launcher.xml').write_text(content, encoding='utf-8')
    # Use the same mark for a legible monochrome notification resource.
    notification = android_vector(mono=True).replace('108dp', '24dp')
    (resources / 'drawable/ic_notification.xml').write_text(notification, encoding='utf-8')
    (resources / 'values/mesa_brand.xml').write_text(
        '<resources><color name="mesa_brand_green">#25634B</color><color name="mesa_launch_background">#F6F7F2</color></resources>', encoding='utf-8')
    (resources / 'values-night/mesa_brand.xml').write_text(
        '<resources><color name="mesa_launch_background">#171D19</color></resources>', encoding='utf-8')
    paths = []
    for item in SPEC['paths']:
        commands = []
        for command, values in parse(item['d']):
            method = {'M': 'moveTo', 'L': 'lineTo', 'C': 'cubicTo', 'Z': 'close'}[command]
            commands.append(f'..{method}({", ".join(str(v) for v in values)})')
        key = item.get('fill') or item['stroke']
        paint = f'Paint()..color = {key}'
        if 'stroke' in item:
            paint += f'..style = PaintingStyle.stroke..strokeWidth = {item["width"]}..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round'
        paths.append(f'  canvas.drawPath(Path(){"".join(commands)}, {paint});')
    source = "// Generated by scripts/make_brand_assets.py from branding/mesa-mark.json.\nimport 'package:flutter/material.dart';\n\nvoid paintMesaSymbol(Canvas canvas, Color foreground, Color accent) {\n" + '\n'.join(paths) + '\n}\n'
    (ROOT / 'client/lib/brand_paths.dart').write_text(source, encoding='utf-8')
    board = Image.new('RGB', (1400, 720), '#F6F7F2')
    draw = ImageDraw.Draw(board)
    font = ImageFont.truetype('C:/Windows/Fonts/segoeuib.ttf', 84)
    label = ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf', 25)
    board.paste(image.resize((300, 300), Image.Resampling.LANCZOS), (70, 70), image.resize((300, 300), Image.Resampling.LANCZOS))
    draw.text((410, 135), 'mesa', font=font, fill='#25634B')
    draw.text((414, 245), 'La cocina que compartes', font=label, fill='#515C53')
    draw.text((70, 450), 'Un cuenco. Una m. Un lugar para tus recetas.', font=label, fill='#242B26')
    x = 70
    for size in [16, 24, 32, 48, 64, 96]:
        icon = image.resize((size, size), Image.Resampling.LANCZOS)
        board.paste(icon, (x, 530), icon)
        draw.text((x, 640), str(size) + ' px', font=label, fill='#515C53')
        x += 140
    board.save(BRAND / 'mesa-identidad.png')
    print(json.dumps(dict(source='branding/mesa-mark.json', svg=3, legacy_densities=5,
                          adaptive=True, monochrome=True, windows_ico=True,
                          framework_dependencies_added=0), ensure_ascii=False))


if __name__ == '__main__':
    main()

