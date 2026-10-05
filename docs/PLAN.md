# Implementation plan — Basecamp notifications for Noctalia

A port of [`basecamp/omarchy-basecamp-plugin`](https://github.com/basecamp/omarchy-basecamp-plugin)
(Quickshell/QML, MIT) to a Noctalia v5 plugin, targeting submission to
[`noctalia-dev/community-plugins`](https://github.com/noctalia-dev/community-plugins).

## Context

The source plugin is an Omarchy bar plugin that shows notifications from every authorized
Basecamp account through the Basecamp CLI. Noctalia plugins are not QML but **Luau** with a
declarative `ui.*` tree, so this is not a file conversion: the logic (`Model.js`,
`Service.qml`) transliterates almost directly, while the UI (`Panel.qml`, ~850 lines of QML)
is rewritten from scratch.

Goal: feature parity with the original, publishable as a community plugin.

## Established facts

**Noctalia v5.0.0.** `plugin_api` levels: 13 `capture_keys` + `onKey`, 14 `[widget.actions]`,
15 `openSettings`, 19 `timeFormat`, 22 `require("./x.luau")`, 24 argv form of `runAsync`,
28 `panel.openContextMenu` (the highest shipped in v5.0.0). Levels 29 and 30 are unreleased and
must not be used.

**The full plugin docs are on disk**, shipped in the Noctalia derivation:
`/nix/store/cvg1bb23ifjhjgc0c4ws2adbnknr4xfj-source/docs/user/plugins/development/`
(`manifest.mdx`, `entries.mdx`, `declarative-ui.mdx`, `runtime-api.mdx`, `workflow.mdx`), plus
`docs/user/theming/palette.mdx` for the 16 colour roles. **`declarative-ui.mdx` is the prop
reference, not `noctalia.d.luau`** — props are typed `any` there. Glyphs are Tabler; 5957 names
in `share/noctalia/assets/fonts/tabler.json`.

**Reference implementations** (read with
`git --git-dir=~/.local/state/noctalia/plugins/sources/{community,official}/repo/.git show HEAD:<path>`):

| For | Plugin |
| --- | --- |
| The whole skeleton: service → state → count pill → scrollable list with click and dismiss | community `rss-notifier/` |
| Poll loop, generation guard, `onConfigChanged`, debug `onIpc` | community `github-prs/fetch.luau` |
| `capture_keys` semantics (Escape, printable keys), `onKey` debouncing | community `todo/panel.luau`, `procmon/panel.luau` |
| CLI-backed service, setup states, tab buttons, per-state SVG | community `tailscale/` |
| Official bar + panel + service example | official `umbriel-companion/` |
| Test harness shape and repo layout | `noctalia-case-convert` |

**Basecamp CLI 0.9.1.** Verified against a real account:

- `accounts list --json` → `{ok, data:[{id, name, href}]}` — **`id` is a JSON number**
  (`1000001`), not a string.
- `notifications list --json` → `{ok, data:{unreads?:[…], reads:[…], bubble_ups_count,
  scheduled_bubble_ups_count}}`. **`unreads` is omitted entirely when nothing is unread.**
  There is no `--limit`, so per-account capping is client-side. `--page` exists.
- Item keys: `id, title, readable_identifier, content_excerpt, creator{name,avatar_url},
  bucket_name, section, type, created_at, updated_at, app_url, participants[], unread_at,
  read_at`. `type` is **capitalised**: `Assignment, BoostReport, Bulletin, Chat, Comment,
  Event, Mention, Message, Reminder`. `section` ∈ `chats, inbox, pings`. `participants` and
  `named` can be `null`. **`readable_identifier` is an opaque base64 GID** — never usable as a
  title.
- `notifications read <id>… --account <id> --json` accepts **multiple ids** and resolves them
  against the page that was listed (we list page 1), so mark-read can be batched.
- `auth status --json` → `data.{authenticated, expired, expires_in, oauth_type, source}`.
- Exit codes: `0` ok, `2` API error with an envelope `{ok:false, error, code, retryable}` on
  **stdout**.
- `app_url` sometimes points at `https://3.basecampapi.com/` and must be rewritten to
  `https://app.basecamp.com/`.

**Runtime properties that shape the design:**

- Entries are isolated VMs. `noctalia.state` copies plain data and is shared across every
  monitor — that replaces the `ServiceHost.js` singleton.
- `runAsync` **always** invokes its callback (`timedOut = true` on expiry) and returns `false`
  synchronously if it could not spawn, so the `bash -c` probe wrapper from `Service.qml:301` is
  unnecessary. `commandExists` is a synchronous host call.
- Subprocesses cannot be cancelled, so in-flight callbacks are disowned with a generation
  counter.
- `ui.scroll` has **no** scroll-to-index (only `stickToBottom`, `scrollToBottomRev` and a
  read-only `onScroll`).
- `ui.image` has **no** colour prop, and no API returns a palette role as hex, so the SVG
  cannot be recoloured to match the theme. `ui.glyph` can.
- `ui.box` is a leaf and takes no children. `ui.row` has no `tooltip`; `ui.button` does.
- `wrap` on `ui.label` still exists in the v5.0.0 binary but has been dropped from the current
  `noctalia.d.luau` — use `maxLines` only.
- `[[service]]` entries cannot own settings (`validate-plugins.py:163-178`: only widget, panel,
  desktop_widget and launcher_provider can), so everything the poller needs is a root
  `[[setting]]`.
- `runInTerminal(cmd) -> boolean` means *launched* only: no exit code, no callback.
- `noctalia.processMatches(cb, …needles)` is the clean replacement for `flock`.

## Repo layout

```
noctalia-basecamp/
├── .gitignore                      # noctalia.d.luau (gitignored; upstream ships no licence)
├── .luaurc                         # nonstrict, as in noctalia-case-convert
├── .vscode/settings.json           # luau-lsp → noctalia.d.luau
├── LICENSE                         # MIT + a separate notice for the 37signals-derived SVG
├── README.md                       # repo README: what it is, install, dev loop, attribution
├── docs/PLAN.md                    # this document
├── docs/panel.png                  # screenshot for the repo README
├── basecamp/                       # ← becomes the PR directory in community-plugins
│   ├── plugin.toml
│   ├── model.luau                  # PURE logic, zero noctalia calls, runs under bare `luau`
│   ├── service.luau                # the only entry that shells out; poller + request handler
│   ├── bar.luau                    # logo + count; click / right / middle; tooltip
│   ├── panel.luau                  # list, tabs, account filter, keys, setup card
│   ├── assets/basecamp-light.svg   # source SVG, fill #fff — for dark themes
│   ├── assets/basecamp-dark.svg    # same geometry, fill #16161d — only if step 1 needs it
│   ├── translations/en.json
│   ├── README.md                   # store page; must pass validate-plugins.py
│   └── thumbnail.webp              # 16:9 WebP from assets.noctalia.dev/plugins/thumbnail-generator.html
└── tests/
    ├── fixtures/                   # real CLI output with names scrubbed, plus hand-written edge cases
    └── model_test.luau             # standalone
```

Two `require` spellings, both needed: the plugin uses `require("./model.luau")` (plugin_api ≥
22), the standalone test uses `require("../basecamp/model")` **without** the extension, because
the `luau` CLI rejects extensions in require paths. `noctalia-case-convert/tests/cases_test.luau:8`
does exactly this.

Do not commit `noctalia.d.luau`; fetch it with
`curl -O https://raw.githubusercontent.com/noctalia-dev/official-plugins/main/noctalia.d.luau`.

## `basecamp/plugin.toml`

```toml
id = "kjvdven/basecamp"
name = "Basecamp"
version = "1.0.0"
plugin_api = 24
author = "kjvdven"
license = "MIT"
dependencies = ["basecamp", "xdg-open"]
tags = ["bar", "panel", "service", "productivity", "indicator"]
icon = "campfire"
description = "Unread and recent notifications from every authorized Basecamp account, via the Basecamp CLI."

# Root settings: [[service]] cannot own any. Four, no more — every setting is
# code, a translation key, a lint rule and a README line.
[[setting]]  refresh_interval    int    default 600, min 60, max 3600, step 60
[[setting]]  per_account_limit   int    default 20,  min 5,  max 50, step 5
[[setting]]  mark_read_on_open   bool   default true
[[setting]]  default_tab         select "unread" | "previous"

[[service]]
id = "service"
entry = "service.luau"

[[widget]]
id = "bar"
entry = "bar.luau"
  [widget.actions]
  left = "panel-toggle kjvdven/basecamp:panel"   # remappable, hence not in onClick
  middle = "none"                                 # otherwise onMiddleClick never fires
  [[widget.setting]]  show_count  bool default true
  # icon_style ("logo" | "glyph") is added ONLY if the tint experiment (step 1)
  # fails. If it succeeds the SVG is tintable and the choice is pointless.

[[panel]]
id = "panel"
entry = "panel.luau"
width = 430
height = 620
placement = "attached"
position = "auto"
open_near_click = true
# Escape is deliberately absent: the host always reserves it to dismiss a panel.
# u / p / r are safe printable chords because this panel has no ui.input to claim them.
capture_keys = ["up", "down", "left", "right", "return", "u", "p", "r"]
```

`plugin_api = 24` is the lowest level that covers everything used; the argv form of `runAsync`
for the variadic mark-read is the upper bound. `openContextMenu` (28) is deliberately not used
in v1.

Rules that bite otherwise:

- `width`, `height`, `placement`, `position` and `open_near_click` are **automatically** exposed
  as user settings — do not declare them as `[[panel.setting]]`.
- `label_key` and `description_key` are mandatory and must resolve in `translations/en.json`;
  CI checks this.
- **Never change the `type` of an existing setting.** A stored value whose type no longer
  matches makes the shell reject *every* settings write. Introduce a new key instead.
- `description` ≤ 120 characters; `tags` only from the closed list in
  `community-plugins/README.md` (`notifications` is **not** in it).

## Architecture — three state channels

`state.set` marshals into every watching VM, so the item list must not ride on the channel the
bar watches. That is the only reason for a split; everything else shares one channel.

| Channel | Writer | Readers | Contents |
| --- | --- | --- | --- |
| `basecamp.summary` | service | bar + panel | status **plus the filters**; everything small |
| `basecamp.items` | service | panel **only** | normalized notifications |
| `basecamp.request` | bar + panel | service | `{seq, action, …payload}` |
| `basecamp.panelOpen` | panel | bar | one boolean; see below |

**Why the fourth channel exists.** Clicking the widget opens the panel directly under the
pointer, and the widget's tooltip stayed parked on top of it. The host already solves this for
built-in widgets — `Bar::suppressTooltipForOpenPanel` calls
`TooltipManager::suppressBarTooltipsForPanel` — and `[widget.actions] left = "panel-toggle …"`
does route through that path (`Widget::dispatchGesture` → `requestPanelToggle`). But the
suppression is only armed `if (PanelManager::instance().isOpenPanel(panelId))` evaluated
immediately after the toggle, and a *plugin* panel is not open yet at that instant: its script
has to load and run `onOpen` → `render()` first. Built-in panels are, which is why the network
widget behaves and this one did not.

Moving the left click into `onClick` is not the fix: `noctalia.togglePanel` skips the bar's panel
callback, and the source comment is explicit that this callback is what anchors the panel "at
this widget rather than at the compositor's focused output". So the panel reports itself instead
— `noctalia.state.set("basecamp.panelOpen", …)` in `onOpen` / `onClose` — and the bar calls
`barWidget.clearTooltip()` while it is true, restoring the rows on close. Measured latency
between the host's `opened` log line and the bar reacting: 4 ms, on both monitors.

```
summary = { probed, installed, supported, authenticated, cliVersion, probeError, refreshing,
            accounts = {{id, name, order}}, unreadTotal, unreadByAccount = {[id]=n},
            itemCount, updatedAtMs, error, actionStatus, setupRunning,
            accountId, tab }              -- filters belong here: small and shared
item    = { id, accountId, accountName, accountOrder, title, creator, excerpt, project,
            kind, tsSec, url, unread, unreadCount }
```

A separate `filters` channel was redundant: it is two fields that ride along on every publish
anyway, and one `publish()` is simpler than two channels that must stay in sync. Publish order:
`items` first (only when the list actually changed), `summary` last, so a watcher reacting to
`summary` already sees consistent `items`. `title` is capped at 200 bytes and `excerpt` at 240;
`readable_sgid`, `attachable_sgid`, `subscription_url`, the whole `creator` object and
`participants` are dropped after normalization.

Requests carry `seq = noctalia.nowMs()`; the service keeps `handledSeq` and ignores anything
`<= handledSeq`. That covers both two identical tables in a row and two racing panels.

| action | payload | behaviour |
| --- | --- | --- |
| `refresh` | `{mode}` | `"full"` forces a run; `"stale"` runs only if the data is older than the interval (panel `onOpen`); `"probe"` runs only the two probe calls (setup retry) |
| `mark_read` | `{accountId, ids}` | optimistic flip + queue |
| `open` | `{accountId, id}` | `xdg-open` the url, then `mark_read` if unread and `mark_read_on_open` |
| `set_filters` | `{accountId?, tab?}` | validate against the live account list, then publish |
| `run_setup` | — | `runInTerminal`, gated on `setupRunning` |

One `refresh(mode)` instead of three actions: all three shared the entire chain and differed
only in their start condition and stop point.

**Shared vs per-instance.** Shared: counts, accounts, items, errors, probe flags,
`setupRunning`, account filter, tab. Per-VM module locals: the panel's `selectedIndex`,
`cursorActive`, `hoveredKey`, `nowSec`, `phraseIndex`, and the bar's cache. The *what* is shared
(the source README promises "shares unread state, account filter, and unread/previous tab
across every monitor"), the *cursor position* is not — two panels must not fight over one
index. Per-VM locals give that isolation for free.

Two things that fail silently otherwise:

1. `panel.onOpen` must call `state.get()` — `watch()` alone misses everything published before
   the panel was first created.
2. The service **must** define `onConfigChanged()`, or the host restarts the whole service VM
   on every settings edit and all timers and caches are lost.

## `model.luau` — the pure module

No `noctalia.*`, no `ui.*`; only `os.date` / `os.time`, which are available in plugin VMs.

```
text          cleanText, truncate, concise
parsing       parseEnvelope, parseCliVersion, parseAccounts, parseNotifications,
              normalizeAppUrl, parseIso8601, idToString
collections   sortNotifications, filterNotifications, unreadCount, unreadByAccount,
              markReadLocally, enqueueRead, accountOptions, cycleAccount
presentation  typeGlyph, typeColorRole, badgeText, relativeTime, metaLine, setupPlan
```

Places where a literal transliteration of `Model.js` would be **wrong**:

- **`cleanText`** — JS regex flags do not exist in Lua patterns. The order stays sacred: decode
  entities, **then** strip tags, with `&amp;` decoded last, so double-encoded markup reforms as
  inert text instead of live tags. This is the security property the source repo tests
  explicitly (`tests/model.test.js:216-225`).
- **Numeric ids** — `idToString` uses `string.format("%d", v)` for integral numbers, so
  `1e+06` can never reach an `--account` argument.
- **Unread detection** — `Model.js:137` infers unread from the section name alone. Correct for
  this CLI, but a single point of failure. OR it with the item's own truth:
  `unread = sectionSaysUnread or (read_at == nil or read_at == "")`.
- **Title fallback** — never `readable_identifier` (opaque base64). Fall back to `bucket_name`,
  then a translated `"Basecamp notification"`.
- **Pings** — when `section == "pings"` and `named ~= true`, the title is
  `"Ping with {names}"` built from `participants[].name`. `model.pingNames(item)` returns the
  joined names and the *caller* does `noctalia.tr("ping.title", { names = … })`, so the format
  string stays translatable.
- **Type map** — lowercase before lookup. The Nerd Font code points from `Model.js:262-274` are
  dropped; Noctalia takes Tabler *names*:

  | kind | glyph | role | | kind | glyph | role |
  | --- | --- | --- | --- | --- | --- | --- |
  | mention | `at` | `error` | | bulletin | `speakerphone` | `secondary` |
  | comment | `message` | `primary` | | document / message | `file-text` | `on_surface_variant` |
  | chat | `messages` | `primary` | | hill | `chart-line` | `on_surface_variant` |
  | completion | `check` | `on_surface_variant` | | boostreport | `rocket` | `tertiary` |
  | event / reminder | `calendar-event` | `secondary` | | assignment | `checkbox` | `secondary` |
  | *default* | `bell` | `on_surface` | | | | |

- **`relativeTime`** — takes `tzOffsetSec` and `use24h` explicitly so tests are deterministic.
  `civilFromEpoch` is the standard days-from-civil algorithm; `parseIso8601` handles `Z`,
  `±HH:MM` and fractional seconds. Callers supply
  `tzOffsetSec = os.time(os.date("*t", now)) - os.time(os.date("!*t", now))` and
  `use24h = noctalia.timeFormat():find("%%H") ~= nil`.
- **`setupPlan`** — everything Omarchy-specific is stripped (`setupLockPath`,
  `setupLaunchCommand`, flock, `omarchy-shell`, `omarchy-pkg-add`, `omarchy update`). What
  remains is the priority order (missing CLI beats outdated beats signed out) and, per state,
  `{kind, titleKey, buttonKey, command, fix, docUrl}`.

## `service.luau` — the state machine

**Probe** (two argv calls, no shell):

```
if not commandExists("basecamp") -> installed = false; probed = true; publish; stop
runAsync({"basecamp","version"}, …, 5000)
  -> model.parseCliVersion; supported = >= 0.9.0
runAsync({"basecamp","auth","status","--json"}, …, 8000)
  -> authenticated = data.authenticated == true and data.expired ~= true
```

An **unreadable** probe sets `authenticated = true` plus `probeError = true`, carried over from
`Service.qml:166-176`: telling the user to log in cannot fix a garbled response, so the error
line wins over the setup card, and `probeError` keeps the panel's retry alive. Including
`expired` is a small upgrade the CLI now supports — an expired token is functionally signed
out, where the original would have failed every account fetch instead.

**Accounts, then sequentially per account.** `fetchNext()` recurses from inside the callback;
the `{fetchAccounts_, fetchIndex, fetched, partialErrors}` quad replaces the six properties of
`Service.qml:37-50`. Per-account failures go into `partialErrors` (joined with `" · "`), but
`env.code == "auth_required"` aborts the whole run: credentials are shared, so every remaining
account would fail identically. Sequential rather than parallel, because N accounts against the
same rate-limited API buys nothing and the auth short-circuit only makes sense in a chain.

**Overlap guard.** `refreshing` permits one chain; `generation` is incremented on every start
and each callback closes over its own `gen` — the only way to disown non-cancellable
subprocesses. Every terminal path sets `refreshing = false` and publishes, plus a safety net in
`update()` that clears `refreshing` after 120 s.

**Mark-read** — three deliberate deviations from `Service.qml:219-289`:

1. **Batching.** One argv per account per drain (`read id1 id2 … --account n --json`) instead
   of one process per notification.
2. **No unconditional re-refresh after 1200 ms.** A `read` that exits 0 has committed
   server-side, so the optimistic flip is already true; a full refresh costs `1 + N` CLI calls
   for nothing. Resync only on **failure** — and then drop the queue, because the flip may be a
   lie.
3. `actionStatus` decays in the **panel**, not the service, because the panel is the thing with
   second ticks. The service reports; the panel stops showing it after ~2.2 s. A service whose
   tick is 600 s has no mechanism for a sub-interval one-shot other than
   `runAsync({"sleep",…})`, which is exactly what this avoids.

**Polling** — `setUpdateInterval(intervalMs())` plus `update() -> refresh("full")`, re-armed in
`onConfigChanged`. At start, `publish()` first and then a refresh, because the host timer does
not fire immediately. After a hot reload, rehydrate from `state.get` first. `onConfigChanged`
re-reads every config-derived value but only refetches when `per_account_limit` changed (a
changed interval only needs the new tick rate). `onEnable()` forces a refresh.

**Opening URLs** also happens in the service (`runAsync({"xdg-open", url})`, fire-and-forget),
so "only the service shells out" stays true. Hence `xdg-open` in `dependencies`.

## `bar.luau`

**Step 1 is answered — measured on niri, Noctalia v5.0.0, `grim` screenshots of the live bar:**

| Call | Result |
| --- | --- |
| `barWidget.setImage("assets/basecamp-light.svg", false, 16, 16)` | Renders, and **does not tint**. The `u_tint` uniforms are not reachable from the plugin API |
| `barWidget.setColor(role)` | Colours the **text**, and works alongside `setImage`. Verified by flipping `error` → `primary` and seeing red become blue |
| `barWidget.setGlyphColor(role)` | Redundant here — removing it changed nothing |

So the widget is **imperative, not declarative**: no `barWidget.render()` tree, no tinted
capsule wrapper, and no `icon_style` setting. The whole widget is four calls.

```lua
local unread = unreadForSelection()
barWidget.setImage(noctalia.isDarkMode() and "assets/basecamp-light.svg"
                                          or "assets/basecamp-dark.svg", false, 16, 16)
barWidget.setText(unread > 0 and tostring(unread) or "")
barWidget.setColor(unread > 0 and "error" or "on_surface")
barWidget.setTooltip(tooltipRows())
```

- Two SVG variants are still required, because the image cannot be tinted and a white logo is
  invisible on a light theme. `noctalia.isDarkMode()` picks one, as `syncthing/bar.luau` does.
- The unread signal is carried entirely by the coloured count. That is a plainer design than
  the capsule this plan originally proposed, and it needs no `ui.*` tree at all.
- `unreadForSelection()`: `accountId == ""` → `unreadTotal`, otherwise
  `unreadByAccount[accountId]` — the original colours on the selected account.
- Vertical bar: `barWidget.isVertical()` still matters, but only to suppress the count; the host
  stacks image and text itself.
- Tooltip as `TooltipRow`s (unread count via `noctalia.trp`, account, last updated), replaced by
  the refresh status or the setup headline.
- The widget stays **always visible** — hiding it makes the setup card unreachable.
- `onRightClick` / `onMiddleClick` → refresh. No `onClick`: left click comes from
  `[widget.actions]`.

One consequence worth noting: because the logo never changes colour, "signed out" cannot be
shown on the image either. It goes in the tooltip and in the panel's setup card, which is where
a user can act on it anyway.

## `panel.luau`

```
ui.column{ flexGrow=1, gap=10, padding=12 }
  header        logo + "Basecamp" + status line + refresh + settings + close
  ui.separator
  setupCard     only on a setup problem (replaces filter, tabs and list)
  accountFilter omitted at ≤ 1 account
  tabs          "New for you" / "Previous notifications"
  body          ui.scroll{ key = "bc-list", flexGrow=1, gap=6 } | emptyState
```

**Status line** in the order of `Panel.qml:102-107`: `actionStatus` (while fresh) → `error` (in
the `error` role) → a rotating `loading.*` phrase while refreshing → `status.designed_by`.

**Account filter without a popup.** At ≤ 4 options, a chip row of `ui.button`s ("All accounts"
first, `" (n)"` appended for accounts with unreads, plus an `error` dot on the All chip when
another account has unreads). Above that, a single cycler button: left click forward,
`onRightClick` backward. **Deliberately not `ui.select`** — `Panel.qml:496-500` documents the
bug: the dropdown trigger keeps focus after closing and eats Enter/Space/Down. QML fixed that
with `forceActiveFocus()`, and Noctalia exposes no focus API at all, so a `ui.select` here would
be a keyboard trap with no escape hatch. Buttons open no popup and never disturb `capture_keys`.
`panel.openContextMenu` (API 28) is the natural upgrade for many-account users in v1.1.

**Row** (`key = accountId .. ":" .. id`, stable across renders): the type badge is a 24 px
`ui.row` circle — not `ui.box`, which takes no children — holding a `ui.glyph`; then
`ui.column{flexGrow=1}` with the title (`maxLines=1`, `semibold` when unread), the excerpt
(`fontSize=11, maxLines=2`) and the meta line (`fontSize=10, color="primary"`); then the unread
badge as a `ui.button` that flips from count to `x` on hover and sends `mark_read` on click
without opening. Selection: `fill = "primary/0.18"`. `onRowHover` clears `cursorActive` so the
mouse takes over from the keyboard cursor (the `PointerMoveGate` idea from
`Panel.qml:238-241`). Use `maxLines` only, never `wrap`.

**Keys** — `onKey(chord, pressed)`, acting only on `pressed`. `down`/`up` move with wrap (the
first press sets `cursorActive` and selects row 1, as in `Panel.qml:193-200`), `return` opens,
`left`/`right` cycle accounts, `u`/`p` switch tab, `r` refreshes. Single letters are debounced
with a held-key guard, because `onKey` delivers auto-repeat — otherwise one press of `r` fires
three refreshes. Escape is not declared; the host always reserves it.

**Keeping the selection in view: we don't.** There is no scroll-to-index, and the known
workaround — rendering a ~7-row window in keyboard mode and sliding it
(`procmon/panel.luau:36-39`) — costs ~60 lines, a `ROWS_PER_PAGE` constant that cannot be
derived from any API, and one visible jump when switching modes. **Deliberate choice: render
everything, highlight the selected row, and accept that the cursor can move out of view.**

```
ui.scroll{ key = "bc-list", flexGrow = 1, gap = 6 } → all filtered rows
row.fill = selected and "primary/0.18" or nil
```

This works because the Unread tab — where the arrow keys get used — is in practice shorter than
one page; that is the definition of "unread". In a 50-item Previous tab the selection can drop
below the edge, and that is the price. Windowing can be added later without rewriting anything:
`selectedIndex` and the row renderer stay identical, a slice is simply inserted. What does
matter: the `ui.scroll` always keeps the same `key = "bc-list"`, because a `flexGrow` scroll
that changes identity gets stuck at the wrong height.

**One timer, and not one render per tick.** `panel.setWantsSecondTicks(true)` in `onOpen`, off
in `onClose`, replaces all four QML `Timer`s: the 3 s setup retry, the phrase rotation, the
relative-time refresh and the `actionStatus` decay. The retry sends `refresh{mode="probe"}` —
two CLI calls every 3 s instead of a full sweep — and the probe continues to `fetchAccounts` on
its own once auth succeeds.

But `update()` must **not** call `render()` blindly. A 40-row tree is ~350 tables; rebuilding it
every second while the labels only change every minute is pure waste. So a dirty check with
four causes:

```lua
function update()
  local now = os.time()
  local dirty = false
  if now // 60 ~= lastMinute then lastMinute = now // 60; nowSec = now; dirty = true end
  if needsSetup or summary.probeError then
    retryTicks += 1
    if retryTicks >= 3 then retryTicks = 0; request("refresh", { mode = "probe" }) end
  end
  if summary.refreshing and not needsSetup then
    phraseTicks += 1
    if phraseTicks >= 3 then phraseTicks = 0; phraseIndex += 1; dirty = true end
  end
  if actionStatusShown and noctalia.nowMs() - actionStatusAtMs > 2200 then
    actionStatusShown = false; dirty = true
  end
  if dirty then render() end
end
```

Relative times are `"9:41am"` or `"Sep 3"`, which change on the minute boundary, not every
second. Result: zero renders per second at rest, one per minute, and one per three seconds
during a refresh. `state.watch` still renders immediately, because there the data really changed.

**Setup flow without Omarchy:**

| State | Card | Button |
| --- | --- | --- |
| CLI missing | `setup.missing_title` + "or run: `<cmd>`" with a copy button | `setup.docs` → `xdg-open` the CLI's install instructions. **No terminal** |
| CLI < 0.9 | `setup.outdated_title` | same: open the docs |
| Signed out / expired | `setup.signin_title` | `run_setup` → `runInTerminal("basecamp auth login")` |

Install and update buttons deliberately do not shell out: `omarchy-pkg-add` and `omarchy update`
are Omarchy-specific and there is no portable equivalent across Arch, NixOS and Fedora — guessing
(`paru -S …`) fails on most machines. The copy line uses
`noctalia.copyToClipboard(cmd, "text/plain")` rather than shelling out to `wl-copy`.

**Blocking a second login** (replacing the flock lockfile): `setupRunning` lives in the service,
set before `runInTerminal`, cleared when (a) `authenticated` becomes true, (b)
`processMatches(cb, "basecamp", "auth", "login")` finds no live process, or (c) after 5 minutes
as a stale guard, so a closed terminal never locks the user out permanently. `processMatches` is
a better lockfile: it observes the real login process rather than a file a killed terminal can
leave behind. The flag sits in the service, so the button is disabled on every monitor at once —
exactly the property the lockfile provided.

**Avatars: not in v1.** `creator.avatar_url` exists, but `ui.image` only takes local files, so
each avatar means a download into `pluginDataDir`, a cache key, an eviction policy, a re-render
per arrival, and a privacy footprint — the plugin currently makes zero network calls of its own.
For 20–60 rows that is a lot of complexity to replace a 24 px circle that already encodes
something more useful: the notification type. The original makes the same call.

## `translations/en.json`

One nested object; every key segment lowercase and dot-free. Groups: `settings.*`, `title`,
`tab.*`, `account.*`, `empty.*`, `error.*`, `status.*`, `setup.*`, `tooltip.*`, `loading.*` (the
six campfire phrases from `Panel.qml:90-97`), `ping.title`, `notify.*`, plus `unread_count` in
the `{one, other}` + `{count}` shape for `noctalia.trp`. **Nothing user-visible stays a bare Lua
string.** Only `en.json` — other languages go through i18n.noctalia.dev.

## Tests

`tests/model_test.luau` in the shape of `noctalia-case-convert/tests/cases_test.luau`
(`expect(label, actual, wanted)`, counters, non-zero exit). Port all 23 assertions from
`tests/model.test.js`, plus what this port adds:

- `parseCliVersion`: `0.8.1` unsupported, `0.9.0` supported, `0.9.0-rc.1` unsupported,
  `0.9.1-rc.1` supported, `0.9.1+linux.x86-64`, garbage → `ok = false`
- `parseAccounts`: **numeric** ids stringified, missing `id` skipped
- `parseNotifications`: unread from the `unreads` section, unread from an empty `read_at` in a
  `reads` section, a **missing `unreads` key**, limit slicing, unread-first-then-newest,
  `readable_identifier` never used as a title
- `cleanText`: the full XSS-shaped table from `tests/model.test.js:216-225`
- `relativeTime` / `parseIso8601`: 12h and 24h, day and year boundaries, DST offsets, `0` → `""`
- `markReadLocally` (does not mutate its input, `nil` when nothing matched), `enqueueRead`
  (coalesces per account), `sortNotifications`, the filters, `setupPlan` priority, and
  `truncate` / `concise` (never splitting a UTF-8 sequence)

Fixtures: `basecamp notifications list --json > tests/fixtures/notifications.json` and
`accounts list --json > tests/fixtures/accounts.json` with names scrubbed, plus hand-written
`unreads` and `{ok:false, code:"auth_required"}` fixtures — a signed-in machine cannot produce
those.

Run: `nix run nixpkgs#luau -- tests/model_test.luau`.

## Memory and hot paths

The state is not the problem; the CLI output and the render rate are.

**Where the memory actually is.** One raw notification item is 1.5–2.5 KB: the `creator` object
drags along `bio`, `avatar_url`, six `can_*` permissions and an `attachable_sgid`, plus
`readable_sgid`, `bookmark_url` and `subscription_url` on the item itself. At 50 items (the CLI
has no `--limit`) that is 75–125 KB of stdout per account, and a decoded Lua table is another
3–5× on top — a peak of roughly 0.5 MB per account. The normalized item is 13 fields with a
capped title and excerpt: ~600 bytes. At 20 items × 3 accounts the published list is ~36 KB.
**That is a 95% reduction, and producing it is the job of `model.normalizeItem`** — not just
tidiness.

Five rules follow:

1. **Sequential fetching keeps one raw response alive at a time.** That was already the choice
   for the `auth_required` short-circuit, but it is also the memory argument: parallel would be
   N × 0.5 MB at once.
2. **Hold nothing raw.** `parseNotifications` returns normalized items only; the service keeps
   `fetched` and never the decoded JSON. No `rawByAccount` cache "for later".
3. **Check `stdoutTruncated`.** `runAsync` can truncate; parsing half a JSON document produces a
   misleading error instead of "response too large".
4. **Cap in `model`, not in the panel.** `per_account_limit` cuts before publishing, so 50 items
   are never marshalled into every panel VM when the setting says 20.
5. **Publish `items` only when the list changed.** Otherwise every probe retry — which runs every
   3 seconds during the setup flow — re-marshals the whole list into every open panel. A cheap
   signature (count + `unreadTotal` + first and last id) is enough. `summary` always publishes,
   because it is small, which is precisely why it is separate from `items`.

**Where the CPU is**: `render()`. A 40-row tree is ~350 table allocations, so it may only run on
a real change — the dirty check in `panel.luau` above. At rest: zero renders per second.

What explicitly gets no optimization: recomputing `unreadByAccount` on every publish is O(n)
over ≤60 items, and `sortNotifications` likewise. That is noise; maintaining it incrementally
would be more code and more bugs for immeasurable gain.

## Deliberately not in v1

Every line below is a feature the original has, or one that offered itself, cut because the cost
does not justify the gain. They are listed so the decision stays visible and does not creep back
in by accident.

| Cut | Why |
| --- | --- |
| A `notify_on_new` setting | Needs a `prevUnreadIds` set living across refreshes, for a feature that is off by default. Noctalia already has notifications; this is v1.1 |
| A `hide_when_zero` setting | Hides the only entry point to the setup card |
| An `unread_color` setting | A `color` setting yields hex, not a palette role — theme breakage in exchange for a knob. The `error` role is right hardcoded |
| An `icon_style` (logo/glyph) setting, and the tinted capsule behind the logo | Both existed only to work around an untintable logo. Step 1 showed `setColor` colours the count, which carries the signal on its own |
| `panel.openContextMenu` for accounts | Would push `plugin_api` to 28 for a case (> 4 accounts) the chip row already covers |
| Avatars | Download, cache, eviction and a re-render per arrival, and the plugin currently makes zero network calls of its own |
| A `demo/` mode with a fake CLI binary | Omarchy-specific tooling; the model tests cover the same logic |
| Crossfades and a spinning refresh icon | No tween primitives; the source repo's `refresh-*.svg` become unnecessary |
| Window rendering to keep the selection in view | ~60 lines plus a non-derivable page size, for a case the Unread tab rarely reaches. Addable later without a rewrite |

## Implementation order — a gate at every step

1. ~~**The tint experiment first.**~~ **Done.** `setImage` does not tint; `setColor` colours the
   text and composes with it. The widget is imperative and four calls long; the `icon_style`
   setting and the capsule are dropped, the two SVG variants stay. See `bar.luau` above.
   Verification method worth reusing for every later step: `grim -g "0,0 700x56" out.png` grabs
   the live bar, and `.luau` edits hot-reload (`[plugin-widget] hot reload: reloaded 'bar.luau'`
   in `~/.cache/noctalia/noctalia.log`), so a change can be seen in about two seconds without
   restarting the shell.
2. ~~**Skeleton, no logic.**~~ **Done.** `.luaurc`, `.vscode/settings.json`, `.gitignore`,
   `LICENSE` (with the 37signals notice), `plugin.toml` with all four settings and all three
   entries, `translations/en.json`, both SVG variants, the finished `bar.luau`, and skeleton
   `service.luau` / `panel.luau`. Both READMEs are deferred to step 10, where their content is
   settled. Verified: `noctalia plugins lint basecamp` clean, the shell loads 3 entries, the bar
   shows the logo with no count at zero unread, and the panel opens and renders its header.

   **Two dev-loop facts worth keeping** (they cost time to find):

   - **A manifest change needs `plugins disable` + `plugins enable`, not just `config-reload`.**
     After adding settings to a manifest whose plugin was already enabled, the shell keeps the
     old binding: `getConfig` returns `nil` for every key and the log says
     `read undeclared setting '<key>'` even though `plugins lint` is clean. Disable and re-enable
     rebinds it. `.luau` edits do hot-reload on their own.
   - **`panel-toggle` over IPC ignores `open_near_click`.** With no pointer event the panel falls
     back to `position = "auto"`, which put it at the right-hand side of the focused output, not
     under the widget. Screenshot the whole output before concluding a panel renders nothing.
3. ~~**`model.luau` and `tests/model_test.luau`, together.**~~ **Done.** `217/217 checks passed`.
   Fixtures live in `tests/fixtures/cli.luau` as Lua tables rather than JSON, because
   `model.luau` deliberately cannot call `noctalia.json` — the service decodes and hands tables
   in, which is what keeps the module runnable under a bare `luau`. `require("./model.luau")`
   verified inside the plugin runtime too, and the host file-watches the required module, so it
   hot-reloads with its entry.

   **Four things the fixtures pinned that the plan had wrong or unstated:**

   - **Keys vary per item.** Unread items carry `unread_count` and no `read_at`; plenty of read
     items have no `content_excerpt` or `participants` key at all. Every field access is
     nil-safe, and the fixture keeps items with holes in them for that reason.
   - **Excerpts contain real newlines**, not the literal `\n` two-character sequences
     `Model.js` filtered for. Both forms have to collapse.
   - **`id = 0` needs an explicit check.** `Model.js` dropped it for free because `0` is falsy
     in JS; in Lua it is truthy, so without the check it would reach the CLI as `--account 0`.
   - **The ellipsis is three bytes.** `truncate` caps bytes and appends `…` (U+2026), so a
     240-byte cap yields a 243-byte string. Pinned in the test, since a later "tighten the cap"
     edit is exactly where that goes wrong.

   Also worth knowing for the next test file: **the `luau` CLI has no `os.exit`.** Signal
   failure with `error(msg, 0)`, which still exits non-zero — the same trick
   `noctalia-case-convert/tests/cases_test.luau` uses.
4. ~~**`service.luau`.**~~ **Done.** Probe → accounts → sequential notifications → publish, with
   the generation guard, the `auth_required` short-circuit, per-account partial errors and the
   watchdog. Verified against the live account:

   ```
   probed=true installed=true supported=true authed=true cli=0.9.1
   accounts=1 items=20 unread=4 refreshing=false error=""
   ```

   The `dump` event on `onIpc` is what makes that readable —
   `noctalia msg plugin kjvdven/basecamp:service all dump` logs one line, which is as close to a
   queryable API as a plugin gets (`onIpc` is one-way with no return value). `refresh` over the
   same channel moved `updatedAtMs` forward, so the request path works too.

5. ~~**`bar.luau`.**~~ **Done.** The logo with a red `4` beside it, identical on both monitors
   from the single poller. Screenshot check: `grim -g "0,0 500x52"` and
   `grim -g "2560,0 600x60"`.

   Still needs a human, because it cannot be reached without changing the user's config or
   moving a pointer: the tooltip rows on hover, right/middle click to refresh, a vertical bar,
   and a light theme (where `basecamp-dark.svg` should take over).
6. ~~**`panel.luau` part 1 — read only.**~~ **Done.** Header with status line, segmented tabs,
   account filter, the list with type badges and meta lines, empty states, second ticks with the
   dirty check. Verified against the live account: four unread rows, ping titles resolving to
   "Ping with <name>", excerpts cleaned and elided, "Updated 17:44".

   **Tabs are a hand-built segmented control.** Noctalia's own panels have a real one —
   `ui::segmented`, used by the weather tab's Daily / Hourly picker, with `compact`,
   `equalSegmentWidths` and a `surfaceRole` track. Plugins do not get it: the plugin `ui.*`
   vocabulary is exactly 19 constructors (`src/scripting/ui_prelude.h`) and segmented is not one
   of them. So `segmented()` in `panel.luau` reproduces it from a filled `ui.row` holding
   `flexGrow = 1` buttons, using the shell's own numbers (`Style::spaceXs` 4, `radiusMd` 6,
   compact segments pad 4 vertical / 8 horizontal). The track is `surface_variant/0.6`, **not**
   `surface`: the panel background is already surface, so a surface track is invisible and the
   segments look like they float. The same helper draws the account filter, so both rows match.

   **Three more things found by running it:**

   - **Hot-reloading an open panel loses `isOpen`.** The module state resets and the host does
     not replay `onOpen`, so the panel sits there rendering nothing until it is toggled twice.
     The `panelOpen` channel already knows the answer, so the bottom of `panel.luau` recovers
     from it — which is what makes editing a live panel iterative at all.
   - **Count accounts, not options, when hiding the account filter.** `accountOptions()` always
     includes the "All accounts" entry, so `#options < 2` never hides anything and a
     single-account user got two chips showing the same number.
   - **A panel dismisses on focus loss**, so `panel-toggle` followed by a slow screenshot
     catches an empty desktop. Toggle and grab within ~1.5 s.

   `tab` and `account` were added to the service's `onIpc` alongside `refresh` and `dump`. That
   started as a way to drive the tabs without a pointer, and is worth keeping: it makes the
   filters bindable to a key without opening the panel.
7. **`panel.luau` part 2 — actions.** Written: text column click → `open` (xdg-open plus
   mark-read when `mark_read_on_open`), badge hover → `x`, badge click → `mark_read`, with the
   optimistic flip and the batching queue in the service. **Needs a human to confirm**, because
   every path mutates real Basecamp data and there is no pointer available here.

   Two shapes were corrected against the original's screenshot:

   - **The account filter is a `ui.select`**, as the original has, not the chip row this plan
     first proposed. The concern stands and is written down at the call site: Panel.qml:496-500
     documents a QML bug where the dropdown trigger kept focus after closing and swallowed
     Enter/Space/Down, repaired there with `forceActiveFocus()`, which has no equivalent here.
     Step 8 is where that gets tested; `onCycleAccountForward` is already written as the
     fallback.
   - **Tabs are small text pills, not a full-width segmented track.** The original's are compact
     and left-aligned with a pill on the active one, so: `variant = "ghost"` plus `selected`, no
     `flexGrow`, a trailing spacer. The enclosing `surface_variant` track is gone.

   And one API limit worth recording: **`ui.button` has no `radius`**, so a badge built from a
   button stays a wide rectangle where the original has a 20 px circle. The unread badge is
   therefore a `ui.row` with `radius = 10` — a row gives radius, fill, `onClick` and `onHover`,
   which is the whole requirement. `tooltip` is the one thing lost, and the hover-to-`x` flip
   already communicates what the badge does.

   The click target is the **text column, not the whole row**, so clicking the badge cannot also
   open the notification. rss-notifier settled on the same split: two adjacent actions need
   disjoint hit areas.
8. **`panel.luau` part 3 — keys.** `onKey`, the held-key debounce for single letters,
   `selectedIndex` with wrap, highlighting the selected row.
   → `↑ ↓` walk the list and wrap at the ends; Enter opens the selected row; `← →` cycle
   accounts; `u`/`p` switch tab; `r` refreshes **once** when held down (that is what the
   debounce is for); Escape still dismisses the panel.
9. **Setup flow.** The card, `run_setup`, the `processMatches` guard, the probe retry, the copy
   button.
   → force all three states (point the binary elsewhere; stub `parseCliVersion` with `0.8.1`;
   stub `authenticated = false`). Check: one terminal, a second click ignored while
   `setupRunning`, killing the terminal re-enables the button within one retry tick, and a
   successful login clears the card without a manual refresh.
10. **Polish and submission.** `mark_read_on_open`, `default_tab`, the loading phrases,
    `thumbnail.webp` (16:9), `docs/panel.png`, both READMEs.
    → lint clean, tests clean, and the **real CI validator** locally:
    ```sh
    python3 <(git --git-dir=~/.local/state/noctalia/plugins/sources/community/repo/.git \
              show HEAD:.github/workflows/scripts/validate-plugins.py) <staging-checkout>
    ```
    That enforces the README sections, the backticked ids (`kjvdven/basecamp`, `bar`, `panel`,
    `service`), the literal line `noctalia msg panel-toggle kjvdven/basecamp:panel`, the
    backticked `basecamp` and `xdg-open` under `## Requirements`, `## Settings`, the no-raw-HTML
    rule and the thumbnail dimensions.

## Change after step 7: one list with Load more, no tabs

The Unread / Previous tabs and `default_tab` went unused and were replaced by a single list
(unread first, then read, both newest first) with a **Load more** button. The panel reveals
`PAGE_SIZE` (15) rows per click from what is held; once that runs out it sends `load_more` and
the service fetches `--page N` for every account in scope, deduplicating by `accountId:id`
because every page repeats the unread section (verified live: `unreads` = 4 on pages 1 and 2,
`reads` = 50 per page). `per_account_limit` was removed with it: trimming page 1 and then
fetching page 2 would skip the trimmed items for good. A full refresh still lists page 1 only
and resets the loaded pages; `u` / `p` left `capture_keys` with the tabs.

Found while testing: every notifications callback had been dying on Noctalia's 25 ms per-callback
CPU budget (`script_runtime.cpp` `kCallBudget`), on every refresh. Measured inside the host via
`state.set` breadcrumbs (log lines from a dying callback are lost): decoding the 158 KB page takes
3 ms, `cleanText` on a 305-char excerpt 0.5 ms, one `normalizeItem` ~0.8 ms, and a bare
100k-iteration `for` loop does not finish in 22 ms where standalone `luau` needs 1.1 ms. The host
VM is 20x+ slower than the CLI, build type release, so one page of 54 items can never be
normalized in one callback. Fix: the notifications call now runs through `runStream` with a `jq`
filter (a new dependency, as in ten other community plugins) that emits a header line, one slim
`{unread, item}` line per notification and, via the shell, an `{end}` sentinel; every line is its
own callback with its own budget. `runStream` has no exit signal, so the refresh watchdog is
what frees the spinner if basecamp hangs. `model.parseNotifications` went with it: the section
walk lives in the jq filter now, and the tests drive `normalizeItem` directly per section.

## Opening a notification: the browser will not take focus

Found by running it: clicking a row marked the notification read but the browser opened in the
background. Not a bug in the click path — a gap in the plugin API.

The shell itself opens URLs through `net::openInBrowser`, which does this:

```cpp
return process::runAsync(std::vector<std::string>{"xdg-open", url}, activationToken);
```

That token comes from `WaylandConnection::requestActivationToken(surface)` and is passed to the
child as `XDG_ACTIVATION_TOKEN` and `DESKTOP_STARTUP_ID` (`process.cpp:636`). It is the
compositor's permission to raise the new window. **Plugins cannot get one**: there is no
activation token anywhere in `src/scripting/`, and no `noctalia msg` verb that opens a URL. So
`xdg-open` from a plugin starts the browser with no focus permission, and a strict compositor
(niri) leaves it in the background where a lenient one (Hyprland — hence the Omarchy original
behaving correctly) raises it anyway.

Rather than hard-code a compositor-specific incantation, the command is a setting:

| Setting | `open_command`, default `xdg-open {url}` |
| --- | --- |
| Why `{url}` | Substituted into one argv token. The command is **exec'd directly, never through a shell**, so a URL can never become shell code and no quoting question arises. The cost is no pipes or `&&`; point it at a script for that. |
| Gotcha | `%` is the escape character in a gsub *replacement*, and URLs contain `%`. `safeUrl` doubles them, or `%2F` would be read as a capture reference. |
| Fixes it on niri + Brave | `brave --new-window {url}` — a new window lands on the active workspace, where `xdg-open` only adds a tab to an existing window sitting on another one. |

Worth raising upstream: `noctalia.openUrl(url)` wrapping `net::openInBrowser` would close this
gap for every plugin, and it is the one thing here that a plugin genuinely cannot do for itself.

## QML features with no Noctalia equivalent

| Original | Replacement |
| --- | --- |
| `Qt.openUrlExternally` | A configurable `open_command` (default `xdg-open {url}`) run from the service as argv. See "Opening a notification" below — the browser will not take focus |
| `panelFlick.contentY = …` (scroll to row) | No scroll-to-index. The selection is highlighted, not scrolled into view |
| `flock` + `omarchy-shell … setupFinished` | `setupRunning` + `processMatches("basecamp","auth","login")` + a 5-minute stale guard + probe polling |
| `omarchy-launch-floating-terminal-with-presentation` | `runInTerminal` (no presentation, no exit status) |
| `omarchy-pkg-add` / `omarchy update` | Not portable. Open the install docs and offer a copyable command |
| The `bash -c` probe wrapper | Unnecessary: `commandExists` is synchronous and `runAsync` always calls back |
| `execDetached([wl-copy])` | `noctalia.copyToClipboard(text, "text/plain")` |
| Status-line crossfade, `RotationAnimation` on refresh | No tweens. Swap the phrase on a tick; `glyph = "loader"` with `enabled = false` while refreshing |
| `PointerMoveGate` (jitter filter) | `onHover` reports enter/leave only, with no coordinates. Enter-cancels-cursor-mode is the closest behaviour |
| `PanelToolTip` on rows | `ui.row` has no `tooltip`. Type and unread state go in the meta line |
| `TextMetrics` ink centring | No metrics API. A fixed 24 px circle; `baseline = "pictographic"` exists on `ui.label` |
| `IpcHandler` with return values | `onIpc` is one-way. A `dump` event that logs JSON instead |
| `switchPanel` on Tab | No sibling-panel concept. Dropped |
| `Qt.darker(foreground, 1.55)` | No colour arithmetic. Palette roles and role-with-alpha (`"primary/0.18"`) — theme-correct rather than approximated |
| `MultiEffect { colorization }` on the SVG | Neither `ui.image` nor `barWidget.setImage` tints (measured, step 1). Two pre-coloured variants picked by `isDarkMode()`; the state signal moves to the coloured count |

## Attribution

`assets/basecamp-*.svg` comes from the MIT-licensed source repository (© 2026 37signals LLC),
with its provenance comment preserved in the file; the second variant is the same geometry with a
different `fill`. The Basecamp word mark remains the property of 37signals — both READMEs must
state that this is an unofficial, unaffiliated plugin and link to the original.

## Open questions

- `thumbnail.webp` and `docs/panel.png` need a screenshot of the working panel, so they come
  after step 8.
- `plugin_api = 24` is the lowest level covering the features used; community-plugins asks for
  "the current documented level" (28) for a new plugin. Bump it if a maintainer insists.
- The directory name `basecamp/` is first-come in community-plugins; currently free, verify at
  PR time.
