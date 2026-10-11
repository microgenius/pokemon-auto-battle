# Temiz bir klondan sonra bir kez çalıştır. Pokémon görselleri telif nedeniyle
# repoda yok (bkz. README, "Sprites"); hepsini açık kaynaklarından indirir.
# Var olan dosyalar atlanır, yani yarıda kalırsa tekrar çalıştırmak yeterli.
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPRITES = ROOT / "assets" / "pokemon_sprites"
POKEBALL_URL = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/items/poke-ball.png"

for script in ("download_and_generate_all.py", "download_icons.py"):
    subprocess.run([sys.executable, str(ROOT / "tools" / script)], check=True)

pokeball = SPRITES / "poke.png"
if not pokeball.exists():
    req = urllib.request.Request(POKEBALL_URL, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req) as response:
        pokeball.write_bytes(response.read())

# download_and_generate_all.py indirme hatalarını sessizce yutuyor; eksikleri burada yakala.
missing = [
    pid for pid in (f"{i:04d}" for i in range(1, 252))
    if not (SPRITES / pid / "sprite_frames.tres").exists() or not (SPRITES / pid / "icon.png").exists()
]
if missing:
    sys.exit(f"Missing {len(missing)} species ({', '.join(missing[:10])}...). Run again to fetch only those.")
print("Assets ready. Open the project in Godot.")
