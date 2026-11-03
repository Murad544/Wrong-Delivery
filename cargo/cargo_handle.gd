class_name CargoHandle
extends InteractableTarget

@export var handle_id: int = 0
@export var handle_label: String = "Handle"

var cargo_owner: Node3D = null
var occupying_actor: Node3D = null


func _ready() -> void:
	super._ready()
	_refresh_prompt_description()


func set_occupying_actor(actor: Node3D) -> void:
	occupying_actor = actor
	_refresh_prompt_description()


func is_occupied() -> bool:
	return occupying_actor != null and is_instance_valid(occupying_actor)


func _refresh_prompt_description() -> void:
	var item_name: String = "Cargo"
	if cargo_owner != null and cargo_owner.has_method("get_display_name"):
		item_name = String(cargo_owner.call("get_display_name"))

	if is_occupied():
		prompt_description = "Release %s (%s)" % [item_name, handle_label]
	else:
		prompt_description = "Grab %s (%s)" % [item_name, handle_label]


func get_prompt_text() -> String:
	_refresh_prompt_description()
	return super.get_prompt_text()


func can_interact_from(origin: Vector3) -> Dictionary:
	var base_check: Dictionary = super.can_interact_from(origin)
	if not bool(base_check.get("allowed", false)):
		return base_check

	if cargo_owner != null and cargo_owner.has_method("evaluate_handle_interaction"):
		return cargo_owner.call("evaluate_handle_interaction", handle_id, origin)

	return base_check


func perform_interaction(actor: Node3D) -> String:
	if cargo_owner != null and cargo_owner.has_method("interact_with_handle"):
		var result: String = String(cargo_owner.call("interact_with_handle", handle_id, actor))
		_refresh_prompt_description()
		interacted.emit(actor)
		return result
	return super.perform_interaction(actor)
