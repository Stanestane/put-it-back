extends Node2D
## Native portrait microgames. All coordinates use the original artwork space.
const SIZE = Vector2(2501, 5001)
const INK = Color("2d3446")
const CREAM = Color("efe9d9")
const PINK = Color("b56b60")
const TEAL = Color("203e43")
const SUCCESS = Color("31594a")
const RETRY = Color("87473d")
const YELLOW = Color("fff869")
const LEVELS = [1,2,3,4,5,6,7,8,9,10,11,12,13,14,114,15,16,17,18,19,20,120,21,22,23,24,25,26]
const NAMES = {1:"Fireplace",2:"Elevator",3:"Plate stack",4:"Tower",5:"Garden",6:"Road junction",7:"Switches",8:"Handles",9:"Tools",10:"Pencils",11:"Cakes",12:"Ceramics",13:"Windows",14:"Ribbons",114:"Circles",15:"Brick arch",16:"Manhole",17:"Parquet",18:"Pills",19:"Hexagons",20:"Cookie facing",120:"Cookie shift",21:"Bathroom",22:"Bookshelf",23:"Paint tubes",24:"Juice bottles",25:"Drawers",26:"Dessert picture"}
const ExtraLevels = preload("res://scripts/extra_levels.gd")
const PuzzleInteraction = preload("res://scripts/puzzle_interaction.gd")
const PuzzleTests = preload("res://scripts/puzzle_tests.gd")
const StackTests = preload("res://scripts/stack_tests.gd")
const AdManager = preload("res://scripts/ads/ad_manager.gd")
@export var ad_settings: Resource = preload("res://resources/ads_settings.tres")
var ads
var app_foreground = true
var resume_after_ad = false
var last_back_request_ms = -1000
var interaction
var textures: Dictionary = {}
var hit_images: Dictionary = {}
var pieces: Array[Dictionary] = []
var background = ""
var state = "splash"
var level = -1
var remaining = 5.0
var phase = 0.0
var prompt = ""
var score = 0
var best = 0
var practice = false
var paused = false
var elapsed = 0.0
var splash_angle = 0.04
var testing = false
var font = preload("res://assets/fonts/COOPERB.TTF")

func _ready() -> void:
	# Android Back belongs to the game's navigation, not SceneTree's auto-quit.
	get_tree().quit_on_go_back = false
	interaction = PuzzleInteraction.new(self)
	scale = Vector2(500.0 / SIZE.x, 1000.0 / SIZE.y)
	var save = ConfigFile.new()
	if save.load("user://progress.cfg") == OK:
		best = save.get_value("game", "best", 0)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			practice = true
			start_round(int(arg.trim_prefix("--level=")))
	if "--self-test" in OS.get_cmdline_user_args():
		testing = true
		call_deferred("self_test")
	if "--gallery" in OS.get_cmdline_user_args():
		testing = true
		call_deferred("capture_gallery")

	if not testing:
		ads = AdManager.new()
		add_child(ads)
		ads.break_finished.connect(_on_ad_break_finished)
		ads.configure(ad_settings)

func tex(name: String) -> Texture2D:
	if not textures.has(name):
		if name.begins_with("DessertTile"):
			var index = int(name.trim_prefix("DessertTile"))
			var tile = AtlasTexture.new()
			tile.atlas = preload("res://assets/new/Picture_Level26.png")
			# Slice the complete original artwork into the same 4 by 8 puzzle.
			var tile_size = tile.atlas.get_size()/Vector2(4,8)
			tile.region = Rect2(Vector2(index%4,int(index/4))*tile_size,tile_size)
			tile.filter_clip = true
			textures[name] = tile
			return tile
		var path = "res://www/assets/" + name + ".png"
		if not ResourceLoader.exists(path):
			path = "res://assets/new/" + name + ".png"
		textures[name] = load(path)
	return textures[name]

func add_piece(name: String, center: Vector2, size: Vector2, mode: String = "static", angle: float = 0.0) -> Dictionary:
	var p = {"name":name,"home":center,"pos":center,"target":center,"size":size,
		"angle":angle,"goal":angle,"rotation_target":angle,"mode":mode,"faults":0,"step":90.0}
	pieces.append(p)
	return p

func art(name: String, x: float, y: float, w: float, h: float, mode: String = "static") -> Dictionary:
	return add_piece(name, Vector2(x+w/2,y+h/2), Vector2(w,h), mode)

