extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	var output := FileAccess.open(args[0], FileAccess.WRITE)
	if output == null:
		quit(1)
		return
	output.store_string("Godot Engine\n\n" + Engine.get_license_text() + "\n\n")
	output.store_string("Third-party component notices:\n" + JSON.stringify(Engine.get_copyright_info(), "\t") + "\n\n")
	var licenses := Engine.get_license_info()
	for license_name in licenses:
		output.store_string(str(license_name) + "\n" + str(licenses[license_name]) + "\n\n")
	output.close()
	print("LICENSE_DUMP_PASS")
	quit()
