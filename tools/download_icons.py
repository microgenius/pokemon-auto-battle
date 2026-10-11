# Run from anywhere: all asset paths below are relative to the project root.
import os as _os
_os.chdir(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)), ".."))

import os
import urllib.request
import concurrent.futures

ids = [f"{i:04d}" for i in range(1, 252)]

def download_icon(pid):
    pokeapi_id = int(pid)
    url = f"https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/{pokeapi_id}.png"
    filepath = f"assets/pokemon_sprites/{pid}/icon.png"
    
    if os.path.exists(filepath) and os.path.getsize(filepath) > 0:
        return True
        
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as response:
            with open(filepath, 'wb') as f:
                f.write(response.read())
        return True
    except Exception as e:
        print(f"Failed to download icon for {pid}: {e}")
        return False

print("Downloading static icons from PokeAPI...")
with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
    executor.map(download_icon, ids)
print("Finished downloading icons!")