func set_drawer_depth(p: Dictionary, depth: int) -> void:
	p.depth = depth
	p.name = "Drawer%d_Level25" % (depth+1)
	p.size = Vector2(950+depth*30,550+depth*70)
	# Keep the back edge in its cabinet opening as the front projects outward.
	p.target = p.home+Vector2(0,depth*35)
	p.pos = p.target
	p.faults = depth

func drawing_order() -> Array:
	var indices = range(pieces.size())
	if not pieces.is_empty() and pieces[0].get("stack",false):
		# Render from the bottom of the stack upward, even during insertion drags.
		indices.sort_custom(func(a, b): return pieces[a].pos.y > pieces[b].pos.y)
	elif level == 25:
		# Draw the cabinet first, then drawers from bottom to top. An open
		# upper drawer projects in front of the row below, not behind it.
		indices.sort_custom(func(a, b):
			var first_drawer: bool = pieces[a].mode == "close"
			var second_drawer: bool = pieces[b].mode == "close"
			if first_drawer != second_drawer: return not first_drawer
			if first_drawer and pieces[a].home.y != pieces[b].home.y:
				return pieces[a].home.y > pieces[b].home.y
			return a < b)
	return indices

func stack_hit(p: Dictionary, point: Vector2) -> bool:
	var local: Vector2 = (point-p.pos).rotated(-deg_to_rad(p.angle))
	var uv: Vector2 = local/p.size+Vector2(0.5,0.5)
	if uv.x < 0 or uv.y < 0 or uv.x >= 1 or uv.y >= 1: return false
	if not hit_images.has(p.name):
		var img = tex(p.name).get_image()
		if img.is_compressed(): img.decompress()
		hit_images[p.name] = img
	var img: Image = hit_images[p.name]
	return img.get_pixel(int(uv.x*img.get_width()),int(uv.y*img.get_height())).a > 0.1

func disturb(count: int = 0) -> void:
	var candidates: Array[int] = []
	for i in pieces.size():
		if pieces[i].mode != "static": candidates.append(i)
	candidates.shuffle()
	var budget = 1 if candidates.size() <= 3 else randi_range(1,2)
	var total = mini(count if count > 0 else budget, candidates.size())
	for i in total:
		var p = pieces[candidates[i]]
		p.faults = 1
		if p.mode == "rotate":
			p.rotation_target = p.goal - p.step
			p.angle = p.rotation_target
		else:
			# Keep small-object faults visible at the 500-pixel viewport width.
			var offset = clampf(p.size.x*0.35,110.0,220.0)*randf_range(0.9,1.1)
			if level == 11: offset = randf_range(100,135)
			p.target = p.home + Vector2(offset * [-1,1].pick_random(),0)
			p.pos = p.target

