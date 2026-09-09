import zipfile, pathlib
from PIL import Image, ImageDraw
out = pathlib.Path('assets/new')
out.mkdir(parents=True, exist_ok=True)
thumbs = []
for z in pathlib.Path('Corel').glob('*.zip'):
    print(z.name)
    with zipfile.ZipFile(z) as f:
        for n in f.namelist():
            if not n.lower().endswith('.png'): continue
            p = out / pathlib.Path(n).name
            p.write_bytes(f.read(n))
            im = Image.open(p).convert('RGBA')
            print(p.name, im.size)
            im.thumbnail((140, 190))
            tile = Image.new('RGB', (240, 230), '#cccccc')
            tile.paste(im, ((240-im.width)//2, 0), im)
            ImageDraw.Draw(tile).text((3,195), p.stem, fill='black')
            thumbs.append(tile)
sheet = Image.new('RGB', (240*6,230*((len(thumbs)+5)//6)), 'white')
for i, im in enumerate(thumbs): sheet.paste(im, ((i%6)*240,(i//6)*230))
sheet.save('asset_catalog.jpg')
