extends Node
# Dev tool: add this node to a scene. While the game runs, if any .gd or .tscn file under
# res://code or res://scene changes on disk, it reloads the scripts and restarts the scene
# in the same window. A node named "Player" keeps its position. Does nothing in exported builds.

const CHECK_EVERY := 0.5
const WATCH_DIRS := ["res://code", "res://scene"]

static var _player_pos = null   # carried across a reload

var _times := {}
var _timer := 0.0


func _ready():
	if not OS.has_feature("editor"):
		queue_free()
		return
	_times = _scan()
	if _player_pos != null:
		var player := get_parent().get_node_or_null("Player") as Node2D
		if player:
			player.global_position = _player_pos
		_player_pos = null


func _process(delta):
	_timer += delta
	if _timer < CHECK_EVERY:
		return
	_timer = 0.0
	var now := _scan()
	var changed: Array[String] = []
	for path in now:
		if _times.get(path) != now[path]:
			changed.append(path)
	_times = now
	if not changed.is_empty():
		_reload(changed)


func _reload(changed: Array[String]):
	for path in changed:
		if path.ends_with(".gd"):
			var scr: GDScript = load(path)
			scr.source_code = FileAccess.get_file_as_string(path)
			if scr.reload(true) != OK:
				push_warning("Live reload: %s has an error, still running the old version" % path)
				return
	var scene := get_tree().current_scene
	var player := scene.get_node_or_null("Player") as Node2D
	if player:
		_player_pos = player.global_position
	var packed: PackedScene = ResourceLoader.load(scene.scene_file_path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	get_tree().change_scene_to_packed(packed)
	print("Live reload: ", ", ".join(changed))


func _scan() -> Dictionary:
	var times := {}
	for dir in WATCH_DIRS:
		_scan_dir(dir, times)
	return times


func _scan_dir(dir: String, times: Dictionary):
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") or f.ends_with(".tscn"):
			var path := dir.path_join(f)
			times[path] = FileAccess.get_modified_time(path)
	for sub in DirAccess.get_directories_at(dir):
		_scan_dir(dir.path_join(sub), times)