func start_round(id: int = -1) -> void:
	# Legacy practice shortcuts cannot reopen the removed size-ordering puzzle.
	if id >= 0 and id not in LEVELS: id = 3 if id == 103 else LEVELS[0]
	if id < 0:
		var choices = LEVELS.duplicate()
		choices.erase(level)
		id = choices.pick_random()
	level = id
	interaction.reset()
	pieces.clear()
	background = "Background_Level%d" % level
	remaining = 5.0
	phase = 0.0
	state = "play"
	paused = false
	match level:
		1:
			prompt = "TIDY UP!"
			art("Fireplace_Level1",400,2409,1701,1401,"move")
			var p = art("Picture_Level1",400,704,1701,1001,"move")
			disturb()
			if p.faults > 0 and randf() < 0.5:
				p.angle = -4.0
				p.rotation_target = -4.0
				p.faults += 1
		4:
			prompt = "CENTRE!"
			for y in [1919,2475,3033]: add_piece("Window_Level4",Vector2(1250.5,y),Vector2(233,274),"move")
			disturb()
		8:
			prompt = "HANDLES!"
			var n = randi_range(2,4)
			var top = 4300-(n-1)*595-868
			for i in n:
				art("Drawer_Bottom_Level8" if i == n-1 else "Drawer_Level8",420.5,top+i*595,1660,868 if i == n-1 else 595)
			for i in n: add_piece("Handle_Level8",Vector2(1250,top+i*595+365.5),Vector2(150,150),"move")
			disturb()
		13:
			prompt = "ALIGN!"
			var n = randi_range(2,5)
			var shrink = minf(1.0,3046.0/((n-1)*670+741))
			for i in n:
				var top = i == n-1
				var y = 3346-(i+1)*670 if not top else 3346-(n-1)*670-741
				art("Floor_Top_Level13" if top else "Floor_Level13",243 if top else 300,y,2015 if top else 1901,741 if top else 670)
				for x in [775.25,1725.75]: add_piece("Window_Level13",Vector2(x,y+(424.5 if top else 357.5)),Vector2(301,401),"move")
			for p in pieces:
				p.home = Vector2(1250.5,3346)+(p.home-Vector2(1250.5,3346))*shrink
				p.pos = p.home
				p.target = p.home
				p.size *= shrink
			disturb()
		14,114:
			prompt = "ROTATE!"
			background = ""
			build_tiles(level == 114)
			disturb()
		16:
			prompt = "TURN!"
			var p = add_piece("Manhole_Level16",SIZE/2,Vector2(1201,1201),"rotate")
			p.step = 15.0
			disturb()
			p.faults = randi_range(1,3)
			p.rotation_target = -15.0*p.faults
			p.angle = p.rotation_target
		18:
			prompt = "FLIP!"
			var cols = randi_range(2,3)
			var rows = randi_range(3,6)
			var cw = 2015.0/cols
			var pw = minf(cw*0.82,(3000.0/rows)*0.62*571/271)
			var ph = pw*271/571
			var pitch = minf(3000.0/rows,ph*2.15)
			for r in rows:
				for c in cols:
					var p = add_piece("Pill_Level18",Vector2(251+(c+0.5)*cw,2500+(r-(rows-1)/2.0)*pitch),Vector2(pw,ph),"rotate")
					p.step = 180.0
			disturb()
		_:
			ExtraLevels.build(self, level)
	if not testing: Telemetry.start_round(level, practice, fault_count())
	queue_redraw()

const PAIRS = [["salmon","green"],["orange","green"],["orange","teal"],["green","pink"],["green","red"],["teal","red"],["pink","blue"],["red","blue"],["red","lgreen"],["blue","coral"],["blue","yellow"],["lgreen","yellow"],["coral","grey"],["yellow","grey"],["yellow","peri"]]
func edges(t: int, k: int) -> Array:
	var pair = PAIRS[t-1]
	var base = [pair[0],pair[1],pair[1],pair[0]] if t%2 else [pair[0],pair[0],pair[1],pair[1]]
	var result = []
	for i in 4: result.append(base[posmod(i-k,4)])
	return result

func build_tiles(circles: bool) -> void:
	if not circles:
		var solution: Array = []
		var budget = [40000]
		if solve_ribbons(solution,budget):
			for i in solution.size():
				var item: Array = solution[i]
				add_piece("Tile%d_Level14" % item[0],Vector2((i%4+0.5)*SIZE.x/4,(int(i/4)+0.5)*SIZE.y/8),Vector2(625.2,625.2),"rotate",item[1]*90.0)
		else: build_tile_fallback()
		return
	var grid: Array = []
	var cycle: Array = [["green","orange","teal","red"],["green","pink","blue","red"],["red","blue","yellow","lgreen"],["blue","coral","grey","yellow"]].pick_random()
	for r in 8:
		for c in 4:
			var options: Array = []
			for t in range(1,16):
				for k in 4:
					var e = edges(t,k)
					if circles:
						var a = cycle[c%4]
						var b = cycle[(c+1)%4]
						if (c+r)%2 == 0:
							if e != [a,b,b,a]: continue
						elif e != [b,b,a,a]: continue
					else:
						if c > 0 and e[3] != grid.back()[1]: continue
						if r > 0 and e[0] != grid[(r-1)*4+c][2]: continue
					options.append([t,k,e])
			if options.is_empty():
				# Restart the small grid if this random colour walk dead-ends.
				pieces.clear()
				build_tile_fallback()
				return
			var chosen: Array = options.pick_random()
			grid.append(chosen[2])
			add_piece("Tile%d_Level14" % chosen[0],Vector2((c+0.5)*SIZE.x/4,(r+0.5)*SIZE.y/8),Vector2(625.2,625.2),"rotate",chosen[1]*90.0)

func build_tile_fallback() -> void:
	var t = randi_range(1,15)
	for r in 8:
		for c in 4:
			var k = (c%2 if r%2 == 0 else 3-c%2)
			# Even-numbered source tiles already carry a 90-degree turn.
			if t%2 == 0: k = posmod(k-1,4)
			add_piece("Tile%d_Level14" % t,Vector2((c+0.5)*SIZE.x/4,(r+0.5)*SIZE.y/8),Vector2(625.2,625.2),"rotate",k*90.0)

