extends Node2D
const MotionTrack = preload("res://scripts/core/motion_track.gd")
var local_simulation := false
var motion := MotionTrack.new()
var initialized := false
var last_position := Vector2.ZERO

func update_motion(point: Vector2, stamp: float, teleport: bool = false) -> void:
	var snap := teleport or not initialized or last_position.distance_to(point) > 90.0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON if local_simulation else Node.PHYSICS_INTERPOLATION_MODE_OFF
	if local_simulation:
		# Called from Session's physics tick: Godot interpolates at display refresh rate.
		position = point
		if snap:
			reset_physics_interpolation()
	else:
		motion.push(point, stamp, snap)
		if snap:
			position = point
	last_position = point
	initialized = true

func advance_motion(delta: float) -> void:
	if not local_simulation and initialized:
		position = motion.advance(delta)
