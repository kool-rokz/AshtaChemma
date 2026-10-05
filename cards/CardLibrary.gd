class_name CardLibrary
extends RefCounted

## Loads every CardData .tres in a folder, so adding a card = saving a new file there.

static func load_cards(folder: String) -> Array[CardData]:
	var cards: Array[CardData] = []
	var dir := DirAccess.open(folder)
	if dir == null:
		push_error("CardLibrary: can't open %s" % folder)
		return cards
	var files := dir.get_files()
	files.sort()
	for file in files:
		# Exported builds list "x.tres.remap"; load() still takes the original name
		file = file.trim_suffix(".remap")
		if not file.ends_with(".tres") and not file.ends_with(".res"):
			continue
		var res := load(folder.path_join(file))
		if res is CardData:
			cards.append(res)
		else:
			push_warning("CardLibrary: %s is not a CardData" % file)
	return cards
