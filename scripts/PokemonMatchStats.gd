class_name PokemonMatchStats
extends RefCounted
## One fighter's record for a single match.
##
## This replaces the loose dictionaries that used to be built in three different
## places with three different sets of keys — the winner's record, for instance,
## was appended once with `dodges`/`criticals` and once without, so whether a
## field existed depended on which code path had run. A single type means every
## consumer sees the same shape.

## Slot identity, stable across evolution. The server matches on this; `name` is
## only ever displayed.
var alias: String = ""
var name: String = ""
var color: Color = Color.WHITE
var kills: int = 0
var attacks: int = 0
var hits: int = 0
var dodges: int = 0
var criticals: int = 0
var has_evolved: bool = false
var evolution_count: int = 0
## True once the fighter has reached its final form and has nowhere left to
## evolve. Species with no evolution at all start out complete.
var evolution_complete: bool = false

## Order of elimination, 1-based. Stays 0 for whoever is still standing.
var death_order: int = 0


static func from_pokemon(pokemon) -> PokemonMatchStats:
	var stats := PokemonMatchStats.new()
	stats.alias = pokemon.alias
	stats.name = pokemon.pokemon_name
	if pokemon.sprite:
		stats.color = pokemon.sprite.modulate
	stats.kills = pokemon.score
	stats.attacks = pokemon.total_attacks
	stats.hits = pokemon.successful_hits
	stats.dodges = pokemon.total_dodges
	stats.criticals = pokemon.total_criticals
	stats.has_evolved = pokemon.has_evolved
	stats.evolution_count = pokemon.evolution_count
	# evolves_to is reloaded from the species data on every evolution, so an
	# empty list means the fighter is standing in its final form.
	stats.evolution_complete = pokemon.evolves_to.is_empty()
	return stats


func is_alive() -> bool:
	return death_order == 0


## Percentage of shots that connected, 0 when nothing was fired.
func hit_ratio() -> float:
	if attacks <= 0:
		return 0.0
	return (float(hits) / float(attacks)) * 100.0


## Wire format for the server. Colors stay client-side — the server has no use
## for them and they do not survive JSON round-tripping cleanly.
func to_dict() -> Dictionary:
	return {
		"alias": alias,
		"name": name,
		"kills": kills,
		"attacks": attacks,
		"hits": hits,
		"dodges": dodges,
		"criticals": criticals,
		"has_evolved": has_evolved,
		"evolution_count": evolution_count,
		"evolution_complete": evolution_complete,
	}


static func list_to_dicts(stats_list: Array) -> Array:
	var out: Array = []
	for entry in stats_list:
		out.append(entry.to_dict())
	return out
