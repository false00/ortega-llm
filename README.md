# Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled Daily Run Guide

This guide is for this exact machine and workspace.

## System and Files
- OS: Windows
- GPU: NVIDIA GeForce RTX 4080 (16 GB VRAM)
- RAM: 64 GB
- Driver seen during tests: 595.79
- Runtime: llama.cpp b8589 (CUDA build)

Paths in this repo:
- Runtime binaries: `tools/llama-b8589-win-cuda/`
- Model file: `models/Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf`

## Short Answer
Yes, this model runs well on this system.

Best daily preset from tests:
- Quant: `Q4_K_M`
- `-ngl 56`
- `-c 4096`
- `-t 12`
- `-fa on`

Measured real generation speed at this preset:
- about `13.79` to `14.1` tokens/sec

## Ortega Command Launcher (Recommended)

You can control the local API server with a single command: `ortega`.

### Install

From repo root:

```powershell
.\scripts\install-ortega.ps1
```

What install does:
- Creates command wrapper: `C:\Users\<you>\bin\ortega.cmd`
- Adds `C:\Users\<you>\bin` to your user PATH (if missing)

After install, open a new terminal.

### Commands

- `ortega`
  - Starts profile `1` (daily default)

- `ortega stop`
  - Stops running server

- `ortega ls`
  - Lists all profiles and speed/context info

- `ortega 1`
  - Start/switch to profile 1

- `ortega 2`
  - Start/switch to profile 2

- `ortega 3`
  - Start/switch to profile 3

- `ortega status`
  - Shows current running profile, PID, and endpoint

### Profile behavior

- If you run `ortega 2` while profile 1 is running, it automatically does:
  1. stop current server
  2. start server with profile 2 settings

### Profile list (used by `ortega ls`)

| profile | name | settings | measured speed |
|---:|---|---|---:|
| 1 | Daily Default | `-ngl 56 -c 4096 -t 12 -fa on` | `13.79` to `14.1` tok/s |
| 2 | Stability Fallback | `-ngl 48 -c 4096 -t 12 -fa on` | `9-10` tok/s |
| 3 | Long Context | `-ngl 48 -c 8192 -t 12 -fa on` | `9.23` tok/s |

### Logs and state

Runtime state and logs are written to:
- `.ortega/state.json`
- `.ortega/server.stdout.log`
- `.ortega/server.stderr.log`

## Daily Use (Simple Workflow)

### 1) Start local API server
Run this in PowerShell from repo root:

```powershell
.\tools\llama-b8589-win-cuda\llama-server.exe -m .\models\Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf -ngl 56 -c 4096 -t 12 -fa on --host 127.0.0.1 --port 8080
```

Use it from apps that support OpenAI-style local endpoints at:
- `http://127.0.0.1:8080`

OpenAI-compatible base URL:
- `http://127.0.0.1:8080/v1`

Common endpoints:
- `POST /v1/chat/completions`
- `POST /v1/completions`
- `GET /v1/models`
- `GET /health`

Stop server with `Ctrl+C`.

## Local API Server (Practical Setup)

If your goal is practical daily use, this is the recommended way to run the model.

### Ranked server profiles

### 1) Daily default server profile (recommended)
- Use when: you want best overall quality/speed for normal chat and coding use
- Command:

```powershell
.\tools\llama-b8589-win-cuda\llama-server.exe -m .\models\Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf -ngl 56 -c 4096 -t 12 -fa on --host 127.0.0.1 --port 8080
```

- Why this is #1 on this machine:
  - Best repeatable performance in testing
  - Real generation around 13.79 to 14.1 tok/s at `-c 4096`
  - Stable for normal daily workloads

### 2) Stability fallback server profile
- Use when: you get memory fitting errors or want extra VRAM headroom
- Command:

```powershell
.\tools\llama-b8589-win-cuda\llama-server.exe -m .\models\Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf -ngl 48 -c 4096 -t 12 -fa on --host 127.0.0.1 --port 8080
```

- Why this is #2:
  - Slightly slower than #1
  - Benchmarked generation at this offload is around 9 to 10 tok/s at `-c 4096`
  - More predictable memory behavior

### 3) Long-context server profile
- Use when: you need larger conversation history
- Command:

```powershell
.\tools\llama-b8589-win-cuda\llama-server.exe -m .\models\Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf -ngl 48 -c 8192 -t 12 -fa on --host 127.0.0.1 --port 8080
```

- Why this is #3:
  - Confirmed practical fallback for 8192 context
  - Measured generation speed is around 9.23 tok/s at `-c 8192`

