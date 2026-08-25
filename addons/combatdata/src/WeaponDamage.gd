@tool
class_name WeaponDamage
extends Resource

@export var amount: int = 1

var _source: Node3D

static func new_probe() -> WeaponDamage:
	var out := WeaponDamage.new()
	out.amount = 0
	return out


func from(source: Node3D) -> WeaponDamage:
	_source = source
	return self


func is_probe() -> bool:
	return amount == 0
