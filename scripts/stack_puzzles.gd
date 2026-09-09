extends RefCounted
## Plate and cookie stacks share artwork-space geometry and visible-surface input.
static func build(g, id: int) -> void:
	var plates = id == 3
	g.background = "Background_Level3" if plates else "Background_Level20"
	g.prompt = "CENTRE THE PLATES!" if plates else ("FACE LEFT!" if id == 20 else "CENTRE THE COOKIES!")
	for i in 5:
		var center = Vector2(1250.5,3500-i*(165 if plates else 230))
		var size = Vector2(1600,440) if plates else Vector2(1108,468)
		var p = g.add_piece("Plate_Level3" if plates else "Bar1_Level20",center,size,"face" if id == 20 else "move")
		p.stack = true
		p.correct_name = p.name
	var indices = range(5)
	indices.shuffle()
	for n in randi_range(1,3 if plates else 2):
		var p = g.pieces[indices[n]]
		p.faults = 1
		if id == 20:
			p.name = "Bar2_Level20"
		else:
			var magnitude = randf_range(70,115) if plates else randf_range(65,105)
			p.target.x += magnitude*[-1,1].pick_random()
			p.pos = p.target
