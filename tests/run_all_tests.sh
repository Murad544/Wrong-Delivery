#!/bin/zsh
# Runs every milestone smoke test headlessly with a per-test time limit.
# Usage: ./tests/run_all_tests.sh [path/to/godot]
GODOT_BIN="${1:-/Applications/Godot.app/Contents/MacOS/Godot}"
setopt NO_BG_NICE 2>/dev/null
cd "$(dirname "$0")/.." || exit 1
FAILED=0
for test_file in tests/milestone_*_smoke_test.gd; do
	out_file="/tmp/wd_$(basename "$test_file" .gd).txt"
	"$GODOT_BIN" --headless --log-file /tmp/wd_godot.log --path . -s "res://$test_file" > "$out_file" 2>&1 &
	pid=$!
	waited=0
	while kill -0 $pid 2>/dev/null && [ $waited -lt 50 ]; do
		sleep 0.5
		waited=$((waited + 1))
	done
	if kill -0 $pid 2>/dev/null; then
		kill -9 $pid 2>/dev/null
		echo "[TIMEOUT] $test_file"
		FAILED=1
	fi
	wait $pid 2>/dev/null
	code=$?
	grep -E "\[PASS\]|\[FAIL\]|SCRIPT ERROR|Parse Error|at: " "$out_file" | head -20
	if [ $code -ne 0 ]; then
		FAILED=1
	fi
done
exit $FAILED
