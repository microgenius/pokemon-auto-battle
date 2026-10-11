# Run from anywhere: all asset paths below are relative to the project root.
import os as _os
_os.chdir(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)), ".."))

from PIL import Image
import glob

files = glob.glob("assets/pokemon_sprites/0001/*Anim.png")
for f in files:
    img = Image.open(f)
    print(f"{f}: {img.size}")
