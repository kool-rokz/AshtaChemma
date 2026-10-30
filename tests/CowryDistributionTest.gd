extends SceneTree

## Verifies cowry scoring, that RandomCowryThrower matches Binomial(4, p), and the
## "skill throws" keep rule: its odds, and when it applies at all.
## Run: godot --headless --path . -s res://tests/CowryDistributionTest.gd

const RandomThrower = preload("res://cowry/RandomCowryThrower.gd")
const Thrower = preload("res://cowry/CowryThrower.gd")

const THROWS := 100000
## ~6 standard deviations for the rarest outcome at 100k throws: effectively never flaky.
const TOLERANCE := 0.005

var failures := 0

func _init() -> void:
	_test_scoring()
	_test_distribution(0.5, 12345)
	_test_distribution(0.4, 67890)
	_test_seed_reproducible()
	_test_keep_odds(0.3, true, 4)
	_test_keep_odds(0.15, true, 4)
	_test_keep_odds(0.3, false, 8)
	_test_keep_rules()

	if failures == 0:
		print("✅ COWRY TESTS PASSED")
		quit(0)
	else:
		print("❌ COWRY TESTS FAILED: %d check(s)" % failures)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: ", message)

## All 16 shell combinations map to the expected move.
func _test_scoring() -> void:
	for mask in 16:
		var shells: Array[bool] = []
		for bit in 4:
			shells.append(bool(mask & (1 << bit)))
		var open_up := shells.count(true)
		var expected := 8 if open_up == 0 else open_up
		_check(Thrower.score(shells) == expected, "score(%s) should be %d" % [shells, expected])
	print("scoring: 16 combinations checked")

func _test_distribution(p: float, seed_value: int) -> void:
	var thrower = RandomThrower.new(p, seed_value)
	var counts := {1: 0, 2: 0, 3: 0, 4: 0, 8: 0}
	for i in THROWS:
		counts[Thrower.score(thrower.throw())] += 1

	var line := "p=%.2f:" % p
	for move in counts:
		var open_up: int = 0 if move == 8 else move
		var expected := _binomial(4, open_up, p)
		var observed := float(counts[move]) / THROWS
		line += "  %d→%.4f (exp %.4f)" % [move, observed, expected]
		_check(absf(observed - expected) < TOLERANCE,
			"p=%.2f move %d: observed %.4f expected %.4f" % [p, move, observed, expected])
	print(line)

func _test_seed_reproducible() -> void:
	var a = RandomThrower.new(0.5, 42)
	var b = RandomThrower.new(0.5, 42)
	var same := true
	for i in 1000:
		if a.throw() != b.throw():
			same = false
			break
	_check(same, "same seed should give identical throws")
	print("seed reproducibility: checked")

## A hand of all-open (or all-closed) shells thrown with keep chance `keep`: each shell
## lands as it lay with probability keep + (1 - keep) / 2, so chamma (or ashta) comes
## up (0.5 + keep / 2)^4 of the time: 17.9% at 0.3, 10.9% at 0.15 (6.25% without).
func _test_keep_odds(keep: float, open: bool, move: int) -> void:
	var thrower = RandomThrower.new(0.5, 2024)
	var hand: Array[bool] = [open, open, open, open]
	var hits := 0
	for i in THROWS:
		if Thrower.score(thrower.throw_with_hand(hand, keep)) == move:
			hits += 1
	var expected := pow(0.5 + keep / 2.0, 4)
	var observed := float(hits) / THROWS
	print("keep %.2f, hand all %s: %d→%.4f (exp %.4f)" % [keep, "open" if open else "closed", move, observed, expected])
	_check(absf(observed - expected) < TOLERANCE, "keep %.2f: %d came up %.4f, expected %.4f" % [keep, move, observed, expected])

## Only shaken, non-quick throws keep anything; harder releases keep less; the
## lobby's level sets the most.
func _test_keep_rules() -> void:
	var gm := GameManager.new()
	gm.setup = MatchSetup.make(GameConfig.default_players(2), false, "strong")
	var g := ThrowGesture.new()
	g.quick = false
	g.shaken = 1.0
	g.power = 0.0
	_check(is_equal_approx(gm.keep_chance(g), 0.3), "a gentle shaken throw keeps the full level")
	g.power = 0.5
	_check(is_equal_approx(gm.keep_chance(g), 0.15), "a half-strength release keeps half")
	g.power = 1.0
	_check(gm.keep_chance(g) == 0.0, "a full-strength release keeps nothing")
	g.power = 0.0
	g.shaken = 0.0
	_check(gm.keep_chance(g) == 0.0, "an unshaken throw keeps nothing")
	_check(gm.keep_chance(ThrowGesture.quick_toss()) == 0.0, "a quick toss keeps nothing")
	_check(gm.keep_chance(null) == 0.0, "no gesture keeps nothing")
	gm.setup = MatchSetup.make(GameConfig.default_players(2), false, "off")
	g.shaken = 1.0
	_check(gm.keep_chance(g) == 0.0, "skill throws off keeps nothing")
	gm.setup = MatchSetup.make(GameConfig.default_players(2), false, "cheat")
	_check(gm.keep_chance(g) == 0.0, "an unknown level counts as off")
	gm.free()
	print("keep rules: checked")

func _binomial(n: int, k: int, p: float) -> float:
	var c := 1.0
	for i in k:
		c = c * (n - i) / (i + 1)
	return c * pow(p, k) * pow(1.0 - p, n - k)
