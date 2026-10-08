extends SceneTree
const Store = preload("res://scripts/telemetry/event_store.gd")
const Client = preload("res://scripts/telemetry/telemetry.gd")
const Attempt = preload("res://scripts/telemetry/ad_attempt.gd")
var failures: Array[String] = []
var prefix = "res://verification/telemetry-unit-"
var client

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func event(index: int) -> Dictionary:
	return {"event_id":Client.uuid(),"occurred_at":Time.get_datetime_string_from_system(true)+"Z","payload":{"name":"first_open"},"sequence":index}

func names() -> Array:
	return client.store.events.map(func(item): return item.payload.name)

func _run() -> void:
	for slot in 2: DirAccess.remove_absolute(prefix + str(slot) + ".json")
	var queue = Store.new(prefix)
	queue.enabled = true
	queue.install_id = Client.uuid()
	queue.events = [event(1), event(2), event(3)]
	check(queue.save(),"Initial snapshot saved")
	var original = JSON.stringify(queue.events)
	check(Store.new(prefix).events == Store.parse(original),"Restart preserves exact IDs, timestamps and sequence")
	queue.events.append(event(4))
	check(queue.save(),"Second snapshot saved")
	var corrupt = FileAccess.open(prefix+str(queue.generation%2)+".json",FileAccess.WRITE)
	corrupt.store_string("torn write")
	corrupt.close()
	queue = Store.new(prefix)
	check(queue.events == Store.parse(original),"Torn latest write falls back to valid snapshot")
	var sent = queue.batch()
	check(not queue.acknowledge(sent,{"accepted":[Client.uuid()],"duplicates":[],"rejected":[]}),"Unknown ack ID cannot delete events")
	check(not queue.acknowledge(sent,{"accepted":[sent[0].event_id],"duplicates":[],"rejected":[{"index":1.5,"code":"invalid_event"}]}),"Malformed receipt rejected atomically")
	check(queue.events.size() == 3,"Bad receipt preserves queue")
	queue.events.append(event(4))
	check(queue.acknowledge(sent,{"accepted":[sent[0].event_id],"duplicates":[sent[1].event_id],"rejected":[{"index":2,"code":"timestamp_out_of_range"}]}),"Accepted, duplicate and rejected mapped to sent batch")
	check(queue.events.size() == 1 and queue.events[0].sequence == 4,"Events appended during upload survive acknowledgment")
	queue.events = []
	for i in 600: queue.events.append(event(i))
	queue.prune()
	check(queue.events.size() == 512 and queue.events[0].sequence == 88,"Queue evicts oldest at count limit")
	check(queue.batch().size() == 100,"Batch count capped")
	queue.events[0].occurred_at = "2020-01-01T00:00:00Z"
	queue.prune()
	check(queue.events.size() == 511,"Expired data evicted")
	queue.events = [event(1),event(2),event(3)]
	for item in queue.events: item.payload.large = "x".repeat(130000)
	check(queue.batch().size() == 1,"Batch byte cap measured as encoded JSON")
	for i in 4:
		var item = event(i)
		item.payload.large = "x".repeat(200000)
		queue.events.append(item)
	queue.prune()
	check(queue.events.size() == 2,"Queue byte limit enforced")
	# Test the actual autoload used by the game; the unit-test flag prevents real networking.
	client = root.get_node("Telemetry")
	check(not client.available and client.store == null,"Automated runs cannot inherit player collection")
	client.store = Store.new(prefix+"client-")
	client.store.enabled = false
	client.store.events = []
	client.store.install_id = ""
	client.store.first_open_recorded = false
	client.http = HTTPRequest.new()
	client.add_child(client.http)
	client.available = true
	client.environment = "test"
	client.set_collection(true)
	check(names() == ["first_open","session_started"],"Opt-in records first open and session")
	var install = client.store.install_id
	client._begin_session("launch")
	check(names().count("first_open") == 1 and client.store.install_id == install,"Subsequent launch retains identity without repeated first open")
	client.start_round(23,true,2)
	client._accumulate(0.75,0.5)
	client.action(true)
	client.action(false)
	client.finish_round("win")
	client.finish_round("win")
	var finish = client.store.events.back().payload
	check(finish.name == "round_finished" and finish.actions == 2 and finish.incorrect_actions == 1 and finish.active_seconds == 0.5,"Round aggregates actions and active time once")
	check(names().count("round_finished") == 1,"Duplicate finish suppressed")
	client.checkpoint()
	var activity = client.store.events.back().payload
	check(activity.foreground_seconds == 0.75 and activity.gameplay_seconds == 0.5,"Checkpoint records incremental foreground/gameplay")
	client.checkpoint()
	check(names().count("activity_checkpoint") == 1,"Empty checkpoint suppressed")
	client.start_round(7,true,1)
	client.last_tick = 1000
	client.tick(1.0/120,1.0/120,1008)
	client.tick(1.0/120,1.0/120,1017)
	check(is_equal_approx(client.round_data.active_seconds,0.017),"120 Hz tick quantization does not lose gameplay time")
	client.tick(1.0/120,0.0,1025)
	check(is_equal_approx(client.round_data.active_seconds,0.017),"Paused frame does not add gameplay time")
	client.finish_round("timeout")
	client.checkpoint()
	client.last_tick = Time.get_ticks_msec()
	var attempt = Attempt.new(client,true)
	attempt.event("ad_requested")
	attempt.event("ad_loaded")
	attempt.event("ad_impression")
	attempt.event("ad_impression")
	attempt.paid(123456,"USD",3)
	attempt.paid(123456,"USD",3)
	check(names().count("ad_impression") == 1 and names().count("ad_revenue") == 1,"Repeated SDK impression and paid callbacks do not inflate metrics")
	check(client.store.events.back().payload.value_micros == 123456,"Paid micros preserved exactly")
	var initial_session = client.session_id
	client.background_at = 0
	client.foreground(1800001)
	check(client.session_id != initial_session,"Long background creates resume session")
	client.in_flight = client.store.batch()
	client._completed(HTTPRequest.RESULT_SUCCESS,429,PackedStringArray(["Retry-After: 120"]),PackedByteArray())
	check(client.next_flush >= Time.get_ticks_msec()+119000 and not client.store.events.is_empty(),"429 retains queue and honors Retry-After")
	client.in_flight = client.store.batch()
	client._completed(HTTPRequest.RESULT_SUCCESS,413,PackedStringArray(),PackedByteArray())
	check(client.batch_limit < 100,"413 splits batches")
	client.in_flight = client.store.batch()
	client._completed(HTTPRequest.RESULT_CANT_CONNECT,0,PackedStringArray(),PackedByteArray())
	check(not client.store.events.is_empty(),"Offline failure retains queue")
	client.in_flight = client.store.batch()
	client._completed(HTTPRequest.RESULT_SUCCESS,401,PackedStringArray(),PackedByteArray())
	check(client.suspended,"401 suspends uploads")
	client.set_collection(false)
	check(client.store.events.is_empty() and client.in_flight.is_empty(),"Opt-out clears pending and in-flight data")
	var restored = Store.new(prefix+"client-")
	check(not restored.enabled and restored.events.is_empty(),"Opt-out survives restart")
	for slot in 2:
		var wrapper = JSON.parse_string(FileAccess.get_file_as_string(prefix+"client-"+str(slot)+".json"))
		check(JSON.parse_string(wrapper.data).events.is_empty(),"Opt-out clears both disk snapshots")
	client.set_collection(true)
	attempt.event("ad_closed")
	check("ad_closed" not in names(),"Late callback from earlier consent period suppressed")
	# Exercise actual gameplay hooks, including the last winning tap and drag.
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.best = 2147483647 # Never change the player's progress save during fixtures.
	check(not quit_on_go_back,"Engine must not auto-quit before Android Back navigation")
	for screen in ["select", "usage"]:
		game.state = screen
		game.last_back_request_ms = -1000
		game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		check(game.state == "splash","Android Back returns from " + screen)
		game._handle_back_request(game.last_back_request_ms + 15)
		check(game.state == "splash","Duplicate Android Back must not quit from " + screen)
	game.state = "play"
	game.paused = false
	game._handle_back_request(game.last_back_request_ms + 300)
	game._handle_back_request(game.last_back_request_ms + 15)
	check(game.paused,"Duplicate Android Back must not undo pause")
	game._handle_back_request(game.last_back_request_ms + 300)
	check(not game.paused,"A later Android Back can resume")
	game.start_round(1)
	var p = game.pieces[0]
	game.pieces.clear()
	game.pieces.append(p)
	p.mode = "move"
	p.faults = 1
	p.pos = Vector2(1250,2500)
	p.home = p.pos + Vector2(100,0)
	p.target = p.pos
	p.size = Vector2(500,500)
	game.tap(p.pos)
	check(game.state == "win" and client.store.events.back().payload.actions == 1,"Winning tap included before round finish")
	game.start_round(1)
	p = game.pieces[0]
	game.pieces.clear()
	game.pieces.append(p)
	p.mode = "rotate"
	p.faults = 1
	p.pos = Vector2(1250,2500)
	p.size = Vector2(500,500)
	p.angle = 0
	p.goal = 0
	p.rotation_target = 90
	p.step = 90
	for i in 3: game.tap(p.pos)
	check(game.state == "win" and client.store.events.back().payload.actions == 3 and client.store.events.back().payload.incorrect_actions == 0,"Necessary intermediate rotations are useful actions")
	game.start_round(24)
	var wrong: Array = []
	for i in game.pieces.size():
		if game.pieces[i].faults > 0: wrong.append(i)
	if wrong.size() == 2:
		var from: Vector2 = game.pieces[wrong[0]].pos
		var to: Vector2 = game.pieces[wrong[1]].pos
		game.interaction.pointer_down(from,0)
		game.interaction.pointer_up(to,0)
		check(game.state == "win" and client.store.events.back().payload.actions == 1,"Winning bottle drag counted once")
	else: check(false,"Bottle fixture has two misplaced bottles")
	game.start_round(11)
	game.paused = true
	game.tap(Vector2(1000,3000))
	check(client.store.events.back().payload.outcome == "abandoned","Explicit return to menu records abandonment")
	game.start_round(25)
	game.finish(false)
	check(client.store.events.back().payload.outcome == "timeout","Timeout records finish")
	client.set_collection(false)
	game.free()
	client.available = false
	for suffix in ["", "client-"]:
		for slot in 2: DirAccess.remove_absolute(prefix+suffix+str(slot)+".json")
	if failures.is_empty(): print("TELEMETRY TESTS PASSED")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
