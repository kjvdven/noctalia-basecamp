# noctalia-basecamp

A [Noctalia 5](https://github.com/noctalia-dev/noctalia) plugin that puts your
Basecamp notifications in the bar: unread count on the Basecamp mark, a panel
with the list, mark-as-read, and an account filter. Everything goes through the
official [Basecamp CLI](https://github.com/basecamp/basecamp-cli); the plugin
never touches your tokens.

A port of 37signals' [Omarchy Basecamp plugin](https://github.com/basecamp/omarchy-basecamp-plugin)
to Noctalia's Luau plugin API. Unofficial and unaffiliated; the Basecamp mark
belongs to 37signals.

The plugin's own page, with usage, settings and IPC, is
[`basecamp/README.md`](basecamp/README.md).

## Install

Requires `basecamp` 0.9 or newer, `jq` and `xdg-open` on `PATH`. Sign in once
with `basecamp auth login`.

Clone anywhere, then register the clone as a plugin source:

```sh
git clone https://github.com/kjvdven/noctalia-basecamp.git
noctalia msg plugins source add local path "$PWD/noctalia-basecamp"
noctalia msg plugins enable kjvdven/basecamp
```

Going through `noctalia msg` rather than editing `settings.toml` by hand
matters: the moment the config declares a `[[plugins.source]]` of its own,
noctalia stops seeding the default `official` and `community` sources, and
hand-editing is an easy way to lose the plugins you already had.

Then add the **Basecamp** widget to a bar in Settings → Bar.

## Development

`basecamp/model.luau` holds all parsing, sorting and formatting and touches no
noctalia API, so it runs and tests standalone:

```sh
nix run nixpkgs#luau -- tests/model_test.luau   # model checks
noctalia plugins lint basecamp                  # manifest + settings cross-check
```

The three entries (`service.luau`, `bar.luau`, `panel.luau`) are file-watched
by the shell: save and the plugin hot-reloads. A manifest change needs
`plugins disable` + `plugins enable` to rebind settings.

For editor completion, drop a local copy of the API type definitions next to
`.luaurc` (gitignored, since the upstream repo ships no license):

```sh
git --git-dir=~/.local/state/noctalia/plugins/sources/official/repo/.git \
    show HEAD:noctalia.d.luau > noctalia.d.luau
```

`docs/PLAN.md` is the implementation plan and the record of what the port
changed and why.

## License

MIT. See [`LICENSE`](LICENSE) for the notice covering the 37signals-derived
assets.
