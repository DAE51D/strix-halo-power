#!/usr/bin/env bash
# pmode-bench — verify the APU power modes actually change performance.
#
# Two complementary tests:
#   1. CPU envelope: pin all cores, sample sustained frequency + package power
#      per mode. Shows the raw power/freq budget each mode allows.
#   2. LLM throughput: llama-bench (prompt processing + token generation) per
#      mode, on a small GGUF model. Shows the real-world effect on inference.
#
# Usage:
#   ./pmode-bench.sh                 # both tests, all three modes
#   ./pmode-bench.sh --cpu           # CPU envelope test only
#   ./pmode-bench.sh --llm           # LLM throughput test only
#   MODEL=/path/to/model.gguf ./pmode-bench.sh --llm
#
# Requires: gdbus, llama-bench (Vulkan build), a GGUF model, and the
# com.evox2.powermode D-Bus service running.

set -euo pipefail

MODES=(quiet balanced performance)
LLAMA_BENCH="${LLAMA_BENCH:-/opt/llama-cpp-vulkan/bin/llama-bench}"
MODEL="${MODEL:-/mnt/DATA/models/gguf/gemma-4-12b/gemma-4-12B-it-Q4_K_M.gguf}"
SAMPLES=6

DO_CPU=0
DO_LLM=0
for arg in "$@"; do
	case "$arg" in
	--cpu) DO_CPU=1 ;;
	--llm) DO_LLM=1 ;;
	-h | --help)
		grep '^#' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		echo "unknown arg: $arg (try --cpu, --llm, --help)" >&2
		exit 2
		;;
	esac
done
[ "$DO_CPU" -eq 0 ] && [ "$DO_LLM" -eq 0 ] && {
	DO_CPU=1
	DO_LLM=1
}

set_mode() {
	gdbus call --session --dest com.evox2.powermode --object-path /com/evox2/powermode \
		--method com.evox2.powermode.SetMode "$1" >/dev/null 2>&1
	sleep 3 # let the mode + governor settle
}

# ---------------------------------------------------------------------------
# Test 1: CPU envelope (freq + package power under a 16-core load)
# ---------------------------------------------------------------------------
run_cpu() {
	local load_pids=""
	cleanup() {
		[ -n "$load_pids" ] && kill $load_pids 2>/dev/null
		wait 2>/dev/null || true
	}
	trap cleanup RETURN

	echo
	echo "=== CPU envelope (all cores pinned, ${SAMPLES}s sample per mode) ==="
	printf "%-14s %14s %14s\n" "mode" "avg_freq_MHz" "pkg_power_W"
	for mode in "${MODES[@]}"; do
		set_mode "$mode"
		local i
		for i in $(seq 1 16); do (while :; do :; done) & done
		load_pids=$(jobs -p | tr '\n' ' ')
		sleep 1
		local fsum=0 psum=0
		for i in $(seq 1 "$SAMPLES"); do
			local fsum_c=0 n=0
			for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq; do
				[ -f "$f" ] || continue
				fsum_c=$((fsum_c + $(cat "$f")))
				n=$((n + 1))
			done
			[ "$n" -gt 0 ] && fsum=$((fsum + fsum_c / n / 1000))
			local pw
			for p in /sys/class/hwmon/hwmon*/power1_average; do
				[ -f "$p" ] && {
					pw=$(($(cat "$p") / 1000000))
					break
				}
			done
			[ -n "${pw:-}" ] && psum=$((psum + pw))
			sleep 1
		done
		kill $load_pids 2>/dev/null
		wait 2>/dev/null || true
		load_pids=""
		printf "%-14s %14s %14s\n" "$mode" "$((fsum / SAMPLES))" "$((psum / SAMPLES))W"
		sleep 1
	done
}

# ---------------------------------------------------------------------------
# Test 2: LLM throughput (llama-bench, prompt processing + token generation)
# ---------------------------------------------------------------------------
run_llm() {
	if [ ! -x "$LLAMA_BENCH" ]; then
		echo "llama-bench not found at $LLAMA_BENCH (set LLAMA_BENCH=...)" >&2
		return 1
	fi
	if [ ! -f "$MODEL" ]; then
		echo "model not found: $MODEL (set MODEL=...)" >&2
		return 1
	fi
	echo
	echo "=== LLM throughput (llama-bench, pp512 + tg128, 3 runs) ==="
	echo "model: $MODEL"
	for mode in "${MODES[@]}"; do
		set_mode "$mode"
		echo "--- $mode ---"
		"$LLAMA_BENCH" -m "$MODEL" -p 512 -n 128 -r 3 2>&1 | grep -E 'pp512|tg128' ||
			echo "  (no output — did the model load?)"
		sleep 1
	done
}

[ "$DO_CPU" -eq 1 ] && run_cpu
[ "$DO_LLM" -eq 1 ] && run_llm

# leave the system in performance mode (the usual working default)
set_mode performance
echo
echo "(restored to performance mode)"