func solve_ribbons(grid: Array, budget: Array) -> bool:
	if grid.size() == 32: return true
	budget[0] -= 1
	if budget[0] <= 0: return false
	var col = grid.size()%4
	var row = int(grid.size()/4)
	var candidates: Array = []
	for t in range(1,16):
		for k in 4:
			var e = edges(t,k)
			if col > 0 and e[3] != grid.back()[2][1]: continue
			if row > 0 and e[0] != grid[grid.size()-4][2][2]: continue
			candidates.append([t,k,e])
	candidates.shuffle()
	for candidate in candidates:
		grid.append(candidate)
		if solve_ribbons(grid,budget): return true
		grid.pop_back()
		if budget[0] <= 0: return false
	return false

func tap(point: Vector2) -> void:
	if ads != null and ads.busy: return
	if state == "usage":
		if Rect2(350,3400,1800,450).has_point(point):
			Telemetry.set_collection(not Telemetry.collecting())
		elif point.y > 4100: state = "splash"
		queue_redraw()
		return
	if state == "splash":
		if Rect2(50,4800,1125,200).has_point(point):
			state = "usage"
		elif ads != null and ads.privacy_required() and Rect2(1250,4800,1200,200).has_point(point):
			ads.show_privacy()
		elif Rect2(650,3190,1200,650).has_point(point):
			practice = false
			score = 0
			start_round()
		elif Rect2(650,4230,1200,400).has_point(point): state = "select"
		else: splash_angle = -splash_angle*1.1
		return
	if state == "select":
		for i in LEVELS.size():
			if level_button_rect(i).has_point(point):
				practice = true
				start_round(LEVELS[i])
				break
		return
	if point.y < 310 and point.x > 2090:
		interaction.cancel()
		paused = not paused
		return
	if paused:
		if point.y > 2600:
			if not testing: Telemetry.finish_round("abandoned")
			state = "splash"
			paused = false
		return
	if state != "play": return
	# Tap actions resolve immediately; drag actions are counted on release.
	var correct = _tap_puzzle(point)
	if not testing:
		# _tap_puzzle defers finish so the winning action is included.
		Telemetry.action(correct)
	if solved(): finish(true)

func fault_count() -> int:
	var count = 0
	for p in pieces: count += maxi(0, p.faults)
	return count

func _tap_puzzle(point: Vector2) -> bool:
	var before = fault_count()
	if interaction.tap_hex(point): return fault_count() < before
	var front_to_back = drawing_order()
	front_to_back.reverse()
	for i in front_to_back:
		var p = pieces[i]
		if not p.mode in ["move","rotate","face","mirror","close"]: continue
		if p.mode == "close":
			if not stack_hit(p,point): continue
			if p.faults <= 0: return false
		elif p.get("stack",false):
			if not stack_hit(p,point): continue
			# A correctly placed visible surface blocks taps on plates below it.
			if p.faults <= 0: return false
		else:
			if p.mode == "move" and p.faults <= 0: continue
			var local = (point-p.pos).rotated(-deg_to_rad(p.angle))
			var margin = minf(65.0,p.size.x*0.15) if not level in [12,14,114,17,19,21] else 0.0
			if not Rect2(-p.size/2-Vector2.ONE*margin,p.size+Vector2.ONE*margin*2).has_point(local): continue
		var had_fault = p.faults > 0
		if p.has("arch_row"):
			for section in pieces:
				if section.get("arch_row",-1) == p.arch_row:
					section.target = section.home
					section.faults = 0
		elif p.mode == "close":
			set_drawer_depth(p,maxi(0,p.depth-1))
		elif p.mode == "mirror":
			p.flip_h = false
			p.faults = 0
		elif p.mode == "face":
			p.name = p.correct_name
			p.faults = 0
		elif p.mode == "rotate":
			p.rotation_target += p.step
			p.faults = 0 if is_zero_approx(fposmod(p.rotation_target-p.goal,360.0)) else 1
		else:
			if p.target != p.home:
				p.target = p.home
				p.faults -= 1
			elif p.rotation_target != p.goal:
				p.rotation_target = p.goal
				p.faults -= 1
		# Intermediate rotation steps are useful actions even before the final angle.
		return had_fault
	return false

