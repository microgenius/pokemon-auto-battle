extends Node
## Autoload: WebSocket client for the host role.
##
## The Godot client owns the simulation; this node is the only thing that talks
## to the Node server. It reconnects on its own because a dropped socket used to
## silently kill betting for the rest of the match with nothing on screen to say
## so.

signal connected_to_server
signal disconnected_from_server
signal bets_updated(bets_dict)
signal emote_received(username, pokemon_name, emote_type)
signal bet_results_received(results: Dictionary)
## Lobby roster: [{ "username": String, "ready": bool }]
signal players_updated(players: Array)
## Every named spectator has pressed ready.
signal all_ready
## A spectator paid for a heal; the host is the only thing that can apply it.
signal heal_requested(id: int, alias: String, amount: float, username: String)
## Emitted while retrying so the UI can show "reconnecting (2/8)".
signal reconnect_attempt(attempt: int, max_attempts: int)
signal reconnect_failed

const MAX_RECONNECT_ATTEMPTS := 8
const RECONNECT_BASE_DELAY := 1.0
const RECONNECT_MAX_DELAY := 15.0

var socket := WebSocketPeer.new()
var is_connected_to_server := false
var current_bets: Dictionary = {}

var _should_be_connected := false
var _reconnect_attempts := 0
var _reconnect_timer: Timer = null


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	set_process(false)

	_reconnect_timer = Timer.new()
	_reconnect_timer.one_shot = true
	_reconnect_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_reconnect_timer.timeout.connect(_attempt_reconnect)
	add_child(_reconnect_timer)


func get_server_url() -> String:
	if get_node_or_null("/root/Settings"):
		return get_node("/root/Settings").get_host_socket_url()
	return "ws://127.0.0.1:3000/?role=host"


func connect_to_server() -> void:
	if get_node_or_null("/root/Global"):
		if not get_node("/root/Global").is_multiplayer_host:
			return  # Spectator build: never opens a host socket.

	_should_be_connected = true
	_reconnect_attempts = 0
	_open_socket()


func disconnect_from_server() -> void:
	# Explicit teardown: stop trying to come back.
	_should_be_connected = false
	_reconnect_timer.stop()
	if is_connected_to_server:
		socket.close()
	is_connected_to_server = false
	set_process(false)


func _open_socket() -> void:
	var url := get_server_url()
	print("NetworkManager: connecting -> ", url)
	var err := socket.connect_to_url(url)
	if err != OK:
		print("NetworkManager: connect failed with error ", err)
		set_process(false)
		_schedule_reconnect()
	else:
		set_process(true)


func _schedule_reconnect() -> void:
	if not _should_be_connected:
		return

	if _reconnect_attempts >= MAX_RECONNECT_ATTEMPTS:
		print("NetworkManager: giving up after ", _reconnect_attempts, " attempts")
		reconnect_failed.emit()
		return

	_reconnect_attempts += 1
	# Exponential backoff, capped. Retrying every frame against a server that is
	# simply not running just burns CPU and fills the log.
	var delay: float = minf(RECONNECT_BASE_DELAY * pow(2.0, _reconnect_attempts - 1), RECONNECT_MAX_DELAY)
	print("NetworkManager: reconnecting in %.1fs (%d/%d)" % [delay, _reconnect_attempts, MAX_RECONNECT_ATTEMPTS])
	reconnect_attempt.emit(_reconnect_attempts, MAX_RECONNECT_ATTEMPTS)
	_reconnect_timer.start(delay)


func _attempt_reconnect() -> void:
	if not _should_be_connected:
		return
	# WebSocketPeer cannot be reused after close; start from a clean peer.
	socket = WebSocketPeer.new()
	_open_socket()


func _process(_delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not is_connected_to_server:
				is_connected_to_server = true
				_reconnect_attempts = 0
				print("NetworkManager: connected")
				connected_to_server.emit()

			while socket.get_available_packet_count() > 0:
				var packet := socket.get_packet()
				_handle_message(packet.get_string_from_utf8())

		WebSocketPeer.STATE_CLOSED:
			var was_connected := is_connected_to_server
			is_connected_to_server = false
			set_process(false)
			if was_connected:
				print("NetworkManager: disconnected. Code: ", socket.get_close_code(), " Reason: ", socket.get_close_reason())
				disconnected_from_server.emit()
			_schedule_reconnect()


func _handle_message(message: String) -> void:
	var json := JSON.new()
	if json.parse(message) != OK:
		print("NetworkManager: JSON parse error: ", message)
		return

	var data = json.data
	if typeof(data) != TYPE_DICTIONARY or not data.has("type"):
		return

	match data["type"]:
		"BETS_UPDATE":
			if data.has("bets"):
				current_bets = data["bets"]
				bets_updated.emit(current_bets)
		"EMOTE":
			if data.has("username") and data.has("pokemon") and data.has("emoteType"):
				emote_received.emit(data["username"], data["pokemon"], data["emoteType"])
		"BET_RESULTS":
			if data.has("results"):
				bet_results_received.emit(data["results"])
		"PLAYERS_UPDATE":
			players_updated.emit(data.get("players", []))
		"ALL_READY":
			all_ready.emit()
		"APPLY_HEAL":
			heal_requested.emit(
				int(data.get("id", 0)), str(data.get("alias", "")),
				float(data.get("amount", 0.0)), str(data.get("username", "")),
			)


func send_message(dict_data: Dictionary) -> void:
	if is_connected_to_server and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify(dict_data))


func broadcast_lobby(options_array: Array) -> void:
	send_message({"type": "LOBBY_UPDATE", "options": options_array})


func broadcast_match_start() -> void:
	send_message({"type": "MATCH_START"})


func broadcast_match_end(winner_alias: String, winner_name: String) -> void:
	send_message({"type": "MATCH_END", "winner": winner_alias, "winner_name": winner_name})


## The alias does not change here — that is the point of having one. The names
## ride along purely so the spectator UI can relabel the card.
func broadcast_evolution(alias: String, old_name: String, new_name: String, new_sprite_url: String) -> void:
	send_message({
		"type": "EVOLUTION",
		"alias": alias,
		"old_name": old_name,
		"new_name": new_name,
		"new_sprite_url": new_sprite_url,
	})
