import sys
from PIL import Image
# Find the bright PLAY button: largest near-white blob in the left-center of the window.
im = Image.open(sys.argv[1]).convert("RGB")
W, H = im.size
px = im.load()
# search region: left 55% of width, vertical middle band
x0, x1 = int(W*0.20), int(W*0.55)
y0, y1 = int(H*0.45), int(H*0.80)
pts = []
for y in range(y0, y1, 3):
    for x in range(x0, x1, 3):
        r, g, b = px[x, y]
        if r > 180 and g > 180 and b > 180:   # near-white button fill
            pts.append((x, y))
if not pts:
    print("NOTFOUND"); sys.exit(1)
xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
cx, cy = sum(xs)//len(xs), sum(ys)//len(ys)
# window is 1280x600 logical at screen origin (388,383); image is 2x
sx = 388 + cx * 1280 // W
sy = 383 + cy * 600 // H
print(f"{sx} {sy} pixels={len(pts)}")