func solved() -> bool:
	for p in pieces:
		if p.faults > 0: return false
	return true

func finish(won: bool) -> void:
	if state != "play": return
	if not testing: Telemetry.finish_round("win" if won else "timeout")
	if ads != null and not testing: ads.complete_round(practice)
	interaction.cancel()
	state = "win" if won else "lose"
	phase = 1.1 if won else 0.5
	if won:
		score += 1
		if score > best and not testing:
			best = score
			var save = ConfigFile.new()
			save.set_value("game","best",best)
			save.save("user://progress.cfg")
	else: score = 0

func _input(event: InputEvent) -> void:
	if not app_foreground or state == "ad" or (ads != null and ads.busy): return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		interaction.cancel()
		if state in ["select", "usage"]: state = "splash"
		elif state != "splash": paused = not paused
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: interaction.pointer_down(event.position/scale,-1)
		else: interaction.pointer_up(event.position/scale,-1)
	elif event is InputEventMouseMotion:
		interaction.pointer_move(event.position/scale,-1)
	elif event is InputEventScreenTouch:
		if event.canceled and event.index == interaction.owner: interaction.cancel()
		elif event.pressed: interaction.pointer_down(event.position/scale,event.index)
		else: interaction.pointer_up(event.position/scale,event.index)
	elif event is InputEventScreenDrag:
		interaction.pointer_move(event.position/scale,event.index)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_APPLICATION_FOCUS_OUT]:
		app_foreground = false
		Telemetry.background()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		app_foreground = true
		Telemetry.foreground()
	if interaction == null: return
	if not app_foreground:
		interaction.cancel()
		if state in ["play","win","lose"] and not (ads != null and ads.busy): paused = true
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back_request()

func _handle_back_request(now: int = Time.get_ticks_msec()) -> void:
	# Godot 4.7 / Android target SDK 36 can deliver one Back press twice.
	# Coalesce the key and dispatcher paths before either changes navigation.
	if now - last_back_request_ms < 250: return
	last_back_request_ms = now
	if state == "ad" or (ads != null and ads.busy): return
	interaction.cancel()
	if state in ["select", "usage"]: state = "splash"
	elif state != "splash": paused = not paused
	else: get_tree().quit()

func _advance_after_result() -> void:
	state = "ad"
	if ads != null and ads.between_rounds(practice): return
	start_round(level if practice else -1)

func _on_ad_break_finished() -> void:
	if state == "ad": resume_after_ad = true

func _process(dt: float) -> void:
	if not app_foreground: return
	if not testing:
		var playing = state == "play" and not paused and not (ads != null and ads.busy)
		Telemetry.tick(dt, minf(dt,remaining) if playing else 0.0)
	if ads != null:
		if state == "splash": ads.show_menu_consent()
		if ads.busy: return
	if resume_after_ad:
		resume_after_ad = false
		start_round(level if practice else -1)
		queue_redraw()
		return
	if paused:
		queue_redraw()
		return
	elapsed += dt
	for i in pieces.size():
		var p = pieces[i]
		if i != interaction.held: p.pos = p.pos.lerp(p.target,1.0-exp(-8.0*dt))
		p.angle = lerpf(p.angle,p.rotation_target,1.0-exp(-8.0*dt))
	if state == "play":
		if ads != null: ads.tick_gameplay(minf(dt,remaining),practice)
		remaining = maxf(0,remaining-dt)
		if remaining == 0: finish(false)
	elif state in ["win","lose"]:
		phase -= dt
		if phase <= 0: _advance_after_result()
	queue_redraw()

func label(value: String, y: float, size_px: int = 160, color: Color = CREAM) -> void:
	var width = font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x
	if width > SIZE.x-120:
		size_px = int(size_px*(SIZE.x-120)/width)
		width = font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x
	var at = Vector2((SIZE.x-width)/2,y)
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,color)

func picture(name: String, rect: Rect2) -> void:
	# Replace baked-in numerals so the elevator uses the same bundled font.
	var number = name.trim_prefix("Button").trim_suffix("_Level2")
	if name.begins_with("Button") and name.ends_with("_Level2") and number.is_valid_int():
		var center = rect.get_center()
		var radius = minf(rect.size.x,rect.size.y)/2
		draw_circle(center,radius,YELLOW)
		draw_circle(center,radius*0.92,Color.WHITE)
		draw_circle(center,radius*0.82,Color("252725"))
		text_in_box(number,rect,int(rect.size.y*0.67),Color.WHITE)
		return
	draw_texture_rect(tex(name),rect,false)

