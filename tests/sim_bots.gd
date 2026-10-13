extends Node
## Partida solo con bots, más rápida que tiempo real:
##   godot --headless --path . --fixed-fps 60 res://tests/sim_bots.tscn -- 15
## Mide la duración de las rondas y los parones: tiempo que un jugador vivo pasa sin acercarse a la meta.

const STALL_SECONDS := 3.0
const LONG_STALL := 6.0
const FAR := 1 << 30

var rounds := 15
var durations: Array[float] = []
var stalls: Array[float] = []
var unresolved := 0
var _best: Dictionary[int, int] = {}
var _since: Dictionary[int, float] = {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		rounds = int(args[0])
	var world := Node2D.new()
	add_child(world)
	Game.world = world
	Game.local_slot = -1
	Config.set_value("rounds", rounds)
	Game.phase_changed.connect(_on_phase)
	Game.start_match()


func _on_phase(phase: Game.Phase) -> void:
	match phase:
		Game.Phase.COUNTDOWN:
			_best.clear()
			_since.clear()
		Game.Phase.ROUND_END:
			durations.append(Game.mode.time)
			for slot: int in _since:
				if _since[slot] > LONG_STALL:
					unresolved += 1
					print("sin resolver al final: ronda %d bot %d (%.1f s)" % [Game.round_index + 1, slot, _since[slot]])
		Game.Phase.MATCH_END:
			var total := 0.0
			for d in durations:
				total += d
			var long_stalls := stalls.filter(func(s: float) -> bool: return s > LONG_STALL).size()
			print("sim_bots: %d rondas, media %.1f s (máx %.1f) | parones >%.0f s: %d, >%.0f s: %d, máx %.1f s, sin resolver: %d" % [
				durations.size(), total / durations.size(), durations.max(), STALL_SECONDS, stalls.size(),
				LONG_STALL, long_stalls, stalls.max() if not stalls.is_empty() else 0.0, unresolved])
			get_tree().quit()


func _physics_process(delta: float) -> void:
	if Game.phase != Game.Phase.PLAYING:
		return
	var mode = Game.mode
	for player in Game.players:
		if player.state != player.State.ALIVE:
			_best[player.slot] = FAR
			_since[player.slot] = 0.0
			continue
		var d: int = mode.dist_goal[mode.data.index(mode.cell_at(player.position))]
		if d < _best.get(player.slot, FAR):
			var stalled: float = _since.get(player.slot, 0.0)
			if stalled > STALL_SECONDS:
				stalls.append(stalled)
			_best[player.slot] = d
			_since[player.slot] = 0.0
		else:
			_since[player.slot] = _since.get(player.slot, 0.0) + delta