### Context size to token speed (measured)

| context size | profile used | measured generation speed |
|---:|---|---:|
| 4096 | `-ngl 56 -t 12 -fa on` | `13.79` to `14.1` tok/s |
| 8192 | `-ngl 48 -t 12 -fa on` | `9.23` tok/s |

Notes:
- These numbers are from real one-shot `llama-completion.exe` runs.
- 8192 with `-ngl 56` failed memory fitting on this machine.

### Quick health check after startup

```powershell
Invoke-WebRequest http://127.0.0.1:8080/health
```

If this returns success, the server is up.

### Quick API test (OpenAI-compatible)

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

### Daily operation checklist
1. Start profile #1.
2. Run health check.
3. Run API test once.
4. If memory fit fails, move to profile #2.
5. Only use profile #3 when you really need longer context.

## CLI Usage (No API Server)

Use this when you want to run everything directly from terminal.

### Ranked CLI profiles

### 1) One-shot CLI default (recommended)
- Best for: quick prompts, scripts, testing
- Context/speed: `-c 4096` at about `13.79` to `14.1` tok/s

```powershell
.\tools\llama-b8589-win-cuda\llama-completion.exe -m .\models\Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf -ngl 56 -c 4096 -t 12 -fa on -no-cnv --temp 0.3 -n 256 -p "Explain quantization in 4 bullets."
```

### 2) Interactive CLI chat
- Best for: terminal-only chat sessions
- Note: interactive mode waits for more input by design

```powershell
.\tools\llama-b8589-win-cuda\llama-cli.exe -m .\models\Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf -ngl 56 -c 4096 -t 12 -fa on --temp 0.6
```

Useful commands inside chat:
- `/clear` clears history
- `/regen` regenerates last answer
- `/exit` exits

### 3) Long-context one-shot CLI fallback
- Best for: larger prompt history in single prompt runs
- Context/speed: `-c 8192` at about `9.23` tok/s

```powershell
.\tools\llama-b8589-win-cuda\llama-completion.exe -m .\models\Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf -ngl 48 -c 8192 -t 12 -fa on -no-cnv --temp 0.3 -n 256 -p "Summarize this text in bullet points: ..."
```

### CLI quick fallback order
1. Start with `-ngl 56 -c 4096`.
2. If fit fails, drop to `-ngl 48 -c 4096`.
3. If you need larger context, use `-ngl 48 -c 8192`.
4. If still failing, drop `-ngl` to `44` or `40`.

### 2) One-shot prompt mode
If you want direct command-line prompts instead of a server:

```powershell
.\tools\llama-b8589-win-cuda\llama-completion.exe -m .\models\Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf -ngl 56 -c 4096 -t 12 -fa on -no-cnv --temp 0.3 -n 256 -p "Explain quantization in 4 bullets."
```

### 3) If memory errors happen
Apply in this order:
1. Drop `-ngl` from `56` to `48`
2. If needed, drop to `44`, then `40`
3. If needed, reduce context from `4096` to `3072` or `2048`

Fallback command:

```powershell
.\tools\llama-b8589-win-cuda\llama-completion.exe -m .\models\Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf -ngl 48 -c 4096 -t 12 -fa on -no-cnv --temp 0.3 -n 256 -p "Your prompt"
```

## Recommended Presets

### Preset A (best overall)
- Use: daily balanced quality/speed
- Flags: `-ngl 56 -c 4096 -t 12 -fa on`
- Expected speed: around `14 tok/s`

### Preset B (extra stability)
- Use: occasional fit failures
- Flags: `-ngl 48 -c 4096 -t 12 -fa on`
- Expected speed: around `9-10 tok/s` benchmarked

### Preset C (longer context)
- Use: larger prompt history
- Flags: `-ngl 48 -c 8192 -t 12 -fa on`
- Measured real speed: around `9.23 tok/s`

## Ranked Run Order (What To Use First)

If you want the simplest decision path, use runs in this order.

### 1) Recommended default for daily use
- Command type: `llama-server.exe`
- Flags: `-ngl 56 -c 4096 -t 12 -fa on`
- Why this is rank #1:
  - Best repeatable real-world speed on this machine (~14 tok/s)
  - Enough context for normal daily workflows
  - Stable in repeated tests

### 2) Recommended fallback when memory fitting fails
- Command type: `llama-server.exe` or `llama-completion.exe`
- Flags: `-ngl 48 -c 4096 -t 12 -fa on`
- Why this is rank #2:
  - Small speed drop versus rank #1
  - Much safer VRAM headroom
  - Good for longer sessions where memory pressure can vary

