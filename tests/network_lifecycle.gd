extends SceneTree
var session
var index: int = 0
var scenario: String = "disconnects"
var started_at: int = 0
var launched: bool = false
var stage: int = 0
var passed: bool = false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() == 2:
			if pair[0] == "index": index = int(pair[1])
			if pair[0] == "scenario": scenario = pair[1]
	_start.call_deferred()

func _start() -> void:
	session = root.get_node("Session")
	started_at = Time.get_ticks_msec()
	var port := 24788 if scenario == "disconnects" else 24789
	if index == 0:
		session.host("Host", false, port)
		session.set_ready(true)
	else:
		session.join("127.0.0.1", "Client%d" % index, port)

func _process(_delta: float) -> bool:
	if session == null or passed:
		return false
	if Time.get_ticks_msec() - started_at > 17000:
		push_error("LIFECYCLE timeout: %s index=%d status=%s stage=%d" % [scenario, index, session.status, stage])
		quit(1)
		return false
	if session.status == "lobby":
		if index == 0 and launched:
			if scenario == "disconnects" and stage == 2 and session.roster.size() == 1 and session.message.contains("cancelada"):
				_pass()
			return false
		if index == 0:
			if session.roster.size() == (4 if scenario == "disconnects" else 2) and session.can_start():
				session.start_match(729)
				launched = true
		else:
			for entry: Dictionary in session.roster:
				if entry.id == session.local_id() and not entry.ready:
					session.set_ready(true)
	if session.status == "match":
		launched = true
		var time: float = session.current_state.time
		if scenario == "disconnects":
			if index == 0:
				if stage == 0 and session.roster.size() == 3:
					stage = 1
				elif stage == 1 and session.roster.size() == 2:
					stage = 2
			elif time > (1.0 + float(3 - index) * 1.5):
				# Verify roster updates propagated before each remaining peer exits.
				if session.roster.size() != index + 1:
					push_error("Disconnected roster was not synchronized")
					quit(1)
				else:
					_pass()
		elif index == 0 and time > 1.0:
			_pass()
	if scenario == "host_exit" and index == 1 and launched and session.status == "menu":
		if session.message.contains("anfitrión"):
			_pass()
		else:
			push_error("Missing host disconnect notice")
			quit(1)
	return false

func _pass() -> void:
	passed = true
	print("LIFECYCLE PASS %s index=%d" % [scenario, index])
	session.leave()
	quit(0)
