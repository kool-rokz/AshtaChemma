class_name DevFlags
extends RefCounted

## Developer command-line options, for testing online play with several windows.
## Only honoured in debug builds (the editor, or a debug export): a shipped release
## build ignores them all. Pass them after `--`, e.g.
##   godot --path . -- --host --autostart=2 --bot --no-mcp
##
##   --host [--port=9080] [--autostart=N] [--no-cards]   host at once (start when N players are in)
##   --join=ADDRESS                                        join at once (room code or address)
##   --name=NAME
##   --bot          this window plays its own seat (random legal moves, auto draft)
##   --no-tunnel    host on the local network only (no room code)
##   --no-mcp       detach the editor's MCP tools, so they only talk to one game window

## Keep the first offered cards instead of showing the draft screen (set by --bot).
static var auto_draft: bool = false

## The developer options given on the command line ({} in release builds or when
## neither --host nor --join is present). Keys keep their dashes: opts["--port"].
static func parse() -> Dictionary:
	if not OS.is_debug_build():
		return {}
	var opts := {}
	for arg in OS.get_cmdline_user_args():
		opts[arg.get_slice("=", 0)] = arg.get_slice("=", 1) if "=" in arg else "true"
	if not opts.has("--host") and not opts.has("--join"):
		return {}
	return opts

## Applies the options that don't depend on the menu: --no-mcp and --bot.
static func apply_tooling(opts: Dictionary, tree: SceneTree) -> void:
	if opts.has("--no-mcp"):
		for tool_name in ["MCPGameInspector", "MCPScreenshot", "MCPInputService"]:
			var tool := tree.root.get_node_or_null(tool_name)
			if tool:
				tool.queue_free()
	if opts.has("--bot"):
		auto_draft = true
		var bot := DevBot.new()
		bot.name = "DevBot"
		tree.root.add_child(bot)
