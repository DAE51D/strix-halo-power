# Benchmarks — do the power modes actually do something?

Short answer: **yes.** The three modes (`quiet` / `balanced` / `performance`)
set different **power/thermal envelopes** (STAPM/PPT budgets) on the APU. They
do **not** change the cpufreq *cap* (all three allow up to ~5.2 GHz) — they
change how hard the boost algorithm is allowed to push, which shows up as
different sustained frequency and package power **under load**, and different
LLM prompt-processing throughput.

At **idle** all three modes sit at the same low frequency, which is why you
don't see a fan or speed change just sitting at a desktop. The difference only
appears under sustained load.

## How to run it

```bash
./pmode-bench.sh              # both tests, all three modes
./pmode-bench.sh --cpu        # CPU envelope only (fast, ~30s)
./pmode-bench.sh --llm        # LLM throughput only (a few minutes)
MODEL=/path/to/model.gguf ./pmode-bench.sh --llm   # use a different model
```

`pmode-bench.sh` needs `gdbus`, a `llama-bench` Vulkan build (default
`/opt/llama-cpp-vulkan/bin/llama-bench`), a GGUF model (default the 12B Gemma),
and the `com.evox2.powermode` service running. It always restores
`performance` mode when done.

## Test 1 — CPU envelope

Pins all 16 cores to 100% and samples the average frequency and package power
for ~6 s per mode. This is the raw "how hard can it push" number.

**Measured 2026-08-25** (GMKtec EVO-X2, Ryzen AI Max+ 395, Kubuntu 26.04,
kernel 7.0.0-30):

| Mode | Avg freq (MHz) | Package power |
|------|---------------:|--------------:|
| quiet | 3091 | ~58 W |
| balanced | 3976 | ~101 W |
| performance | 4183 | ~128 W |

> The absolute wattage varies with what else is running (a loaded LLM model,
> other services) — the **frequency spread is the reliable signal**. In a
> heavier session (LLM model resident) the same test showed
> quiet 3047 MHz / 343 W, balanced 3814 MHz / 605 W, performance 4146 MHz /
> 769 W. Either way: **performance runs ~36% faster and pulls ~2× the power of
> quiet** under a full-core load.

## Test 2 — LLM throughput

`llama-bench` on a small GGUF model, 3 runs each. Two sub-metrics:

- **pp512** — prompt processing (512 tokens): **CPU-heavy**, pins all cores at
  boost. This is where the power mode matters most.
- **tg128** — token generation (128 tokens): **GPU / memory-bandwidth-bound**
  on this APU (unified memory is the bottleneck), so it's nearly
  mode-insensitive.

**Measured 2026-08-25**, model `gemma-4-12B-it-Q4_K_M.gguf` (6.86 GiB, 11.91 B
params, Vulkan, all layers offloaded):

| Mode | pp512 (t/s) | tg128 (t/s) |
|------|------------:|------------:|
| quiet | 633.4 ± 3.9 | 26.60 ± 0.09 |
| balanced | 729.7 ± 41.9 | 27.49 ± 0.04 |
| performance | **816.6 ± 1.6** | **27.76 ± 0.02** |

**Reading it:**

- **Prompt processing scales a lot** — performance is **~29% faster** than
  quiet (817 vs 633 t/s). Long-context ingestion, RAG, big system prompts, and
  any CPU-bound burst all benefit.
- **Token generation barely moves** — 26.6 → 27.8 t/s (~4%). Decode on this
  box is memory-bandwidth-bound, not CPU-boost-bound, so the power envelope
  doesn't help it much.

## Why you don't notice it in normal use

Your real workload (the 27B model) is dominated by **token generation**
(decode), which is nearly mode-insensitive here. The modes shine on:

- **Prompt processing** — long context, RAG, large system prompts.
- **Genuinely CPU-bound bursts** — builds, compiles, video encoding, the
  16-core pin test above.
- **Thermal / noise budget** — `quiet` keeps the APU cool and silent under
  sustained load at the cost of ~30% less CPU throughput; `performance`
  spends the power budget to stay fast.

## Method notes

- **Why a small model for the LLM test:** the 12B Gemma loads in ~7 s and
  runs pp512 in well under a second, so a full 3-mode sweep finishes in a few
  minutes. The *relative* spread between modes is what matters, and it holds
  regardless of model size — the CPU-heavy pp path is the signal.
- **Settling time:** `pmode-bench.sh` sleeps 3 s after each `SetMode` so the
  governor and power budget settle before sampling.
- **Frequency sampling:** reads `scaling_cur_freq` across all 16 cores and
  averages; package power from the `hwmon` `power1_average` sensor.
- **Reproducibility:** run the sweep back-to-back without changing other load;
  the absolute numbers will move with ambient temperature and what else is on
  the box, but the *ratio* between modes is stable.
