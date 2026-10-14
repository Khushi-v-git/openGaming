extends GutTest


func test_create_gives_stable_ids_and_secret_tokens() -> void:
	var reg: PlayerRegistry = PlayerRegistry.new()
	var a: Dictionary = reg.create("A")
	var b: Dictionary = reg.create("B")
	assert_eq(a["player_id"], "p1")
	assert_eq(b["player_id"], "p2")
	assert_ne(a["token"], b["token"])
	assert_eq(str(a["token"]).length(), 32)


func test_bind_and_unbind_peer() -> void:
	var reg: PlayerRegistry = PlayerRegistry.new()
	reg.create("A")
	reg.bind_peer("p1", 7)
	assert_eq(reg.player_of_peer(7), "p1")
	assert_eq(reg.peer_of("p1"), 7)
	assert_true(reg.is_connected_player("p1"))
	assert_eq(reg.unbind_peer(7), "p1")
	assert_eq(reg.peer_of("p1"), 0)
	assert_eq(reg.player_of_peer(7), "")
	assert_eq(reg.unbind_peer(7), "")


func test_verify_token() -> void:
	var reg: PlayerRegistry = PlayerRegistry.new()
	var a: Dictionary = reg.create("A")
	assert_true(reg.verify_token("p1", a["token"]))
	assert_false(reg.verify_token("p1", "wrong"))
	assert_false(reg.verify_token("p1", ""))
	assert_false(reg.verify_token("nobody", a["token"]))


func test_rotate_token_invalidates_the_old_one() -> void:
	var reg: PlayerRegistry = PlayerRegistry.new()
	var old: String = reg.create("A")["token"]
	var fresh: String = reg.rotate_token("p1")
	assert_ne(old, fresh)
	assert_false(reg.verify_token("p1", old))
	assert_true(reg.verify_token("p1", fresh))
	assert_eq(reg.rotate_token("nobody"), "")


func test_ids_are_not_reused_after_removal() -> void:
	var reg: PlayerRegistry = PlayerRegistry.new()
	reg.create("A")
	reg.remove("p1")
	assert_eq(reg.create("B")["player_id"], "p2")


func test_to_dict_round_trip_keeps_identity_but_not_connections() -> void:
	var reg: PlayerRegistry = PlayerRegistry.new()
	reg.create("A")
	reg.create("B")
	reg.bind_peer("p1", 5)
	var data: Dictionary = Envelope.normalize(JSON.parse_string(JSON.stringify(reg.to_dict())))
	var copy: PlayerRegistry = PlayerRegistry.from_dict(data)
	assert_eq(copy.player_ids(), ["p1", "p2"] as Array[String])
	assert_eq(copy.name_of("p2"), "B")
	assert_true(copy.verify_token("p1", reg.token_of("p1")))
	assert_eq(copy.peer_of("p1"), 0)
	assert_eq(copy.create("C")["player_id"], "p3")


func test_previous_token_stays_valid_until_confirmed() -> void:
	var reg: PlayerRegistry = PlayerRegistry.new()
	var a: String = reg.create("A")["token"]
	var b: String = reg.rotate_token("p1", a)
	assert_true(reg.verify_token("p1", a), "just-replaced token still works")
	assert_true(reg.verify_token("p1", b))
	reg.confirm_token("p1")
	assert_false(reg.verify_token("p1", a))
	assert_true(reg.verify_token("p1", b))


func test_rotate_without_keep_valid_invalidates_immediately() -> void:
	var reg: PlayerRegistry = PlayerRegistry.new()
	var a: String = reg.create("A")["token"]
	reg.rotate_token("p1")
	assert_false(reg.verify_token("p1", a))


func test_saved_registry_does_not_carry_the_previous_token() -> void:
	var reg: PlayerRegistry = PlayerRegistry.new()
	var a: String = reg.create("A")["token"]
	var b: String = reg.rotate_token("p1", a)
	var copy: PlayerRegistry = PlayerRegistry.from_dict(reg.to_dict())
	assert_true(copy.verify_token("p1", b))
	assert_false(copy.verify_token("p1", a))
