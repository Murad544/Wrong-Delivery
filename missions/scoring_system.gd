class_name ScoringSystem
extends RefCounted


static func calculate_mission_score(
	current_durability: float,
	max_durability: float,
	elapsed_seconds: float,
	target_time_seconds: float = 300.0,
	major_mistakes_count: int = 0,
	penalty_per_mistake: int = 15
) -> Dictionary:
	var safe_max_dur: float = maxf(max_durability, 1.0)
	var clamped_dur: float = clampf(current_durability, 0.0, safe_max_dur)
	var durability_lost_pct: float = (1.0 - (clamped_dur / safe_max_dur)) * 100.0
	var damage_penalty: int = clampi(roundi(durability_lost_pct), 0, 100)

	var overtime_seconds: float = maxf(0.0, elapsed_seconds - target_time_seconds)
	var overtime_penalty: int = 0
	if overtime_seconds > 0.0:
		# 2 points per 10 seconds over the generous target time, capped at 30
		overtime_penalty = clampi(int(floor(overtime_seconds / 10.0)) * 2, 0, 30)

	var major_mistake_penalty: int = maxi(0, major_mistakes_count) * maxi(0, penalty_per_mistake)

	# Deterministic formula from AGENTS.md §7:
	# score = clamp(100 - damage_penalty - overtime_penalty - major_mistake_penalty, 0, 100)
	var final_score: int = clampi(
		100 - damage_penalty - overtime_penalty - major_mistake_penalty,
		0,
		100
	)

	var rating: String = get_rating_for_score(final_score)

	return {
		"final_score": final_score,
		"damage_penalty": damage_penalty,
		"overtime_penalty": overtime_penalty,
		"major_mistake_penalty": major_mistake_penalty,
		"major_mistakes_count": maxi(0, major_mistakes_count),
		"durability_remaining": clamped_dur,
		"max_durability": safe_max_dur,
		"elapsed_seconds": maxf(0.0, elapsed_seconds),
		"target_time_seconds": target_time_seconds,
		"rating": rating,
	}


static func get_rating_for_score(score: int) -> String:
	if score >= 90:
		return "S — Miracle Movers!"
	if score >= 75:
		return "A — Surprisingly Competent"
	if score >= 50:
		return "B — 'It Was Scratched When We Got Here'"
	if score >= 25:
		return "C — Structurally Questionable"
	return "D — Wrong Delivery Certified"


static func format_time_mm_ss(seconds_val: float) -> String:
	var total_sec: int = maxi(0, int(floor(seconds_val)))
	var mins: int = total_sec / 60
	var secs: int = total_sec % 60
	return "%02d:%02d" % [mins, secs]
