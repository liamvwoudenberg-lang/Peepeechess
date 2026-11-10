extends RefCounted
## Minimal assertion harness (no addons). Failures are recorded and the run continues so one
## broken rule does not hide others; the process exit code reflects the total.

var passed: int = 0
var failed: int = 0
var tests_run: int = 0
var current: String = ""
var failures: Array[String] = []


func begin(test_name: String) -> void:
	current = test_name
	tests_run += 1


func check(condition: bool, message: String) -> bool:
	if condition:
		passed += 1
	else:
		failed += 1
		failures.append("%s: %s" % [current, message])
		printerr("  FAIL [%s] %s" % [current, message])
	return condition


func eq(actual: Variant, expected: Variant, message: String) -> bool:
	return check(typeof(actual) == typeof(expected) and actual == expected \
			or (actual is float or actual is int) and (expected is float or expected is int) and is_equal_approx(float(actual), float(expected)),
			"%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func near(actual: float, expected: float, tolerance: float, message: String) -> bool:
	return check(absf(actual - expected) <= tolerance,
			"%s (expected %s +/- %s, got %s)" % [message, str(expected), str(tolerance), str(actual)])


func report() -> int:
	print("")
	if failed == 0:
		print("PASS: %d checks across %d tests" % [passed, tests_run])
		return 0
	printerr("FAILED: %d of %d checks failed across %d tests" % [failed, passed + failed, tests_run])
	for line in failures:
		printerr("  - " + line)
	return 1
