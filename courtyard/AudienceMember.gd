class_name AudienceMember
extends Node3D

## Someone watching the game from the courtyard's edge. The Courtyard places members
## in its spots and tells all of them about the match's big moments (Courtyard.MOMENTS);
## each reacts in its own way. Villagers are members today (Villager); an online
## spectator would be another member, reacting to their own emote messages instead, in
## the same spots, so the courtyard needs no changes for them.

## A big moment happened ("capture", "near_miss", "big_throw", "home", "gate", "forfeit", "win").
func react(_moment: StringName) -> void:
	pass
