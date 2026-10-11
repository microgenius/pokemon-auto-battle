# Run from anywhere: all asset paths below are relative to the project root.
import os as _os
_os.chdir(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)), ".."))

import urllib.request
import os

ids = ["0001", "0002", "0003", "0004", "0005", "0006", "0007", "0008", "0009", "0063", "0064", "0065", "0092", "0093", "0094"]
anims = ["Walk", "Hop", "Idle", "Attack"]

base_url = "https://raw.githubusercontent.com/PMDCollab/SpriteCollab/master/sprite/{}/{}-Anim.png"

os.makedirs("assets/pokemon_sprites", exist_ok=True)

for pid in ids:
    os.makedirs(f"assets/pokemon_sprites/{pid}", exist_ok=True)
    for anim in anims:
        url = base_url.format(pid, anim)
        filepath = f"assets/pokemon_sprites/{pid}/{anim}-Anim.png"
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req) as response:
                with open(filepath, 'wb') as f:
                    f.write(response.read())
            print(f"Downloaded: {filepath}")
        except Exception as e:
            print(f"Failed to download {url}: {e}")
