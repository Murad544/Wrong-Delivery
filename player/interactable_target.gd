class_name InteractableTarget
extends Area3D

signal interacted(actor: Node3D)

@export var action_key_label: String = "E"
@export var prompt_description: String = "Interact"
@export var interaction_enabled: bool = true
@export var disabled_reason: String = "Cannot interact right now"
@export_range(0.5, 10.0, 0.1) var max_interaction_distance: float = 3.0
@export var feedback_message: String = "Interaction complete"

var _interaction_count: int = 0


func _ready() -> void:
	collision_layer = 4 # Layer 3: Interactable (bitmask value 4)
	collision_mask = 0
	monitoring = false
	monitorable = true


func get_prompt_text() -> String:
	if not interaction_enabled:
		return "%s — %s (%s)" % [action_key_label, prompt_description, disabled_reason]
	return "%s — %s" % [action_key_label, prompt_description]


func can_interact_from(origin: Vector3) -> Dictionary:
	var distance: float = global_position.distance_to(origin)
	if distance > max_interaction_distance:
		return {
			"allowed": false,
			"reason": "Too far away"
		}
	if not interaction_enabled:
		return {
			"allowed": false,
			"reason": disabled_reason
		}
	return {
		"allowed": true,
		"reason": ""
	}


func perform_interaction(actor: Node3D) -> String:
	var check: Dictionary = can_interact_from(actor.global_position)
	if not bool(check.get("allowed", false)):
		return String(check.get("reason", "Cannot interact"))
	_interaction_count += 1
	interacted.emit(actor)
	return "%s (#%d)" % [feedback_message, _interaction_count]
