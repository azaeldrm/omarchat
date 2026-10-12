# Omarchat

A quick, throwaway AI chat for [Omarchy](https://omarchy.org). Press a shortcut,
ask a question, get an answer with its sources, and press Esc. Nothing is kept.

![Omarchat answering a question with a cited source](preview.png)

- **Your agents and models.** Works with Claude Code, Pi, Codex, and opencode,
  and lists every model they offer you, including local ones through Pi.
- **Search-only.** The model can search the web and nothing else: no files, no
  commands, no local network.
- **Throwaway.** Close the card and the conversation is gone.
- **Looks like Omarchy.** Styled like the Omarchy menu, and follows your theme.

## Requirements

- Omarchy 4
- `bubblewrap`: `omarchy pkg add bubblewrap`
- At least one agent, logged in:
  - [Claude Code](https://claude.com/claude-code): `omarchy default agent claude`
  - [Pi](https://pi.dev): `omarchy default agent pi`, then `/login` inside `pi`
  - [Codex](https://developers.openai.com/codex): `omarchy default agent codex`, then `codex login`
  - [opencode](https://opencode.ai): `omarchy default agent opencode`, then `opencode auth login`

No agent yet? Open Omarchat anyway and pick one to set up.

## Install

```bash
omarchy plugin add https://github.com/azaeldrm/omarchat.git --enable
```

Bind a key in `~/.config/hypr/bindings.lua`, e.g. Super+Alt+Space (which
Omarchy uses for the apps menu, so unbind it first):

```lua
hl.unbind("SUPER + ALT + SPACE")
o.bind("SUPER + ALT + SPACE", "Omarchat", "omarchy-shell shell toggle azaeldrm.omarchat '{}'")
```

Optionally, add **Ask Omarchat** and **Settings** to the Omarchy menu: paste
the rows from `extras/omarchy-menu.jsonc` into
`~/.config/omarchy/extensions/omarchy-menu.jsonc`.

## Usage

| Key | Action |
| --- | --- |
| Enter | Send |
| Shift+Enter | New line |
| Ctrl+, | Settings: choose the agent and model |
| Ctrl+Y | Copy the last answer |
| PgUp / PgDn | Scroll |
| Esc | Close and forget the chat |

In settings, type to filter and press Enter to choose. Models a plan doesn't
include are greyed out once refused.

Open it from a script, with a question or straight into settings:

```bash
omarchy-shell shell summon azaeldrm.omarchat '{"prompt":"What is the latest Hyprland release?"}'
omarchy-shell shell summon azaeldrm.omarchat '{"settings":true}'
```

## Privacy and security

- **Search is the only tool.** Every other tool is switched off, and no search
  tool takes a URL, so the model can't reach your machine or network.
- **Sandboxed.** Each chat runs in bubblewrap with a read-only system and an
  empty home folder: your documents, keys, and configs aren't there to read,
  even for tools an agent can't switch off.
- **Nothing saved.** No transcripts are kept.

Your questions go to the model's provider, and search queries go to
[Exa](https://exa.ai) with Pi and opencode. Exa's free search is rate-limited;
set `EXA_API_KEY` in your environment for more.

## Update and remove

```bash
omarchy plugin update azaeldrm.omarchat
omarchy plugin remove azaeldrm.omarchat
```

Run `omarchy restart shell` after an update.

## Development

```bash
tests/run           # offline checks (what CI runs)
tests/run --live    # also real chats and the search-only checks, per agent
```

## License

MIT