func text_in_box(value: String, rect: Rect2, size_px: int, color: Color) -> void:
	var width = font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x
	if width > rect.size.x*0.85:
		size_px = int(size_px*rect.size.x*0.85/width)
		width = font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x
	var baseline = rect.get_center().y+(font.get_ascent(size_px)-font.get_descent(size_px))/2
	draw_string(font,Vector2(rect.get_center().x-width/2,baseline),value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,color)

func caption(value: String, center_y: float, size_px: int, color: Color) -> void:
	# An opaque warm-ivory surface keeps Cooper readable on every scene, without
	# font outlines, neon colors, or guessing the colors behind each glyph.
	var width = minf(SIZE.x-180,font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x+160)
	var height = font.get_height(size_px)+80
	var rect = Rect2((SIZE.x-width)/2,center_y-height/2,width,height)
	var style = StyleBoxFlat.new()
	style.bg_color = CREAM
	style.set_corner_radius_all(55)
	draw_style_box(style,rect)
	text_in_box(value,rect,size_px,color)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,SIZE),CREAM)
	if state == "usage":
		label("USAGE DATA",650,220,TEAL)
		label("Help improve the puzzles",1200,130,TEAL)
		label("Share level results, play time",1580,115,TEAL)
		label("and ad activity with VD Solution.",1770,110,TEAL)
		label("Uses a random installation ID.",2080,110,TEAL)
		label("No name, email or advertising ID.",2270,105,TEAL)
		label("Optional. Off clears unsent data;",2580,110,TEAL)
		label("data already sent stays on the server.",2770,100,TEAL)
		label("Event data is kept for 90 days.",3040,105,TEAL)
		var button = Rect2(350,3400,1800,450)
		draw_style_box(menu_style(),button)
		var title = ("Turn off" if Telemetry.collecting() else "Allow usage data") if Telemetry.available else "Unavailable in this build"
		text_in_box(title,button,125,CREAM)
		label("Back",4400,150,TEAL)
		return
	if state == "splash":
		picture("Background_Splash_Screen",Rect2(Vector2.ZERO,SIZE))
		draw_set_transform(Vector2(1250.5,995.3),splash_angle+sin(elapsed*1.6)*0.008)
		picture("Picture_Splash_Screen",Rect2(-780.5,-175.3,1561,1753))
		draw_set_transform(Vector2.ZERO)
		label("PUT IT BACK",520,240,TEAL)
		var play_rect = Rect2(740.5,3229,1020,442)
		var play_style = StyleBoxFlat.new()
		play_style.bg_color = CREAM
		play_style.border_color = TEAL
		play_style.set_border_width_all(18)
		play_style.set_corner_radius_all(210)
		draw_style_box(play_style,play_rect)
		text_in_box("Play",play_rect,270,TEAL)
		label("5 SECONDS. FIX THE SCENE.",4050,110,TEAL)
		label("CHOOSE LEVEL",4490,135,TEAL)
		label("BEST STREAK  %d" % best,4720,90,TEAL)
		text_in_box("Usage data: " + ("on" if Telemetry.collecting() else "off"),Rect2(50,4800,1125,200),90,TEAL)
		if ads != null and ads.privacy_required(): text_in_box("Ad privacy",Rect2(1250,4800,1200,200),90,TEAL)
		return
	if state == "select":
		draw_rect(Rect2(Vector2.ZERO,SIZE),INK)
		label("CHOOSE LEVEL",370,200,CREAM)
		for i in LEVELS.size():
			var box = level_button_rect(i)
			draw_style_box(menu_style(),box)
			var title = "%s  %s" % [(str(LEVELS[i]-100)+"b") if LEVELS[i] >= 100 else str(LEVELS[i]),NAMES[LEVELS[i]]]
			var title_size = mini(100,int(100*1010.0/font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,100).x))
			text_in_box(title,box,title_size,CREAM)
		label("Esc / Back to return",4800,90)
		return
	if background != "": picture(background,Rect2(Vector2.ZERO,SIZE))
	for i in drawing_order():
		if i == interaction.held: continue
		var p = pieces[i]
		draw_set_transform(p.pos,deg_to_rad(p.angle),Vector2(-1 if p.get("flip_h",false) else 1,1))
		picture(p.name,Rect2(-p.size/2,p.size))
	draw_set_transform(Vector2.ZERO)
	interaction.draw_drag()
	draw_rect(Rect2(0,0,SIZE.x,120),INK)
	draw_rect(Rect2(25,25,(SIZE.x-50)*remaining/5.0,65),PINK if remaining < 1.7 else CREAM)
	var pause_style = StyleBoxFlat.new()
	pause_style.bg_color = CREAM
	pause_style.set_corner_radius_all(35)
	draw_style_box(pause_style,Rect2(2140,140,250,150))
	text_in_box("II",Rect2(2140,140,250,150),105,TEAL)
	if state == "play" and remaining > 4.15: caption(prompt,430,145,TEAL)
	if state == "win": caption("GREAT!",2500,300,SUCCESS)
	if state == "lose":
		draw_rect(Rect2(Vector2.ZERO,SIZE),Color(0,0,0,0.25))
		caption("TRY AGAIN!",2500,240,RETRY)
	if paused:
		draw_rect(Rect2(Vector2.ZERO,SIZE),Color(0.1,0.12,0.17,0.88))
		label("PAUSED",2300,300,CREAM)
		label("Tap II to resume",2550,120)
		label("Tap below for menu",2900,120)

