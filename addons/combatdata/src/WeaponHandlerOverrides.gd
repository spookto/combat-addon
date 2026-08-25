## Overrides the availability of moves in WeaponHandlers.[br]
## Used to disable moves that weren't unlocked yet.
# the name is misleading
class_name WeaponHandlerOverrides
extends Resource

signal moves_updated

var _disabled_moves: Array[WeaponMove] = []


func is_move_disabled(move: WeaponMove) -> bool:
	return _disabled_moves.has(move)


func enable_move(move: WeaponMove) -> void:
	_disabled_moves.erase(move)
	moves_updated.emit.call_deferred()


func disable_move(move: WeaponMove) -> void:
	if _disabled_moves.has(move):
		return
	_disabled_moves.append(move)
	moves_updated.emit.call_deferred()
