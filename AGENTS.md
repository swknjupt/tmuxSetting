# Repository Guidelines

## Project Structure & Module Organization

- `tmuxSetting.sh` is the main Bash installer/uninstaller for tmux pane notifications.
- `README.md` contains user-facing installation, usage, dependency, and feature details.
- `doc/` contains the Chinese tmux cheat sheet and agent-specific notification guides.

There is no separate `src/`, `test/`, or `assets/` tree. The installer generates runtime assets under `$HOME/.tmux-pane-notify/`. Keep user configuration changes inside the marked `tmux-pane-notify` blocks.

## Build, Test, and Development Commands

This project has no build step or automated test suite.

```bash
bash -n tmuxSetting.sh                      # Validate Bash syntax
shellcheck tmuxSetting.sh                   # Lint when ShellCheck is installed
bash tmuxSetting.sh                         # Install or idempotently upgrade
bash tmuxSetting.sh --uninstall             # Remove marked config and runtime panel
```

Before testing installation, use a disposable home directory with a `.zshrc` so your real configuration is untouched.

## Coding Style & Naming Conventions

- Use Bash with `set -euo pipefail`; quote expansions and handle missing commands explicitly.
- Use two-space indentation, `lower_snake_case` for functions, and `UPPER_SNAKE_CASE` for constants and environment variables.
- Preserve the tmux/zsh and Codex hook markers and their balanced removal behavior.
- Keep the sandboxed state file, watcher, and `@tpn_state` / `@tpn_done_at` in sync; tmux Codex runs with `--no-daemon`, and Codex owns `pane_title`.
- When changing heredocs, preserve quoting intentionally: `<<'EOF'` prevents expansion, while `<<EOF` allows installer variables to render.
- Documentation is primarily Simplified Chinese. Match existing heading, table, and code-block conventions.

No repository formatter is configured. Keep shell style consistent and use ShellCheck when available.

## Testing Guidelines

There is no test framework, coverage target, or test naming convention. Manually verify syntax and test install, upgrade, and uninstall behavior in a temporary `HOME`. Confirm idempotence, backups, marker cleanup, command thresholds, Codex hook migration, multi-pane done states, and the `prefix+t` panel on tmux 3.2+.

## Commit & Pull Request Guidelines

Git history uses Conventional Commit-style subjects such as `feat: ...`, `docs: ...`, and `chore: ...`; write concise, lower-case summaries. Pull requests should explain the change, compatibility impact, installation/uninstallation effects, and validation commands or results. Link relevant issues and include terminal captures for visible pane or panel changes.

## Configuration Safety

Preserve the `.tpn.bak` first-install backup contract and uninstall only files or blocks owned by this tool. Keep `TPN_MIN_SEC`, `TPN_AGENT_CMDS`, and `TMUX_PANE_NOTIFY_MIN_SEC` behavior documented when changed. Never commit credentials or user-specific configuration.
