class_name TruckInteractable
extends InteractableTarget

@export_enum("DriverSeat", "PassengerSeat", "CargoAnchor") var role: String = "DriverSeat"

var truck_owner: Node3D = null


func _ready() -> void:
	super._ready()
	_refresh_prompt()


func _refresh_prompt() -> void:
	if truck_owner != null and truck_owner.has_method("get_interaction_prompt_for_role"):
		var info: Dictionary = truck_owner.call("get_interaction_prompt_for_role", role)
		action_key_label = String(info.get("key", "E"))
		prompt_description = String(info.get("description", "Interact"))
		interaction_enabled = bool(info.get("enabled", true))
		disabled_reason = String(info.get("reason", ""))


func get_prompt_text() -> String:
	_refresh_prompt()
	return super.get_prompt_text()


func can_interact_from(origin: Vector3) -> Dictionary:
	_refresh_prompt()
	var base_check: Dictionary = super.can_interact_from(origin)
	if not bool(base_check.get("allowed", false)):
		return base_check
	if truck_owner != null and truck_owner.has_method("can_interact_with_role"):
		return truck_owner.call("can_interact_with_role", role, origin)
	return base_check


func perform_interaction(actor: Node3D) -> String:
	if truck_owner != null and truck_owner.has_method("interact_with_role"):
		var msg: String = String(truck_owner.call("interact_with_role", role, actor))
		_refresh_prompt()
		interacted.emit(actor)
		return msg
	return super.perform_interaction(actor)