func level_button_rect(index: int) -> Rect2:
	var rows = ceili(LEVELS.size()/2.0)
	var pitch = minf(330.0,4080.0/rows)
	return Rect2(100+(index%2)*1150,600+int(index/2)*pitch,1100,pitch-35)

func menu_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color("485467")
	style.set_corner_radius_all(40)
	return style

func self_test() -> void:
	if not await preload("res://scripts/ads/ad_tests.gd").new().run(self):
		get_tree().quit(1)
		return
	if not preload("res://scripts/aesthetic_tests.gd").new().run(self):
		get_tree().quit(1)
		return
	if not preload("res://scripts/new_levels_tests.gd").new().run(self):
		get_tree().quit(1)
		return
	# Exercise real hit testing and completion for every generated puzzle.
	for id in LEVELS:
		for repetition in 20:
			seed(1000+id*100+repetition)
			start_round(id)
			if solved():
				push_error("Round starts solved: %d" % id)
				get_tree().quit(1)
				return
			if id in [5,10,19,22,23,24,26]:
				var suite = PuzzleTests.new(self,repetition%2 == 0)
				if not suite.run_round(id):
					get_tree().quit(1)
					return
				continue
			if id in [3,20,120]:
				var suite = StackTests.new(self,repetition%2 == 0)
				if not suite.run_round(id):
					get_tree().quit(1)
					return
				continue
			for p in pieces:
				assert(tex(p.name) != null)
				var attempts = 0
				while p.faults > 0 and attempts < 24:
					tap(p.pos)
					attempts += 1
			if not solved() or state != "win":
				push_error("Unsolvable level: %d" % id)
				get_tree().quit(1)
				return
		start_round(id)
		_process(5.01)
		assert(state == "lose")
	print("SELF TEST PASSED: %d levels, 20 randomized solves each, all timeouts; mouse/touch ordering, placement, swaps, subtle imperfections, cookie facing, horizontal stack faults, invalid drops, cancellation, and pointer ownership" % LEVELS.size())
	get_tree().quit()

func capture_gallery() -> void:
	DirAccess.make_dir_recursive_absolute("res://verification")
	for id in [0] + LEVELS:
		if id == 0: state = "splash"
		else: start_round(id)
		set_process(false)
		queue_redraw()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://verification/level_%d.png" % id)
	for id in [5,10,22,23,24,26]:
		start_round(id)
		remaining = 4.0
		for p in pieces:
			if p.faults <= 0: continue
			interaction.pointer_down(p.pos,-1)
			interaction.pointer_move(p.pos+Vector2(120,80),-1)
			break
		queue_redraw()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://verification/drag_%d.png" % id)
	for id in [2,10,11,15,19,21,23,24,25,26]:
		start_round(id)
		remaining = 4.0
		for p in pieces:
			if p.mode == "close": set_drawer_depth(p,0)
			if p.has("correct_name"): p.name = p.correct_name
			p.pos = p.home
			p.target = p.home
			p.angle = p.goal
			p.rotation_target = p.goal
			p.flip_h = false
			p.faults = 0
		queue_redraw()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://verification/solved_%d.png" % id)
	state = "select"
	queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://verification/level_select.png")
	print("GALLERY CAPTURED")
	get_tree().quit()
