extends Node
## WebSocket client for the local Pi bridge. Owns request correlation and
## streaming fan-out; views await `request()` or subscribe to task signals.

signal ready_received(info: Dictionary)
signal bridge_closed()
signal task_delta(id: String, text: String)
signal task_finished(id: String, msg: Dictionary)
signal status_received(data: Dictionary)
signal link_changed(online: bool, label: String)

var ws_url := "ws://127.0.0.1:8791/ws"

var ws: WebSocketPeer = null
var connected := false
var server_ready := false
var desired := false
var campaign := ""
var player_handle := "GHOST"
var model := "deepseek-flash"
var mode := "real"
var pi_version := "?"
var last_error := ""
var reconnect_at := 0.0
var _req_counter := 0
var _pending: Dictionary = {}
var _ready_waiters: Array = []

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ws="):
			ws_url = arg.substr(5)
	set_process(true)

func connect_bridge(campaign_id: String, handle: String) -> void:
	campaign = campaign_id
	player_handle = handle
	desired = true
	_open_socket()

func disconnect_bridge() -> void:
	desired = false
	if ws != null:
		ws.close()
	ws = null
	connected = false
	server_ready = false

func _open_socket() -> void:
	if ws != null:
		ws.close()
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 8 * 1024 * 1024
	ws.outbound_buffer_size = 4 * 1024 * 1024
	var err := ws.connect_to_url(ws_url)
	if err != OK:
		last_error = "无法连接桥接服务 (%s)" % error_string(err)
		link_changed.emit(false, "LINK DOWN")
		reconnect_at = Time.get_ticks_msec() + 2500
	else:
		link_changed.emit(false, "LINKING…")

func _process(_delta: float) -> void:
	if ws == null:
		if desired and Time.get_ticks_msec() > reconnect_at:
			_open_socket()
		return
	ws.poll()
	while ws.get_available_packet_count() > 0:
		var pkt := ws.get_packet()
		_handle_text(pkt.get_string_from_utf8())
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not connected:
			connected = true
			server_ready = false
			_send({"type": "hello", "campaign": campaign, "player": player_handle})
			link_changed.emit(false, "HANDSHAKE…")
	elif st == WebSocketPeer.STATE_CLOSED:
		if connected or server_ready:
			connected = false
			server_ready = false
			last_error = "桥接服务断开"
			link_changed.emit(false, "LINK DOWN")
			bridge_closed.emit()
			_fail_pending("桥接服务断开")
			if desired:
				reconnect_at = Time.get_ticks_msec() + 3000
		ws = null
		if desired and Time.get_ticks_msec() > reconnect_at:
			_open_socket()

func _send(obj: Dictionary) -> bool:
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	var text := JSON.stringify(obj)
	var err := ws.send_text(text)
	if err != OK:
		last_error = "发送失败: %s" % error_string(err)
		return false
	return true

func _handle_text(text: String) -> void:
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	var t := str(data.get("type", ""))
	match t:
		"ready":
			server_ready = true
			mode = str(data.get("mode", "real"))
			model = str(data.get("model", model))
			pi_version = str(data.get("pi", {}).get("version", "?"))
			link_changed.emit(true, "LINK STABLE")
			ready_received.emit(data)
		"model":
			model = str(data.get("model", model))
		"delta":
			task_delta.emit(str(data.get("id", "")), str(data.get("text", "")))
		"done", "error":
			var id := str(data.get("id", ""))
			_pending.erase(id)
			task_finished.emit(id, data)
		"status":
			status_received.emit(data.get("data", {}))
		"reset_ok":
			task_finished.emit("__reset__", data)
		"mode_ok":
			mode = str(data.get("mode", mode))
		"pong":
			pass

func _fail_pending(reason: String) -> void:
	var ids: Array = _pending.keys()
	_pending.clear()
	for id in ids:
		task_finished.emit(str(id), {"type": "error", "id": str(id), "message": reason, "ok": false})

func ask_now(task: String, input: Dictionary, opts: Dictionary = {}) -> String:
	_req_counter += 1
	var id := "q%d_%d" % [_req_counter, Time.get_ticks_msec()]
	var payload := {
		"type": "ask",
		"id": id,
		"task": task,
		"input": input,
		"stream": bool(opts.get("stream", true)),
	}
	if opts.has("actor"):
		payload["actor"] = opts["actor"]
	if opts.has("fallback"):
		payload["fallback"] = opts["fallback"]
	if opts.has("timeoutMs"):
		payload["timeoutMs"] = opts["timeoutMs"]
	_pending[id] = true
	if not _send(payload):
		_pending.erase(id)
		call_deferred("_emit_failed", id)
	return id

func _emit_failed(id: String) -> void:
	task_finished.emit(id, {"type": "error", "id": id, "message": "链路不可用", "ok": false})

func request(task: String, input: Dictionary, opts: Dictionary = {}) -> Dictionary:
	if not server_ready:
		var waited := 0.0
		while not server_ready and waited < 30.0:
			await get_tree().create_timer(0.2).timeout
			waited += 0.2
	if not server_ready:
		return {"type": "error", "ok": false, "message": "桥接服务未连接"}
	var id := ask_now(task, input, opts)
	while true:
		var args: Array = await task_finished
		if str(args[0]) == id:
			return args[1]
	return {}

func request_status() -> void:
	_send({"type": "status"})

func request_reset() -> void:
	_send({"type": "reset"})

func set_mode(new_mode: String) -> void:
	_send({"type": "set_mode", "mode": new_mode})

func abort(actor_id: String, actor_kind: String = "gm") -> void:
	_send({"type": "abort", "actor": {"id": actor_id, "kind": actor_kind}})

func is_online() -> bool:
	return server_ready

func link_label() -> String:
	if not desired:
		return "OFFLINE"
	if server_ready:
		return "LINK STABLE"
	if connected:
		return "HANDSHAKE…"
	return "LINK DOWN"

