"""Deterministic final cleanup of generated sheets; no artwork is synthesized.
Removes magenta, discards tiny neighboring-cell fragments, crops, aligns and resizes.
"""
from pathlib import Path
from collections import deque
from PIL import Image
import json

ROOT = Path(__file__).resolve().parents[1]
for family, rows, cols in [('terrain', 4, 4), ('roads', 4, 4), ('props', 4, 4), ('roofs', 2, 3)]:
    source = Image.open(ROOT / 'assets/source' / f'{family}-raw.png').convert('RGBA')
    output = ROOT / 'assets/sprites' / family
    atlas = Image.new('RGBA', (cols * 64, rows * 64))
    report = []
    for index in range(rows * cols):
        x, y = index % cols, index // cols
        bounds = (round(x * source.width / cols), round(y * source.height / rows), round((x + 1) * source.width / cols), round((y + 1) * source.height / rows))
        cell = source.crop(bounds)
        pixels = cell.load()
        foreground = set()
        for cy in range(cell.height):
            for cx in range(cell.width):
                r, g, b, a = pixels[cx, cy]
                if r > g + 40 and b > g + 40:
                    pixels[cx, cy] = (0, 0, 0, 0)
                else:
                    foreground.add((cx, cy))
        components = []
        while foreground:
            seed = foreground.pop()
            todo = [seed]
            component = [seed]
            while todo:
                px, py = todo.pop()
                for q in [(px-1, py), (px+1, py), (px, py-1), (px, py+1)]:
                    if q in foreground:
                        foreground.remove(q)
                        todo.append(q)
                        component.append(q)
            components.append(component)
        largest = max(len(c) for c in components)
        for component in components:
            if len(component) < max(12, largest * 0.018):
                for pt in component: pixels[pt] = (0, 0, 0, 0)
        bbox = cell.getbbox()
        crop = cell.crop(bbox)
        frame = Image.new('RGBA', (64, 64))
        if family in ['terrain', 'roads']:
            # Surfaces must fill their tile, with no transparent seams.
            frame = crop.resize((64, 64), Image.Resampling.NEAREST)
            if family == 'terrain':
                # Use opaque interior bounds for uninterrupted square ground.
                inset = max(1, int(min(crop.size) * 0.012))
                frame = crop.crop((inset, inset, crop.width-inset, crop.height-inset)).resize((64, 64), Image.Resampling.NEAREST)
        else:
            crop.thumbnail((59, 59), Image.Resampling.NEAREST)
            frame.alpha_composite(crop, ((64-crop.width)//2, (64-crop.height)//2))
        frame.save(output / f'sprite-{index+1}.png')
        atlas.alpha_composite(frame, (x*64, y*64))
        report.append({'sprite': index+1, 'source_bbox': bbox, 'output_bbox': frame.getbbox()})
    atlas.save(output / 'sheet-transparent.png')
    (ROOT / 'assets/source' / f'{family}-final-qc.json').write_text(json.dumps(report, indent=2))
    print(f'{family}: {len(report)} sprites')
