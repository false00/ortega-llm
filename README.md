# Shard

**Run a 27B reasoning model locally. One command. Auto-tuned to your hardware.**

Shard wraps [Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled](https://huggingface.co/mradermacher/Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled-GGUF) with a zero-config launcher that detects your GPU, benchmarks your system, and picks the fastest settings automatically. No YAML files. No guessing `-ngl` values. Just `shard`.

---

### Why Shard?

| | |
|---|---|
| **One-command install** | Downloads llama.cpp + model + creates the `shard` command globally |
| **Auto hardware detection** | Detects your GPU, VRAM, CPU cores, CUDA version |
| **Auto-tuning** | Benchmarks your specific machine and generates optimized profiles |
| **5 built-in profiles** | From fast daily chat (4K context) to deep reasoning (32K context) |
| **OpenAI-compatible API** | Drop-in replacement at `localhost:8080/v1` for any app that speaks OpenAI |
| **Hot profile switching** | Switch context/speed profiles without manual restarts |
| **Works on any NVIDIA GPU** | CUDA auto-detected; CPU fallback if no GPU |

---

## Quick Start

```powershell
# 1. Install (downloads runtime + model, creates global 'shard' command)
.\scripts\install-shard.ps1

# 2. Open a new terminal, then detect your hardware
shard detect

# 3. Auto-tune for your system (benchmarks GPU, finds optimal settings)
shard recalc

# 4. Launch
shard
```

Server is now live at **`http://127.0.0.1:8080/v1`** — compatible with any OpenAI client.

```powershell
shard stop       # stop the server
shard 2          # switch to a different profile
shard ls         # see all profiles with speeds
shard status     # check what's running
```

---

## How It Works

### `shard detect` — See Your Hardware

```
shard: detected system specs
-----------------------------
  OS:         Microsoft Windows 10.0.22631
  CPU:        AMD Ryzen 9 7950X 16-Core Processor
  CPU cores:  32
  Threads:    16 (recommended for llama.cpp)
  RAM:        64 GB
  GPU:        NVIDIA GeForce RTX 4080
  VRAM:       16 GB
  CUDA:       12.4
```

### `shard recalc` — Auto-Tune Profiles

Runs `llama-bench` and `llama-completion` across multiple GPU layer offload values and context sizes, then saves the fastest working configuration for each profile:

1. Sweeps `-ngl` candidates at 4K context to find your best speed
2. Probes 8K, 16K, and 32K context to find what your VRAM can handle
3. Calculates optimal thread count from your CPU
4. Saves everything to `.shard/profiles.json`

After recalc, every profile is tuned to **your** GPU — not someone else's.

### Profiles

| # | Name | Context | Purpose |
|--:|------|--------:|---------|
| 1 | Daily Default | 4K | Best speed for everyday chat and coding |
| 2 | Stability Fallback | 4K | Extra VRAM headroom when profile 1 has fit errors |
| 3 | Long Context | 8K | Larger conversation history |
| 4 | XL Context | 16K | Extended reasoning and longer documents |
| 5 | XXL Context | 32K | Maximum context for very long inputs |

Switch profiles instantly — if a server is running, it auto-restarts with the new settings:

```powershell
shard 3          # switch to 8K context
shard 1          # back to fast daily mode
```

---

## Installation

```powershell
.\scripts\install-shard.ps1
```

This will:
- Detect your NVIDIA CUDA version (falls back to CPU if no GPU)
- Download the matching llama.cpp release
- Download the Q4_K_M quantized model (~17 GB)
- Create `shard.cmd` in `~/bin` and add it to your PATH
- Set `SHARD_HOME` environment variable

Optional flags:

```powershell
.\scripts\install-shard.ps1 -SkipRuntimeDownload    # already have llama.cpp
.\scripts\install-shard.ps1 -SkipModelDownload       # already have the model
.\scripts\install-shard.ps1 -Force                    # re-download model
.\scripts\install-shard.ps1 -LlamaCppTag b8589        # pin a specific release
```

Open a **new terminal** after install.

---

## All Commands

| Command | What it does |
|---------|-------------|
| `shard` | Start profile 1 (daily default) |
| `shard 1` through `shard 5` | Start/switch to a specific profile |
| `shard stop` | Stop the running server |
| `shard ls` | List all profiles with settings and speeds |
| `shard status` | Show running profile, PID, and endpoint |
| `shard info` | Show resolved runtime and model paths |
| `shard detect` | Show detected system specs |
| `shard recalc` | Benchmark hardware and auto-tune all profiles |
| `shard reset` | Remove tuned profiles, return to defaults |
| `shard update` | Update llama.cpp runtime and model to latest |
| `shard help` | Show usage summary |

---

## Use with Any OpenAI-Compatible App

The server exposes a standard OpenAI API at `http://127.0.0.1:8080/v1`:

```
POST /v1/chat/completions
POST /v1/completions
GET  /v1/models
GET  /health
```

### Example: PowerShell

```powershell
$body = @{
  model = "local"
  messages = @(
    @{ role = "user"; content = "Give me 3 tips for local LLM setup." }
  )
  temperature = 0.6
  max_tokens = 200
} | ConvertTo-Json -Depth 8

Invoke-RestMethod -Uri "http://127.0.0.1:8080/v1/chat/completions" -Method Post -ContentType "application/json" -Body $body
```

### Example: OpenCode

Add to your `opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "local-llama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local llama.cpp",
      "options": {
        "baseURL": "http://127.0.0.1:8080/v1"
      },
      "models": {
        "qwen-distilled": {
          "name": "Qwen 3.5 Claude Distilled"
        }
      }
    }
  },
  "model": "local-llama/qwen-distilled"
}
```

Works with any tool that supports OpenAI-compatible endpoints: [Open WebUI](https://github.com/open-webui/open-webui), [Continue.dev](https://continue.dev), [SillyTavern](https://sillytavernai.com/), [OpenCode](https://opencode.ai/), etc.

---

## CLI Usage (No Server)

For one-shot prompts directly from the terminal:

```powershell
.\tools\llama-b8589-win-cuda\llama-completion.exe -m .\models\Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf -ngl 56 -c 4096 -t 12 -fa on -no-cnv --temp 0.3 -n 256 -p "Explain quantization in 4 bullets."
```

For interactive chat:

```powershell
.\tools\llama-b8589-win-cuda\llama-cli.exe -m .\models\Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf -ngl 56 -c 4096 -t 12 -fa on --temp 0.6
```

> Replace `-ngl` and `-t` values with your `shard ls` output after running `shard recalc`.

---

## Author's Benchmarks

Tested on: **RTX 4080 (16 GB VRAM) / 64 GB RAM / Windows**

Default profiles ship with these values. Run `shard recalc` to replace them with values tuned for your hardware.

### Speed by profile

| Profile | Context | `-ngl` | Measured speed |
|--------:|--------:|-------:|---------------:|
| 1 | 4096 | 56 | 13.79–14.1 tok/s |
| 2 | 4096 | 48 | 9–10 tok/s |
| 3 | 8192 | 48 | 9.23 tok/s |
| 4 | 16384 | 32 | 5–6 tok/s (est.) |
| 5 | 32768 | 20 | 2–3 tok/s (est.) |

### Full `-ngl` sweep (tg64, Q4_K_M)

| ngl | tok/s | notes |
|----:|------:|-------|
| 16 | 4.46 | stable |
| 20 | 4.82 | stable |
| 24 | 5.03 | stable |
| 28 | 5.21 | stable |
| 32 | 5.96 | stable |
| 36 | 6.49 | stable |
| 40 | 6.96 | validated |
| 44 | 8.19 | validated |
| 48 | 9.53 | validated |
| **56** | **13.96** | **best stable** |
| 64 | 1.89–6.53 | inconsistent |
| 80 | 1.83–6.16 | inconsistent |
| 99 | 3.90–5.98 | inconsistent |

> High `-ngl` values (64+) were unreliable on this GPU. `shard recalc` finds the sweet spot for yours.

### Reproduce

```powershell
# Full sweep
.\tools\llama-b8589-win-cuda\llama-bench.exe -m .\models\Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf -r 1 --no-warmup -p 256 -n 64 -t 12 -ngl 16,20,24,28,32,36,40,44,48,56,64,80,99 -fa 1 -o md

# Focused validation
.\tools\llama-b8589-win-cuda\llama-bench.exe -m .\models\Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf -r 1 --no-warmup -p 256 -n 64 -t 12 -ngl 40,44,48,56,99 -fa 1 -o md
```

---

## Troubleshooting

| Error | Fix |
|-------|-----|
| `invalid argument: -temp` | Use `--temp`, not `-temp` |
| `failed to fit params to free device memory` | Lower `-ngl` first, then `-c`. Or switch to a higher-numbered profile |
| Command appears stuck | You're in interactive mode. Use `llama-completion.exe` with `-no-cnv` for one-shot |
| `llama-bench` rejects `-c` | This build doesn't accept `-c` in bench mode — remove it |

---

## Configuration

### Environment variable overrides

| Variable | Purpose |
|----------|---------|
| `SHARD_HOME` | Repo root (set by installer) |
| `SHARD_RUNTIME_EXE` | Force a specific `llama-server.exe` path |
| `SHARD_MODEL_PATH` | Force a specific `.gguf` model path |

### Logs and state

| File | Purpose |
|------|---------|
| `.shard/state.json` | Running server state |
| `.shard/server.stdout.log` | Server stdout |
| `.shard/server.stderr.log` | Server stderr |
| `.shard/profiles.json` | Tuned profiles (after `shard recalc`) |

---

## License

This repo provides tooling and configuration only. The model weights are subject to their upstream license. See the [model card](https://huggingface.co/mradermacher/Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled-GGUF) for details.
