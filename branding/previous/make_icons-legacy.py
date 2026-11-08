from pathlib import Path
from PIL import Image, ImageDraw
root = Path(__file__).resolve().parents[1] / 'client'
image = Image.new('RGBA', (512,512), '#285b44')
draw = ImageDraw.Draw(image)
draw.ellipse((135,140,397,402), outline='#f7f5ef', width=25)
draw.ellipse((176,181,356,361), outline='#a9dfb8', width=7)
draw.rounded_rectangle((93,100,113,403), radius=10, fill='#f7f5ef')
for x in (72,94,116):
    draw.rounded_rectangle((x,91,x+14,182), radius=7, fill='#f7f5ef')
for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
    image.resize((size,size),Image.Resampling.LANCZOS).save(root / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png')
image.save(root / 'windows/runner/resources/app_icon.ico',sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])
