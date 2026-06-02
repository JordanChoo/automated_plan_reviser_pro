# Automated Plan Reviser Pro (apr)

APR automates iterative specification refinement with OpenAI Responses API background jobs. It bundles a project README, specification, and optional implementation document into a single review prompt, creates a stored Responses API job, tracks the response id locally, and saves completed review output under `.apr/rounds/`.

## Quick Start

```bash
export OPENAI_API_KEY=sk-...
apr setup
apr run 1
apr status
apr attach apr-default-round-1
apr run 2 --wait
```

`apr run` creates a background API job by default. Use `--wait` when you want APR to poll until completion and write the round output before returning.

## What APR Does

- Builds deterministic review bundles from README, spec, and optional implementation docs.
- Sends the bundle to `POST /v1/responses` with `background: true` and `store: true`.
- Records API session metadata in `.apr/api_sessions/<slug>.json`.
- Caches raw API responses in `.apr/logs/api_<slug>.json`.
- Saves completed review text to `.apr/rounds/<workflow>/round_N.md`.
- Provides human commands and robot JSON commands for agents.

## Commands

```bash
apr setup                      # Interactive workflow setup
apr run <N>                    # Create API review job for round N
apr run <N> --wait             # Poll until completion
apr run <N> --include-impl     # Include implementation document
apr run <N> --dry-run          # Preview API request metadata
apr run <N> --render           # Print full API prompt bundle
apr status [--hours 24]        # List and refresh API sessions
apr attach <slug|response_id>  # Show status or completed output
apr show <N>                   # View saved round output
apr history                    # List saved rounds
apr diff <N> [M]               # Compare round outputs
apr integrate <N> --copy       # Build implementation prompt from review output
apr stats                      # Convergence analytics
apr backfill                   # Generate metrics from existing rounds
apr update                     # Self-update
```

## Robot Mode

Robot mode emits JSON by default and TOON when requested and available.

```bash
apr robot status
apr robot validate 3 -w myspec
apr robot run 3 -w myspec -i
apr robot history -w myspec
apr robot integrate 3 -w myspec
apr robot stats -w myspec
```

Response envelope:

```json
{
  "ok": true,
  "code": "ok",
  "data": {},
  "meta": {"v": "1.2.2", "ts": "2026-06-02T00:00:00Z"}
}
```

`apr robot run` returns fields such as `slug`, `response_id`, `api_status`, `model`, `reasoning_effort`, `output_file`, and `log_file`.

Error codes: `ok`, `usage_error`, `not_configured`, `config_error`, `validation_failed`, `dependency_missing`, `busy`, `network_error`, `update_error`, `attachment_mismatch`, `not_implemented`, `internal_error`.

## Workflow Configuration

APR stores workflow config in `.apr/workflows/<name>.yaml`:

```yaml
name: default
description: Iterative specification refinement

documents:
  readme: README.md
  spec: SPECIFICATION.md
  implementation: docs/implementation.md

api:
  model: "gpt-5.5"
  reasoning_effort: high

rounds:
  output_dir: .apr/rounds/default
  impl_every_n: 4

template: |
  First, read the README section.
  Then read the specification section.
  Review the plan carefully and propose concrete improvements.

template_with_impl: |
  First, read the README, implementation, and specification sections.
  Review the plan against the implementation reality and propose concrete improvements.
```

`template_with_impl` is optional. If omitted, APR falls back to `template`. If no template is configured, APR uses its built-in review prompt. Do not use `{{README}}` or similar placeholders; APR includes document contents in the API bundle automatically.

## Project Files

```text
.apr/
├── config.yaml
├── workflows/<name>.yaml
├── api_sessions/<slug>.json
├── logs/api_<slug>.json
├── rounds/<workflow>/round_N.md
├── analytics/<workflow>/metrics.json
└── templates/
```

## Environment Variables

| Variable | Purpose | Default |
|---|---|---|
| `OPENAI_API_KEY` | Required API credential for run/refresh/attach | unset |
| `OPENAI_BASE_URL` | OpenAI-compatible API base URL | `https://api.openai.com/v1` |
| `APR_DEFAULT_MODEL` | Default model for new workflows | `gpt-5.5` |
| `APR_REASONING_EFFORT` | Override workflow reasoning effort | unset |
| `APR_TEXT_VERBOSITY` | Responses API text verbosity | `medium` |
| `APR_MAX_OUTPUT_TOKENS` | Max output tokens | `32768` |
| `APR_API_TIMEOUT` | Per-request timeout seconds | `60` |
| `APR_API_POLL_INTERVAL` | Poll interval for `--wait` | `10` |
| `APR_API_MAX_POLL_SECONDS` | Max polling duration | `21600` |
| `APR_NO_GUM` | Disable gum UI | unset |
| `APR_STATUS_HOURS` | Default status window | `72` |

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Partial failure |
| `2` | Usage error |
| `3` | Missing dependency or API credential |
| `4` | Config or validation error |
| `10` | Network/API error |
| `11` | Update error |
| `12` | Busy: active run for the workflow/round |

## Security

APR reads `OPENAI_API_KEY` from the environment and does not write it to disk. Review bundles are sent to `OPENAI_BASE_URL`. Response metadata and raw response JSON are cached locally under `.apr/` so users and agents can inspect status and output deterministically.

## Development

```bash
bash -n apr install.sh
shellcheck apr install.sh
tests/run_tests.sh
```

When making changes, keep `.beads/` updates committed with code changes and use `br`/`bv --robot-*` for issue tracking as described in `AGENTS.md`.
