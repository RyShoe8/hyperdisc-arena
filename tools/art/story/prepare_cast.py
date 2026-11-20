"""Lossless cutouts from the approved gameplay atlases for editable Rigby projects."""
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'build' / 'story-cast'
IDS = ['mick', 'pete', 'tiffany', 'tango', 'alex', 'jimmy', 'jason', 'steve', 'vanessa', 'keno']
def make_grid(full, size):
    bounds = full.getchannel('A').getbbox()
    # Only retain six-pixel mesh cells touching the approved silhouette.
    alpha = full.getchannel('A')
    points, triangles, lookup = [], [], {}
    def vertex(x, y):
        pair = (x, y)
        if pair not in lookup:
            lookup[pair] = len(points)
            points.append([x, y])
        return lookup[pair]
    for y in range(bounds[1], bounds[3], 6):
        for x in range(bounds[0], bounds[2], 6):
            right, bottom = min(x + 6, bounds[2]), min(y + 6, bounds[3])
            if not alpha.crop((x, y, right, bottom)).getbbox():
                continue
            a, b, c, d = vertex(x, y), vertex(right, y), vertex(right, bottom), vertex(x, bottom)
            triangles.extend([a, b, c, a, c, d])
    bind_points = []
    for x, y in points:
        # Transparent boundary vertices inherit their nearest painted pixel's
        # anatomical region, preventing long edge triangles at moving fingers.
        options = [(dx * dx + dy * dy, x + dx, y + dy)
                   for dy in range(-7, 8) for dx in range(-7, 8)
                   if 0 <= x + dx < size and 0 <= y + dy < size
                   and alpha.getpixel((x + dx, y + dy)) > 96]
        _, bx, by = min(options) if options else (0, x, y)
        bind_points.append([bx, by])
    return {'points': points, 'bind_points': bind_points, 'triangles': triangles}

for name in IDS:
    folder = OUT / name
    folder.mkdir(parents=True, exist_ok=True)
    base = ROOT / 'assets/art/characters' / name
    metadata = json.loads(base.with_suffix('.json').read_text())
    sheet = Image.open(base.with_suffix('.webp')).convert('RGBA')
    size, columns = int(metadata['frame_size']), int(metadata['columns'])
    images = {}
    for n in range(len(metadata['frames'])):
        x, y = n % columns * size, n // columns * size
        frame = sheet.crop((x, y, x + size, y + size))
        box = frame.getchannel('A').getbbox()
        if box is None:
            continue
        frame.crop(box).save(folder / f'frame-{n}.png')
        images[f'frame-{n}'] = {'crop': list(box), 'frame': n}
    # The resting head and body are separate bones. The 8-pixel neck overlap
    # keeps the source painting continuous during small acting gestures.
    n = int(metadata['animations']['idle']['start'])
    full = sheet.crop((n % columns * size, n // columns * size, n % columns * size + size, n // columns * size + size))
    bounds = full.getchannel('A').getbbox()
    cut = int(bounds[1] + (bounds[3] - bounds[1]) * (0.30 if name == 'tango' else 0.24))
    for part, box in [('head', (bounds[0], bounds[1], bounds[2], cut + 8)), ('body', (bounds[0], cut, bounds[2], bounds[3]))]:
        full.crop(box).save(folder / f'{part}.png')
        images[part] = {'crop': list(box), 'frame': n}
    metadata['story_images'] = images
    metadata['neck'] = [(bounds[0] + bounds[2]) / 2, cut + 5]
    metadata['acting_grid'] = make_grid(full, size)
    if name == 'mick':
        metadata['kneel_grid'] = make_grid(sheet.crop((512,512,1024,1024)), size)
    # New interaction poses extend the existing cast; original gameplay atlases
    # stay untouched. Normalize generated art to the same character/anchor size.
    if name == 'tiffany':
        metadata['stairs_grids'] = []
        stairs = Image.open(ROOT/'assets/art/story/tiffany-stairs-source.png').convert('RGBA')
        for i in range(6):
            frame = stairs.crop((i%3*512,i//3*512,i%3*512+512,i//3*512+512))
            frame = frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            frame = frame.resize((276,276),Image.Resampling.NEAREST)
            canvas = Image.new('RGBA',(512,512))
            canvas.alpha_composite(frame,(118,196))
            part = f'stairs-{i}'
            box = canvas.getchannel('A').getbbox()
            canvas.crop(box).save(folder/f'{part}.png')
            canvas.save(ROOT/f'assets/art/story/tiffany-{part}.png')
            images[part] = {'crop':list(box),'frame':-1,'texture':f'res://assets/art/story/tiffany-{part}.png','markers':{'hand_front':[73,-154],'head':[13,-205]}}
            metadata['stairs_grids'].append(make_grid(canvas,size))
    if name == 'vanessa':
        lean = Image.open(ROOT/'assets/art/story/vanessa-lean-source.png').convert('RGBA')
        box = lean.getchannel('A').point(lambda a:255 if a>64 else 0).getbbox()
        lean = lean.crop(box)
        width = round(lean.width*245/lean.height)
        lean = lean.resize((width,245),Image.Resampling.NEAREST)
        canvas = Image.new('RGBA',(512,512))
        canvas.alpha_composite(lean,(210,205))
        box = canvas.getchannel('A').getbbox()
        canvas.crop(box).save(folder/'rail-lean.png')
        canvas.save(ROOT/'assets/art/story/vanessa-rail-lean.png')
        images['rail-lean'] = {'crop':list(box),'frame':-1,'texture':'res://assets/art/story/vanessa-rail-lean.png','markers':{'hand_front':[107,-194],'head':[15,-220]}}
        metadata['lean_grid'] = make_grid(canvas,size)
    if name == 'tango':
        look = Image.open(ROOT/'assets/art/story/tango-look-back-source.png').convert('RGBA')
        look = look.crop(look.getchannel('A').point(lambda a:255 if a>64 else 0).getbbox())
        look = look.resize((round(look.width*155/look.height),155),Image.Resampling.NEAREST)
        canvas = Image.new('RGBA',(512,512))
        canvas.alpha_composite(look,(142,295))
        box = canvas.getchannel('A').getbbox()
        canvas.crop(box).save(folder/'look-back.png')
        canvas.save(ROOT/'assets/art/story/tango-look-back.png')
        images['look-back'] = {'crop':list(box),'frame':-1,'texture':'res://assets/art/story/tango-look-back.png','markers':{'head':[25,-130],'hand_front':[5,-110]}}
    (folder / 'source.json').write_text(json.dumps(metadata))
print('Prepared existing pixel cast for Rigby:', ', '.join(IDS))
