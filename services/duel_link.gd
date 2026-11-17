class_name DuelLink
extends Node
## The Duel socket (docs/DUEL_MODE.md, section 3; the server's side is
## backend/src/duel_ws.rs): one WebSocket to our server, JSON text messages.
## It signs in with the session's token on open, and every message from the
## server comes out as `received`. With no server (the client is not ours) it
## never opens and `closed` says so.

## A message from the server: {"t": "matched", ...}.
signal received(msg: Dictionary)
## The socket closed (or never opened); `why` for the screen.
signal closed(why: String)
## Every physics frame while open: DuelFlow sends the ticks from here.
signal ticked

const NO_SERVER := "Duels need a connection to the server."
const LOST := "Lost the connection to the server."

var _client: FlapjawClient
var _peer: WebSocketPeer
var _hello := {}
var _said_hello := false


func _init(client: BackendClient) -> void:
	_client = client as FlapjawClient
	name = "DuelLink"


func is_online() -> bool:
	return _client != null


func is_open() -> bool:
	return _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN


## Opens the socket and says hello as this player.
func open(player_name: String, flyer: String) -> void:
	if _client == null:
		closed.emit(NO_SERVER)
		return
	if _peer != null and _peer.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		return
	var ok: bool = await _client.ensure_session()
	if not ok:
		closed.emit(LOST)
		return
	var where := _client.duel_socket()
	_hello = {
		"t": "hello",
		"token": where.token,
		"version": SimConfig.GAMEPLAY_VERSION,
		"name": player_name,
		"flyer": flyer,
	}
	_said_hello = false
	_peer = WebSocketPeer.new()
	if _peer.connect_to_url(str(where.url)) != OK:
		_peer = null
		closed.emit(LOST)


func send(msg: Dictionary) -> void:
	if is_open():
		_peer.send_text(JSON.stringify(msg))


func close() -> void:
	if _peer != null:
		_peer.close()


func _process(_delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()
	var state := _peer.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _said_hello:
			_said_hello = true
			send(_hello)
		while _peer.get_available_packet_count() > 0:
			var data: Variant = JSON.parse_string(_peer.get_packet().get_string_from_utf8())
			if data is Dictionary:
				received.emit(data as Dictionary)
	elif state == WebSocketPeer.STATE_CLOSED:
		_peer = null
		closed.emit(LOST)


func _physics_process(_delta: float) -> void:
	if is_open():
		ticked.emit()
