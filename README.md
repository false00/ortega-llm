# Shard

**Run Qwen3.5 reasoning models locally. One command. Auto-tuned to your hardware.**

Shard wraps the [Qwen3.5-Claude-4.6-Opus-Reasoning-Distilled](https://huggingface.co/collections/Jackrong/qwen35-claude-46-opus-reasoning-distilled) model family with a zero-config launcher that detects your GPU, benchmarks your system, and picks the fastest settings automatically. No YAML files. No guessing `-ngl` values. Just `shard`.

---

### Why Shard?

| | |
|---|---|
| **Multi-model support** | 5 model sizes from 0.8B to 27B — pick what fits your hardware |
| **One-command install** | Downloads llama.cpp + model + creates the `shard` command globally |
| **Auto hardware detection** | Detects your GPU, VRAM, CPU cores, CUDA version |
| **Auto-tuning** | Benchmarks your specific machine and generates optimized profiles |
| **5 built-in profiles** | From fast daily chat (4K context) to deep reasoning (32K context) |
| **Per-model profiles** | Each model gets its own tuned profiles — recalc one, many, or all |
| **Smart quant picker** | Detects your VRAM/RAM and recommends the best quantization per model |
| **OpenAI-compatible API** | Drop-in replacement at `localhost:8080/v1` for any app that speaks OpenAI |
| **Hot profile switching** | Switch context/speed profiles without manual restarts |
| **Works on any NVIDIA GPU** | CUDA auto-detected; CPU fallback if no GPU |

---

## Available Models

All models from the [Qwen3.5-Claude-4.6-Opus-Reasoning-Distilled collection](https://huggingface.co/collections/Jackrong/qwen35-claude-46-opus-reasoning-distilled):

| Size | Model | Q4_K_M | Best For |
|-----:|-------|-------:|----------|
| 27B | Qwen3.5-27B | 16.5 GB | Maximum quality — coding agents, deep reasoning |
| 9B | Qwen3.5-9B | 5.6 GB | Great balance of quality and speed |
| 4B | Qwen3.5-4B | 2.7 GB | Fast general use, fits most GPUs |
| 2B | Qwen3.5-2B | 1.3 GB | Lightweight, very fast |
| 0.8B | Qwen3.5-0.8B | 527 MB | Minimal — testing, embedded, CPU-only |

Multiple quantization levels available per model (Q2_K through Q8_0). During install and download, Shard detects your VRAM and RAM and recommends the best quant for each model — quants that won't fit are flagged so you don't waste disk space.

---

## Quick Start

```powershell
# 1. Install (downloads runtime + lets you choose which model(s) to download)
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
shard 2          # switch to a different profile (1-7)
shard ls         # see all profiles with speeds
shard status     # check what's running
shard model 9B   # switch to a different model
shard download   # get more models (shows recommended quants for your hardware)
shard check      # check HuggingFace for new models
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

1. **Detects your VRAM** and filters out ngl values that clearly won't fit
2. Sweeps `-ngl` candidates at 4K context to find your best speed
3. **Adaptively narrows** candidates for 8K, 16K, and 32K
4. Calculates optimal thread count from your CPU
5. Saves everything to `.shard/profiles.json` under the model's key

Recalc supports targeting specific models:

```powershell
shard recalc          # recalc active model
shard recalc 9B       # recalc a specific model
shard recalc 27B,9B   # recalc multiple models
shard recalc all      # recalc all installed models
```

After recalc, every profile is tuned to **your** GPU — not someone else's.

### Profiles

| # | Name | Context | Purpose |
|--:|------|--------:|---------|
| 1 | Daily Default | 4K | Best speed for everyday chat and coding |
| 2 | Stability Fallback | 4K | Extra VRAM headroom when profile 1 has fit errors |
| 3 | Long Context | 8K | Larger conversation history |
| 4 | XL Context | 16K | Extended reasoning and longer documents |
| 5 | XXL Context | 32K | Maximum context for very long inputs |
| 6 | Ultra Context | 64K | Massive reasoning chains and deep analysis |
| 7 | Max Context | 128K | Full document analysis |
| 8 | Absolute Max | 256K | Full native context window (262K) |

Each model gets its own set of tuned profiles. Switch profiles instantly — if a server is running, it auto-restarts with the new settings:

```powershell
shard 3          # switch to 8K context
shard 1          # back to fast daily mode
```

### Model Management

```powershell
shard model          # show all models and which is active
shard model 9B       # switch active model to 9B
shard download       # interactive model download menu
shard download 4B    # download 4B with default quant (Q4_K_M)
shard download 4B Q8_0   # download a specific quant
shard check          # check HuggingFace for available/new models
```

---

## Installation

```powershell
.\scripts\install-shard.ps1
```

This will:
- Detect your NVIDIA CUDA version (falls back to CPU if no GPU)
- Download the matching llama.cpp release
- **Prompt you to select which model(s) to download**
- Create `shard.cmd` in `~/bin` and add it to your PATH
- Set `SHARD_HOME` environment variable

Optional flags:

```powershell
.\scripts\install-shard.ps1 -SkipRuntimeDownload       # already have llama.cpp
.\scripts\install-shard.ps1 -SkipModelDownload          # already have models
.\scripts\install-shard.ps1 -Force                       # re-download everything
.\scripts\install-shard.ps1 -LlamaCppTag b8589           # pin a specific release
.\scripts\install-shard.ps1 -Models 27B,9B               # download specific models
.\scripts\install-shard.ps1 -Models all                  # download all models
.\scripts\install-shard.ps1 -Models 27B -Quant Q8_0      # specific quant
```

Open a **new terminal** after install.

---

## All Commands

| Command | What it does |
|---------|-------------|
| `shard` | Start active model with profile 1 (daily default) |
| `shard 1` through `shard 8` | Start/switch to a specific profile |
| `shard stop` | Stop the running server |
| `shard ls` | List all profiles with settings, speeds, and installed models |
| `shard status` | Show running profile, PID, and endpoint |
| `shard info` | Show resolved runtime and model paths |
| `shard model` | Show available models and which is active |
| `shard model <id>` | Switch active model (e.g. `shard model 9B`) |
| `shard download` | Interactive model download with hardware-aware quant recommendations |
| `shard download <id> [quant]` | Download a specific model |
| `shard check` | Check HuggingFace for new/updated models |
| `shard detect` | Show detected system specs |
| `shard recalc` | Benchmark active model and auto-tune profiles |
| `shard recalc all` | Benchmark all installed models |
| `shard recalc <id>` | Benchmark a specific model |
| `shard reset` | Remove all profile overrides |
| `shard reset <id>` | Remove profile overrides for a specific model |
| `shard update` | Update llama.cpp runtime to latest |
| `shard opencode` | Setup/update OpenCode config for local shard |
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

Shard can automatically configure [OpenCode](https://opencode.ai/) to use your local server:

```powershell
shard opencode   # setup config (offers to install opencode if needed)
shard            # start the server
opencode         # launch OpenCode, then /models to select shard
```

This generates `%USERPROFILE%\.config\opencode\opencode.jsonc` with the correct provider, model, and context limits from your tuned profiles. The config auto-updates when you:

- **Switch profiles** (`shard 3`) — updates context limits to match
- **Run recalc** (`shard recalc`) — updates with new speed/context values
- **Run `shard opencode`** again — refreshes everything

Existing providers in your opencode config are preserved — only the `"shard"` provider entry is touched.

Works with any tool that supports OpenAI-compatible endpoints: [Open WebUI](https://github.com/open-webui/open-webui), [Continue.dev](https://continue.dev), [SillyTavern](https://sillytavernai.com/), [OpenCode](https://opencode.ai/), etc.

---

## CLI Usage (No Server)

For one-shot prompts directly from the terminal:

```powershell
.\tools\llama-b8589-win-cuda\llama-completion.exe -m .\models\Qwen3.5-27B.Q4_K_M.gguf -ngl 56 -c 4096 -t 12 -fa on -no-cnv --temp 0.3 -n 256 -p "Explain quantization in 4 bullets."
```

For interactive chat:

```powershell
.\tools\llama-b8589-win-cuda\llama-cli.exe -m .\models\Qwen3.5-27B.Q4_K_M.gguf -ngl 56 -c 4096 -t 12 -fa on --temp 0.6
```

> Replace `-ngl` and `-t` values with your `shard ls` output after running `shard recalc`.

---

## Configuration

All state is stored in `.shard/`:

| File | Purpose |
|------|---------|
| `profiles.json` | Per-model tuned profiles + active model selection |
| `state.json` | Running server info (PID, profile, endpoint) |
| `server.stdout.log` | Server stdout |
| `server.stderr.log` | Server stderr (loading info, metrics) |

The `profiles.json` format stores profiles per model:

```json
{
  "activeModel": "27B",
  "models": {
    "27B": {
      "1": { "Ngl": 64, "Context": 4096, "Threads": 16, "Speed": "29.11 tok/s", "Name": "Daily Default" },
      "2": { "Ngl": 56, "Context": 4096, "Threads": 16, "Speed": "15.27 tok/s", "Name": "Stability Fallback" }
    },
    "9B": {
      "1": { "Ngl": 41, "Context": 4096, "Threads": 16, "Speed": "52.3 tok/s", "Name": "Daily Default" }
    }
  }
}
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `shard` not found | Open a **new** terminal after install |
| VRAM overflow / fit errors | Switch to a lower profile (`shard 2`) or smaller model (`shard model 4B`) |
| Slow speeds | Run `shard recalc` to find optimal settings |
| Model not found | Run `shard download` to get models |
| Want a different model | Run `shard model` to see options, `shard model 9B` to switch |
| Check for new models | Run `shard check` |

---

## License

Apache-2.0 — same as the underlying Qwen3.5 models and llama.cpp.
