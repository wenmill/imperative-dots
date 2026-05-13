# Personal Hyprland dots

Custom Hyprland + Quickshell setup. Layout inspired by [ilyamiro/imperative-dots](https://github.com/ilyamiro/imperative-dots) — install script structure and the symlink approach are based on theirs. Everything inside the configs (the bar, popups, scripts, themes, AI integration) is custom.

## What's in here

```
.config/
├── cava/                     # CLI audio visualizer
├── hypr/
│   ├── hyprland.conf         # WM config
│   ├── ai_config.json        # AI / chess / kavita keys (created on install)
│   └── scripts/
│       ├── focus_warning.sh  # opens FocusWarning.qml at 5min
│       ├── focus_mode_helper.sh
│       ├── qs_manager.sh     # popup IPC dispatcher
│       └── quickshell/
│           ├── Main.qml
│           ├── TopBar.qml
│           ├── WindowRegistry.js
│           ├── AiPopup.qml
│           ├── AppMenu.qml
│           ├── ClipboardMenu.qml
│           ├── FocusWarning.qml
│           ├── chess_stream.sh
│           ├── battery/BatteryPopup.qml
│           ├── calendar/CalendarPopup.qml
│           ├── network/NetworkPopup.qml
│           ├── settings/SystemSettings.qml
│           └── notifications/NotificationPopups.qml
├── kitty/                    # terminal
├── matugen/                  # generates color palettes from wallpapers
├── nvim/
└── swaync/                   # notification daemon

.local/share/fonts/           # JetBrains Mono Nerd Font etc.
install.sh
```

No `rofi/` — the launcher (AppMenu.qml) and clipboard picker (ClipboardMenu.qml) are in QML and don't need rofi anymore.

## Install

```bash
git clone <your-repo-url> ~/.hyprland-dots
cd ~/.hyprland-dots
./install.sh
```

The script:
1. Installs paru if missing, then all required pacman + AUR packages
2. Backs up any existing `~/.config/{cava,hypr,kitty,nvim,swaync,matugen}` to `~/.config-backup-<timestamp>/`
3. Symlinks the repo's `.config/*` folders into `~/.config/`
4. Copies fonts to `~/.local/share/fonts/` and refreshes the cache
5. Creates `~/.config/hypr/ai_config.json` with empty fields
6. (Optional) Installs Hermes Agent and writes a minimal `~/.hermes/config.yaml` pointing at local ollama

## Post-install

Edit `~/.config/hypr/ai_config.json`:
- `api_key` — for OpenWebUI / your remote LLM (`"ollama"` if using local ollama directly)
- `base_url` — `http://localhost:11434/v1` for local ollama, or your OpenWebUI URL
- `model` — model name (e.g. `qwen2.5:7b`, `Agentic-Intelligence`)
- `lichess_token` — from [lichess.org/account/oauth/token](https://lichess.org/account/oauth/token), enable **Board API** + **Challenge** scopes
- `kavita_url` + `kavita_api_key` — from your Kavita server's Account → API Key
- `hermes_enabled` — set `true` to let the AI tab call Hermes for shell actions
- `approval_policy` — `ask` (default), `auto` (no prompts), or `deny` (read-only)

Then pull a model:
```bash
ollama pull qwen2.5:7b
```

Hermes works with any tool-calling model. Good local choices: `qwen2.5:7b`, `qwen2.5-coder:7b`, `llama3.2`, `mistral-small`. Skip pure-chat models — they ignore tool schemas.

## AI popup → Hermes integration

The Chat tab in the AI popup talks to two backends depending on the request:

- **Plain questions** → goes to `base_url` directly (OpenWebUI or ollama)
- **Action requests** ("open my calendar", "set volume to 30") → goes to Hermes if `hermes_enabled: true`, which decides which tool to call

When Hermes wants to run a shell command, the popup checks `approval_policy`:
- `ask` — shows the command in an approval dialog with **Allow** / **Deny** buttons
- `auto` — runs it silently (only safe for trusted models on commands you've allowlisted)
- `deny` — refuses everything that touches the shell

The allowlist + denylist live in `~/.hermes/config.yaml`. Anything in the denylist always requires manual approval regardless of the popup's policy setting. Edit that file to taste — `rm -rf`, `sudo`, `dd`, `mkfs`, `passwd` are denied by default.

## Update

```bash
cd ~/.hyprland-dots
git pull
./install.sh   # safe to re-run, only re-symlinks missing folders
```

## Uninstall

```bash
# Restore from backup
mv ~/.config-backup-<timestamp>/* ~/.config/
# Remove symlinks if any survived
rm -rf ~/.hyprland-dots
```

## Credits

- Install script structure adapted from [ilyamiro/imperative-dots](https://github.com/ilyamiro/imperative-dots)
- Hyprland, Quickshell, Hermes Agent, Matugen — see their respective repos
