# Run from anywhere: all asset paths below are relative to the project root.
import os as _os
_os.chdir(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)), ".."))

import urllib.request
import json

url = "https://pokeapi.co/api/v2/pokemon?limit=251"
try:
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read())
        
    pokemon_dict = {}
    for i, p in enumerate(data['results']):
        pid = f"{i+1:04d}"
        pokemon_dict[pid] = p['name'].capitalize()
        
    with open('assets/pokemon_data.json', 'w') as f:
        json.dump(pokemon_dict, f, indent=4)
        
    print("Successfully generated pokemon_data.json with 251 names.")
except Exception as e:
    print(f"Error: {e}")
