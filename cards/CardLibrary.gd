class_name CardLibrary
extends RefCounted

## Loads every CardData .tres in a folder, so adding a card = saving a new file there.

static func load_cards(folder: String) -> Array[CardData]:
	var cards: Array[CardData] = []
	for res in ResourceFolder.load_all(folder, func(r): return r is CardData, "CardLibrary"):
		cards.append(res)
	return cards
