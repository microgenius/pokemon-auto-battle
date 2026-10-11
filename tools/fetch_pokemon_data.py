# Run from anywhere: all asset paths below are relative to the project root.
import os as _os
_os.chdir(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)), ".."))

import urllib.request
import json
import concurrent.futures

def fetch_json(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla'})
    return json.loads(urllib.request.urlopen(req).read())

# Pre-fetch evolution chains to assign to species
evolution_cache = {} # url -> chain
species_data_cache = {} # id -> species_data

def get_evolves_to_names(evolves_to_list):
    # Returns list of names it can evolve into
    names = []
    for e in evolves_to_list:
        url = e['species']['url']
        # only keep gen 1 and 2
        p_id = int(url.rstrip('/').split('/')[-1])
        if p_id <= 251:
            names.append(e['species']['name'])
    return names

def parse_chain_for_species(chain, target_name, current_stage=1, total_stages=1):
    # First, find total stages
    def get_max_depth(c):
        if not c['evolves_to']: return 1
        return 1 + max([get_max_depth(x) for x in c['evolves_to']])
    
    max_stages = get_max_depth(chain)
    
    # Then find the target species in the chain
    def find_node(c, stage):
        if c['species']['name'] == target_name:
            return c, stage
        for e in c['evolves_to']:
            res = find_node(e, stage + 1)
            if res: return res
        return None
        
    node, stage = find_node(chain, 1)
    if node:
        return {
            'stage': stage,
            'max_stages': max_stages,
            'is_basic': (stage == 1),
            'evolves_to': get_evolves_to_names(node['evolves_to'])
        }
    return {'stage': 1, 'max_stages': 1, 'is_basic': True, 'evolves_to': []}

def fetch_pokemon(pid):
    try:
        p_data = fetch_json(f"https://pokeapi.co/api/v2/pokemon/{pid}")
        s_data = fetch_json(f"https://pokeapi.co/api/v2/pokemon-species/{pid}")
        
        chain_url = s_data['evolution_chain']['url']
        if chain_url not in evolution_cache:
            evolution_cache[chain_url] = fetch_json(chain_url)
            
        chain_data = evolution_cache[chain_url]['chain']
        evo_info = parse_chain_for_species(chain_data, s_data['name'])
        
        # Simplified level thresholds
        evolution_level = -1
        if evo_info['evolves_to']:
            if evo_info['max_stages'] == 3:
                if evo_info['stage'] == 1:
                    evolution_level = 13
                elif evo_info['stage'] == 2:
                    evolution_level = 26
            elif evo_info['max_stages'] == 2:
                evolution_level = 20
                
        stats = {s['stat']['name']: s['base_stat'] for s in p_data['stats']}
        
        return {
            'id': pid,
            'name': p_data['name'],
            'base_hp': stats.get('hp', 50),
            'base_atk': stats.get('attack', 50),
            'base_def': stats.get('defense', 50),
            'base_sp_atk': stats.get('special-attack', 50),
            'base_sp_def': stats.get('special-defense', 50),
            'base_spd': stats.get('speed', 50),
            'is_basic': evo_info['is_basic'],
            'evolves_to': evo_info['evolves_to'],
            'evolution_level': evolution_level,
            'stage': evo_info['stage'],
            'max_stages': evo_info['max_stages']
        }
    except Exception as e:
        print(f"Error fetching {pid}: {e}")
        return None

results = []
with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
    futures = {executor.submit(fetch_pokemon, i): i for i in range(1, 252)}
    for future in concurrent.futures.as_completed(futures):
        res = future.result()
        if res:
            results.append(res)
            
results.sort(key=lambda x: x['id'])

with open('assets/pokemon_advanced_data.json', 'w') as f:
    json.dump(results, f, indent=4)
print(f"Saved {len(results)} pokemons.")
