class_name Storage
extends RefCounted

## Where the game keeps its small files (settings, the last room's seat token).
## Files under user:// on desktop, web (the browser's IndexedDB) and phones. A console
## port subclasses this for the platform's save data (mounting, commit after writing)
## and returns it from Platform.storage(). Nothing else in the game opens files there.

const ROOT := "user://"

func read_text(file_name: String) -> String:
	var file := FileAccess.open(ROOT + file_name, FileAccess.READ)
	return file.get_as_text() if file else ""

func write_text(file_name: String, text: String) -> bool:
	var file := FileAccess.open(ROOT + file_name, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	return true
