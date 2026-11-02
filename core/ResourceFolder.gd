class_name ResourceFolder
extends RefCounted

## Loads every resource of one type saved in a folder, so adding content (a card, a
## villager, later a feat or reward) = saving a new .tres there, with no code to change.

static func load_all(folder: String, type_check: Callable, label: String = "ResourceFolder") -> Array[Resource]:
	var found: Array[Resource] = []
	var dir := DirAccess.open(folder)
	if dir == null:
		push_error("%s: can't open %s" % [label, folder])
		return found
	var files := dir.get_files()
	files.sort()
	for file in files:
		# Exported builds list "x.tres.remap"; load() still takes the original name
		file = file.trim_suffix(".remap")
		if not file.ends_with(".tres") and not file.ends_with(".res"):
			continue
		var res := load(folder.path_join(file))
		if type_check.call(res):
			found.append(res)
		else:
			push_warning("%s: %s is not the expected type" % [label, file])
	return found