### 3) Recommended for larger context sessions
- Command type: `llama-server.exe` or `llama-completion.exe`
- Flags: `-ngl 48 -c 8192 -t 12 -fa on`
- Why this is rank #3:
  - Confirmed working at 8192 context (exit code 0)
  - Keeps model usable when longer prompt history is required
  - Slower than 4096 profile (~9.23 tok/s measured)

### 4) Not recommended for normal use on this setup
- High offload near full GPU (`-ngl 64+`)
- Why this is not recommended:
  - Inconsistent benchmark behavior across runs
  - Sometimes slower than `-ngl 56`
  - Less predictable for day-to-day reliability

### Quick chooser
- Use rank #1 if you want best all-around daily experience.
- Use rank #2 if you see fit/memory errors with rank #1.
- Use rank #3 only when you need more context window.

## Benchmarks Collected

All benchmark runs below used:
- `llama-bench`
- model `Q4_K_M`
- `-r 1 --no-warmup -p 256 -n 64 -t 12 -fa 1`

### Benchmark sweep results (tg64)

| ngl | tg64 t/s | notes |
|---:|---:|---|
| 16 | 4.46 | stable |
| 20 | 4.82 | stable |
| 24 | 5.03 | stable |
| 28 | 5.21 | stable |
| 32 | 5.96 | stable |
| 36 | 6.49 | stable |
| 40 | 6.96 | rerun validated |
| 44 | 8.19 | rerun validated |
| 48 | 9.53 | rerun validated |
| 56 | 13.96 | rerun validated, best |
| 64 | 1.89 (one run), 6.53 (earlier run) | inconsistent |
| 80 | 1.83 (one run), 6.16 (earlier run) | inconsistent |
| 99 | 5.98 (rerun), 3.90 (earlier run) | inconsistent |

Note on inconsistencies:
- High `ngl` values near full offload (`64+`) were not consistently better in repeated tests on this setup.
- `ngl 56` was the strongest repeatable point.

### Real one-shot completion tests

Using `llama-completion.exe -no-cnv`:

- `-ngl 56 -c 4096`: `13.79 tok/s` eval
- `-ngl 48 -c 8192`: `9.23 tok/s` eval

Also observed earlier with `llama-cli` at 4096:
- around `14.1 tok/s`

## Reproduce the Tests

### A) Full ngl sweep command
```powershell
.\tools\llama-b8589-win-cuda\llama-bench.exe -m .\models\Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf -r 1 --no-warmup -p 256 -n 64 -t 12 -ngl 16,20,24,28,32,36,40,44,48,56,64,80,99 -fa 1 -o md
```

### B) Focused validation command
```powershell
.\tools\llama-b8589-win-cuda\llama-bench.exe -m .\models\Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf -r 1 --no-warmup -p 256 -n 64 -t 12 -ngl 40,44,48,56,99 -fa 1 -o md
```

### C) Real completion speed command (4096)
```powershell
.\tools\llama-b8589-win-cuda\llama-completion.exe -m .\models\Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf -ngl 56 -c 4096 -n 64 -t 12 -fa on -no-cnv --temp 0.3 --no-warmup -p "Give 4 concise bullets about local LLM setup."
```

### D) Real completion speed command (8192 fallback)
```powershell
.\tools\llama-b8589-win-cuda\llama-completion.exe -m .\models\Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.Q4_K_M.gguf -ngl 48 -c 8192 -n 64 -t 12 -fa on -no-cnv --temp 0.3 --no-warmup -p "Give 4 concise bullets about local LLM setup."
```

## Known Errors and Fast Fixes

- Error: `invalid argument: -temp`
  - Fix: use `--temp`, not `-temp`.

- Error: `failed to fit params to free device memory`
  - Fix: lower `-ngl` first, then lower `-c`.

- Error: command appears stuck
  - Cause: conversation/interactive mode waiting for input.
  - Fix: use `llama-completion.exe` with `-no-cnv` for one-shot runs.

- Error with `llama-bench ... -c ...`
  - Cause: this build rejects `-c` in bench mode.
  - Fix: remove `-c` from benchmark commands.

## Practical Recommendation

For normal daily use on this exact system:
1. Use `llama-server.exe` with `-ngl 56 -c 4096 -t 12 -fa on`.
2. Keep `Q4_K_M` as default quant.
3. Use `-ngl 48` only when memory fitting fails or when you need `-c 8192`.
