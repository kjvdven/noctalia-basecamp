--!nonstrict
-- Unit tests for the pure Basecamp logic. Run without installing anything:
--
--   nix run nixpkgs#luau -- tests/model_test.luau
--
-- (from the repository root). Exits non-zero when any expectation fails.
--
-- The cases that matter most are the ones a straight transliteration of
-- Model.js would have got wrong: HTML entity ordering, ISO-8601 without a date
-- library, numeric account ids, id 0 (falsy in JS, truthy in Lua), a missing
-- `unreads` section, and readable_identifier never being used as a title.

local model = require("../basecamp/model")
local cli = require("./fixtures/cli")

local failures = 0
local checks = 0

local function expect(label: string, actual: any, wanted: any)
	checks += 1
	if actual ~= wanted then
		failures += 1
		print(`FAIL {label}\n  wanted: {tostring(wanted)}\n  actual: {tostring(actual)}`)
	end
end

local ACCOUNT = { id = "1000001", name = "The Shire", order = 0 }
local ACCOUNT_TWO = { id = "1000002", name = "bree traders", order = 1 }
local LABELS = { fallbackTitle = "Basecamp notification", pingTitle = "Ping with {names}" }

-- ── trim / cleanText ────────────────────────────────────────────────────────
do
	expect("trim spaces", model.trim("  hi  "), "hi")
	expect("trim newlines", model.trim("\n\thi\n"), "hi")
	expect("trim empty", model.trim(""), "")

	expect("cleanText nil", model.cleanText(nil), "")
	expect("cleanText number", model.cleanText(42), "")
	expect("cleanText collapses real newlines", model.cleanText("a\n\n\nb   c"), "a b c")
	expect("cleanText collapses literal escapes", model.cleanText("a\\nb\\tc"), "a b c")
	expect("cleanText strips tags", model.cleanText("<b>bold</b> text"), "bold text")
	expect("cleanText strips br", model.cleanText("one<br/>two<br />three"), "one two three")
	expect("cleanText decodes nbsp", model.cleanText("a&nbsp;b"), "a b")
	expect("cleanText decodes quot", model.cleanText("say &quot;hi&quot;"), 'say "hi"')
	expect("cleanText decodes apos", model.cleanText("it&#39;s"), "it's")
	expect("cleanText leaves unknown entity", model.cleanText("&notanentity;"), "&notanentity;")

	-- The security property: encoded markup is decoded and THEN stripped, so it
	-- cannot survive into the UI as live markup.
	expect("cleanText removes encoded markup", model.cleanText("&lt;img onerror=x&gt;safe"), "safe")
	-- Double-encoded markup re-forms as inert TEXT, because &amp; resolves last.
	expect(
		"cleanText keeps double-encoded markup inert",
		model.cleanText("&amp;lt;script&amp;gt;alert(1)&amp;lt;/script&amp;gt;"),
		"&lt;script&gt;alert(1)&lt;/script&gt;"
	)
	expect("cleanText bare amp", model.cleanText("a &amp; b"), "a & b")
end

-- ── truncate / concise ──────────────────────────────────────────────────────
do
	expect("truncate short", model.truncate("hello", 10), "hello")
	expect("truncate exact", model.truncate("hello", 5), "hello")
	expect("truncate cuts", model.truncate("hello world", 5), "hello…")

	-- "é" is two bytes: cutting at 3 must not leave half of it behind.
	local accented = "caf\u{e9}s"
	expect("truncate keeps utf8 whole", model.truncate(accented, 4), "caf…")
	expect("truncate does not split utf8", model.truncate(accented, 3), "caf…")

	expect("concise falls back", model.concise("", "nothing"), "nothing")
	expect("concise cleans", model.concise("  <b>x</b>  ", "f"), "x")
	-- 180 bytes of text plus the ellipsis, which is U+2026 and therefore THREE
	-- bytes, not one. Worth pinning: it is the kind of thing a later "tighten
	-- the cap" change silently gets wrong.
	local long = string.rep("a", 400)
	expect("concise caps at 180", #model.concise(long, ""), 183)
end

-- ── formatTemplate ──────────────────────────────────────────────────────────
do
	expect("template substitutes", model.formatTemplate("Ping with {names}", { names = "A & B" }), "Ping with A & B")
	expect("template numbers", model.formatTemplate("{count} left", { count = 3 }), "3 left")
	expect("template leaves unknown", model.formatTemplate("{nope}", {}), "{nope}")
end

-- ── idToString ──────────────────────────────────────────────────────────────
do
	-- The real reason this exists: a large integral float must not become
	-- "1e+06" and reach the CLI as --account.
	expect("id from number", model.idToString(1000001), "1000001")
	expect("id from big number", model.idToString(9000000008), "9000000008")
	expect("id from string", model.idToString(" 42 "), "42")
	expect("id from nil", model.idToString(nil), "")
	expect("id from bool", model.idToString(true), "")
	expect("id from zero", model.idToString(0), "0")
end

-- ── parseEnvelope ───────────────────────────────────────────────────────────
do
	local ok = model.parseEnvelope({ ok = true, data = { 1, 2 } })
	expect("envelope ok", ok.ok, true)
	expect("envelope data", #ok.data, 2)

	local auth = model.parseEnvelope(cli.authRequired)
	expect("envelope failure", auth.ok, false)
	expect("envelope code", auth.code, "auth_required")
	expect("envelope retryable false", auth.retryable, false)

	local rate = model.parseEnvelope(cli.apiError)
	expect("envelope retryable true", rate.retryable, true)
	expect("envelope error text", rate.error, "Rate limited, try again shortly")

	local junk = model.parseEnvelope("not a table")
	expect("envelope junk", junk.ok, false)
	expect("envelope junk code", junk.code, "")
end

-- ── parseCliVersion ─────────────────────────────────────────────────────────
do
	local function supported(text: string): boolean
		return model.parseCliVersion(text).supported
	end

	expect("version 0.9.1 parses", model.parseCliVersion("basecamp version 0.9.1").version, "0.9.1")
	expect("version 0.9.1 supported", supported("basecamp version 0.9.1"), true)
	expect("version 0.9.0 supported", supported("basecamp version 0.9.0"), true)
	expect("version 0.8.9 unsupported", supported("basecamp version 0.8.9"), false)
	expect("version 0.10.0 supported", supported("basecamp version 0.10.0"), true)
	expect("version 1.0.0 supported", supported("basecamp version 1.0.0"), true)
	-- A prerelease of the floor predates the floor.
	expect("version 0.9.0-rc.1 unsupported", supported("basecamp version 0.9.0-rc.1"), false)
	expect("version 0.9.1-rc.1 supported", supported("basecamp version 0.9.1-rc.1"), true)
	expect("version with build metadata", model.parseCliVersion("basecamp version 0.9.1+linux.x86-64").version, "0.9.1+linux.x86-64")
	expect("version with v prefix", supported("basecamp version v0.9.1"), true)
	expect("version trailing space", supported("basecamp version 0.9.1\n"), true)

	expect("version garbage not ok", model.parseCliVersion("garbage").ok, false)
	expect("version empty not ok", model.parseCliVersion("").ok, false)
	expect("version nil not ok", model.parseCliVersion(nil).ok, false)
end

-- ── parseAccounts ───────────────────────────────────────────────────────────
do
	local parsed = model.parseAccounts(cli.accounts)
	expect("accounts ok", parsed.ok, true)
	-- Three entries in, one without an id: two out.
	expect("accounts count", #parsed.accounts, 2)
	expect("accounts numeric id stringified", parsed.accounts[1].id, "1000001")
	expect("accounts name", parsed.accounts[1].name, "The Shire")
	expect("accounts order starts at 0", parsed.accounts[1].order, 0)
	expect("accounts order increments", parsed.accounts[2].order, 1)

	local failed = model.parseAccounts(cli.authRequired)
	expect("accounts on auth failure", failed.ok, false)
	expect("accounts empty on failure", #failed.accounts, 0)

	local unnamed = model.parseAccounts({ ok = true, data = { { id = 77 } } }, "Account {id}")
	expect("accounts fallback name", unnamed.accounts[1].name, "Account 77")

	-- Ids reach a shell command: anything but plain digits is dropped.
	local hostile = model.parseAccounts({ ok = true, data = {
		{ id = "1$(printf INJECTION_PROOF)" },
		{ id = "12; rm -rf x" },
		{ id = "007" },
		{ id = "0" },
		{ id = "42" },
	} })
	expect("accounts drop non-numeric ids", #hostile.accounts, 1)
	expect("accounts keep numeric id", hostile.accounts[1].id, "42")
end

-- ── normalizeItem ───────────────────────────────────────────────────────────
-- The service feeds normalizeItem one raw item at a time (jq splits the page
-- and flags the section), so the tests do the same over the fixture sections.
local function normalizeAll(response)
	local items = {}
	for _, section in ipairs({ { response.data.unreads, true }, { response.data.reads, false } }) do
		for _, raw in ipairs(section[1] or {}) do
			local item = model.normalizeItem(raw, ACCOUNT, section[2], LABELS)
			if item ~= nil then
				table.insert(items, item)
			end
		end
	end
	return items
end

do
	local items = normalizeAll(cli.notifications)
	-- 3 unread + 5 read = 8 raw, minus the id-0 item = 7.
	expect("notifications count drops id 0", #items, 7)

	local byId = {}
	for _, item in ipairs(items) do
		byId[item.id] = item
	end

	expect("unread section marks unread", byId["9000000007"].unread, true)
	expect("read section marks read", byId["9000000005"].unread, false)
	expect("unread count carried", byId["9000000008"].unreadCount, 3)

	-- An unnamed ping is titled just "Ping"; the participants identify it.
	expect("ping title from participants", byId["9000000008"].title, "Ping with Frodo Baggins")

	-- Never the opaque base64 GID: fall back to the project name.
	expect("title falls back to bucket_name", byId["9000000002"].title, "Internal")

	-- API host rewritten so the browser gets the web app, not raw JSON.
	expect("app_url rewritten", byId["9000000006"].url, "https://app.basecamp.com/1000001/my/boosts/7")
	expect("app_url left alone", byId["9000000007"].url, "https://app.basecamp.com/1000001/buckets/1/todos/2")

	-- Excerpt is cleaned and capped.
	expect("excerpt cleaned", byId["9000000007"].excerpt, "Can you take a look before Friday?")
	-- 240 bytes plus the three-byte ellipsis.
	expect("excerpt capped", #byId["9000000004"].excerpt, 243)
	expect(
		"excerpt keeps double-encoded markup inert",
		byId["9000000005"].excerpt,
		"Looks good &lt;script&gt;alert(1)&lt;/script&gt; bold & done"
	)

	expect("creator extracted", byId["9000000005"].creator, "Gandalf Greyhame")
	expect("kind preserved with capital", byId["9000000006"].kind, "BoostReport")
	expect("account id copied", byId["9000000005"].accountId, "1000001")
	expect("account name copied", byId["9000000005"].accountName, "The Shire")
	expect("missing excerpt is empty", byId["9000000003"].excerpt, "")

	-- Raw fields that must not survive normalization.
	expect("sgid dropped", byId["9000000008"].readable_sgid, nil)
	expect("subscription_url dropped", byId["9000000008"].subscription_url, nil)
	expect("raw creator object dropped", type(byId["9000000005"].creator), "string")

	-- A missing `unreads` key is the normal shape when nothing is unread.
	local allRead = normalizeAll(cli.notificationsAllRead)
	expect("missing unreads count", #allRead, 1)
	expect("missing unreads all read", allRead[1].unread, false)

	-- The item's own read_at overrides an optimistic section name.
	local mismatch = normalizeAll(cli.notificationsReadSectionUnreadItem)
	expect("empty read_at means unread", mismatch[1].unread, true)

	-- No read_at at all, outside any unread section: unread.
	local bare = model.normalizeItem(
		{ id = 5, type = "Comment", title = "Bare", updated_at = "2026-09-01T10:00:00.000Z" },
		ACCOUNT,
		false,
		LABELS
	)
	expect("bare item unread", bare.unread, true)
	expect("bare item id is a string", bare.id, "5")
end

-- ── normalizeAppUrl ─────────────────────────────────────────────────────────
do
	expect(
		"rewrites api host",
		model.normalizeAppUrl("https://3.basecampapi.com/1000001/x"),
		"https://app.basecamp.com/1000001/x"
	)
	expect(
		"leaves app host",
		model.normalizeAppUrl("https://app.basecamp.com/1000001/x"),
		"https://app.basecamp.com/1000001/x"
	)
	-- Only at the start, so a host appearing mid-URL is not mangled.
	expect(
		"only rewrites prefix",
		model.normalizeAppUrl("https://app.basecamp.com/r?u=https://3.basecampapi.com/x"),
		"https://app.basecamp.com/r?u=https://3.basecampapi.com/x"
	)
	expect("empty url", model.normalizeAppUrl(nil), "")
end

-- ── joinNames / pingNames ───────────────────────────────────────────────────
do
	expect("join none", model.joinNames({}), "")
	expect("join one", model.joinNames({ "A" }), "A")
	expect("join two", model.joinNames({ "A", "B" }), "A & B")
	expect("join three", model.joinNames({ "A", "B", "C" }), "A, B & C")

	expect("ping names", model.pingNames({ participants = { { name = "A" }, { name = "B" } } }), "A & B")
	expect("ping names skips blanks", model.pingNames({ participants = { { name = "" }, { name = "B" } } }), "B")
	expect("ping names without participants", model.pingNames({}), "")
	expect("ping names on nil", model.pingNames(nil), "")
end

-- ── daysFromCivil / civilFromDays / parseIso8601 ────────────────────────────
do
	expect("epoch day", model.daysFromCivil(1970, 1, 1), 0)
	expect("day after epoch", model.daysFromCivil(1970, 1, 2), 1)
	expect("leap day 2000", model.daysFromCivil(2000, 3, 1) - model.daysFromCivil(2000, 2, 28), 2)
	expect("non-leap 1900", model.daysFromCivil(1900, 3, 1) - model.daysFromCivil(1900, 2, 28), 1)
	expect("before epoch", model.daysFromCivil(1969, 12, 31), -1)

	local roundTrip = model.civilFromDays(model.daysFromCivil(2026, 9, 3))
	expect("round trip year", roundTrip.y, 2026)
	expect("round trip month", roundTrip.m, 9)
	expect("round trip day", roundTrip.d, 3)

	expect("iso epoch", model.parseIso8601("1970-01-01T00:00:00Z"), 0)
	expect("iso utc", model.parseIso8601("2026-09-03T15:16:25Z"), 1788448585)
	expect("iso fractional", model.parseIso8601("2026-09-03T15:16:25.678Z"), 1788448585)
	-- +02:00 means the UTC instant is two hours earlier.
	expect("iso positive offset", model.parseIso8601("2026-09-03T17:16:25+02:00"), 1788448585)
	expect("iso negative offset", model.parseIso8601("2026-09-03T10:16:25-05:00"), 1788448585)
	expect("iso compact offset", model.parseIso8601("2026-09-03T17:16:25+0200"), 1788448585)
	expect("iso space separator", model.parseIso8601("2026-09-03 15:16:25Z"), 1788448585)
	expect("iso malformed", model.parseIso8601("not a date"), 0)
	expect("iso nil", model.parseIso8601(nil), 0)
	expect("iso partial", model.parseIso8601("2026-09-03"), 0)
end

-- ── relativeTime ────────────────────────────────────────────────────────────
do
	-- 2026-09-03T09:41:00Z, and "now" later the same UTC day.
	local ts = model.parseIso8601("2026-09-03T09:41:00Z")
	local now = model.parseIso8601("2026-09-03T20:00:00Z")

	expect("same day 12h", model.relativeTime(ts, now, 0, false), "9:41am")
	expect("same day 24h", model.relativeTime(ts, now, 0, true), "9:41")

	local afternoon = model.parseIso8601("2026-09-03T13:05:00Z")
	expect("afternoon 12h", model.relativeTime(afternoon, now, 0, false), "1:05pm")
	expect("afternoon 24h", model.relativeTime(afternoon, now, 0, true), "13:05")

	local noon = model.parseIso8601("2026-09-03T12:00:00Z")
	expect("noon is 12pm", model.relativeTime(noon, now, 0, false), "12:00pm")
	local midnight = model.parseIso8601("2026-09-03T00:30:00Z")
	expect("midnight is 12am", model.relativeTime(midnight, now, 0, false), "12:30am")

	-- Earlier this year, so a day but no year.
	local earlier = model.parseIso8601("2026-08-29T10:00:00Z")
	expect("this year", model.relativeTime(earlier, now, 0, true), "Aug 29")

	-- Last year, so a year too.
	local lastYear = model.parseIso8601("2025-12-24T22:15:00Z")
	expect("last year", model.relativeTime(lastYear, now, 0, true), "Dec 24, 2025")

	-- The timezone offset can move an instant across the day boundary, which is
	-- exactly why it is a parameter instead of read from the environment.
	local lateUtc = model.parseIso8601("2026-09-03T23:30:00Z")
	expect("utc same day", model.relativeTime(lateUtc, now, 0, true), "23:30")
	expect("plus two crosses midnight", model.relativeTime(lateUtc, now, 7200, true), "Sep 4")

	expect("zero timestamp", model.relativeTime(0, now, 0, true), "")
	expect("negative timestamp", model.relativeTime(-5, now, 0, true), "")
end

-- ── metaLine ────────────────────────────────────────────────────────────────
do
	local now = model.parseIso8601("2026-09-03T20:00:00Z")
	local item = {
		tsSec = model.parseIso8601("2026-09-03T09:41:00Z"),
		creator = "Samwise Gamgee",
		project = "Fellowship",
		accountName = "The Shire",
	}
	expect("meta without account", model.metaLine(item, now, 0, false, false), "9:41am • Samwise Gamgee • Fellowship")
	expect(
		"meta with account",
		model.metaLine(item, now, 0, false, true),
		"9:41am • Samwise Gamgee • Fellowship (The Shire)"
	)
	expect(
		"meta account only when no project",
		model.metaLine(
			{ tsSec = item.tsSec, creator = "", project = "", accountName = "The Shire" },
			now,
			0,
			false,
			true
		),
		"9:41am • The Shire"
	)
	expect("meta empty item", model.metaLine({ tsSec = 0, creator = "", project = "", accountName = "" }, now, 0, false, false), "")
	expect("meta nil", model.metaLine(nil, now, 0, false, false), "")
end

-- ── sort / filter / counts ──────────────────────────────────────────────────
do
	local items = {
		{ id = "1", accountId = "a", accountOrder = 0, tsSec = 100, unread = true },
		{ id = "2", accountId = "b", accountOrder = 1, tsSec = 300, unread = false },
		{ id = "3", accountId = "a", accountOrder = 0, tsSec = 200, unread = true },
		-- Same timestamp as 2: account order breaks the tie, then id.
		{ id = "4", accountId = "a", accountOrder = 0, tsSec = 300, unread = false },
	}

	local sorted = model.sortNotifications(items)
	expect("sorted newest first", sorted[1].id, "4")
	expect("tie broken by account order", sorted[2].id, "2")
	expect("then by time", sorted[3].id, "3")
	expect("oldest last", sorted[4].id, "1")
	-- The input must not be reordered in place: state values are copies.
	expect("sort does not mutate input", items[1].id, "1")

	expect("filter all", #model.filterNotifications(items, "", "all"), 4)
	expect("filter unread", #model.filterNotifications(items, "", "unread"), 2)
	expect("filter previous", #model.filterNotifications(items, "", "previous"), 2)
	expect("filter by account", #model.filterNotifications(items, "a", "all"), 3)
	expect("filter account and tab", #model.filterNotifications(items, "a", "previous"), 1)
	expect("filter unknown account", #model.filterNotifications(items, "zzz", "all"), 0)
	expect("filter nil items", #model.filterNotifications(nil, "", "all"), 0)

	-- Pages repeat the unread section, so merging must drop repeats by
	-- account + id and nothing else.
	local merged = model.mergeItems(items, {
		{ id = "1", accountId = "a", accountOrder = 0, tsSec = 100, unread = true },
		{ id = "1", accountId = "b", accountOrder = 1, tsSec = 100, unread = false },
		{ id = "5", accountId = "a", accountOrder = 0, tsSec = 50, unread = false },
	})
	expect("merge drops repeat", #merged, 6)
	expect("merge keeps existing order", merged[1].id, "1")
	expect("merge appends new last", merged[6].id, "5")
	expect("merge same id other account", merged[5].accountId, "b")
	expect("merge nil existing", #model.mergeItems(nil, items), 4)
	expect("merge nil incoming", #model.mergeItems(items, nil), 4)

	expect("unread count all", model.unreadCount(items, ""), 2)
	expect("unread count account a", model.unreadCount(items, "a"), 2)
	expect("unread count account b", model.unreadCount(items, "b"), 0)
	expect("unread count nil", model.unreadCount(nil, ""), 0)

	local byAccount = model.unreadByAccount(items)
	expect("unread by account a", byAccount.a, 2)
	expect("unread by account b", byAccount.b, nil)
end

-- ── markReadLocally ─────────────────────────────────────────────────────────
do
	local items = {
		{ id = "1", accountId = "a", unread = true, unreadCount = 3 },
		{ id = "2", accountId = "a", unread = true, unreadCount = 1 },
		{ id = "3", accountId = "b", unread = true, unreadCount = 1 },
	}

	local out = model.markReadLocally(items, "a", { "1" })
	expect("mark read returns array", #out, 3)
	expect("mark read flips target", out[1].unread, false)
	expect("mark read clears count", out[1].unreadCount, 0)
	expect("mark read leaves sibling", out[2].unread, true)
	expect("mark read leaves other account", out[3].unread, true)
	-- Must not mutate: the caller publishes the new array.
	expect("mark read does not mutate input", items[1].unread, true)

	expect("mark read numeric id", model.markReadLocally(items, "a", { 2 })[2].unread, false)
	expect("mark read wrong account", model.markReadLocally(items, "zzz", { "1" }), nil)
	expect("mark read unknown id", model.markReadLocally(items, "a", { "999" }), nil)
	expect("mark read already read", model.markReadLocally({ { id = "1", accountId = "a", unread = false } }, "a", { "1" }), nil)
	expect("mark read empty ids", model.markReadLocally(items, "a", {}), nil)
end

-- ── enqueueRead ─────────────────────────────────────────────────────────────
do
	local queue = {}
	model.enqueueRead(queue, "a", { "1" })
	expect("enqueue creates batch", #queue, 1)
	expect("enqueue batch account", queue[1].accountId, "a")

	-- The CLI takes many ids at once, so one account coalesces into one argv.
	model.enqueueRead(queue, "a", { "2", "3" })
	expect("enqueue coalesces same account", #queue, 1)
	expect("enqueue coalesced ids", #queue[1].ids, 3)

	model.enqueueRead(queue, "a", { "2" })
	expect("enqueue dedupes", #queue[1].ids, 3)

	model.enqueueRead(queue, "b", { "9" })
	expect("enqueue separates accounts", #queue, 2)

	model.enqueueRead(queue, "c", {})
	expect("enqueue ignores empty", #queue, 2)
	model.enqueueRead(queue, "c", { "" })
	expect("enqueue ignores blank ids", #queue, 2)
end

-- ── accountOptions / cycleAccount ───────────────────────────────────────────
do
	local accounts = {
		{ id = "1", name = "The Shire", order = 0 },
		{ id = "2", name = "bree traders", order = 1 },
	}
	local options = model.accountOptions(accounts, "All accounts")
	expect("options count", #options, 3)
	expect("options all first", options[1].value, "")
	expect("options all label", options[1].label, "All accounts")
	-- Case-insensitive: "bree traders" sorts before "The Shire".
	expect("options sorted case-insensitively", options[2].label, "bree traders")
	expect("options last", options[3].label, "The Shire")

	expect("cycle forward from all", model.cycleAccount(options, "", 1), "2")
	expect("cycle backward wraps", model.cycleAccount(options, "", -1), "1")
	expect("cycle forward wraps", model.cycleAccount(options, "1", 1), "")
	expect("cycle single option", model.cycleAccount({ { value = "", label = "All" } }, "", 1), "")
	expect("cycle unknown current", model.cycleAccount(options, "nope", 1), "2")

	expect("options with no accounts", #model.accountOptions({}, "All accounts"), 1)
	expect("options with nil", #model.accountOptions(nil, "All accounts"), 1)
end

-- ── glyphs / colours / badge ────────────────────────────────────────────────
do
	-- The CLI capitalises type, so the lookup has to lower first.
	expect("glyph for Mention", model.typeGlyph("Mention"), "at")
	expect("glyph for Comment", model.typeGlyph("Comment"), "message")
	expect("glyph for Chat", model.typeGlyph("Chat"), "messages")
	expect("glyph for BoostReport", model.typeGlyph("BoostReport"), "rocket")
	expect("glyph for Reminder", model.typeGlyph("Reminder"), "calendar-event")
	expect("glyph for Assignment", model.typeGlyph("Assignment"), "checkbox")
	expect("glyph fallback", model.typeGlyph("SomethingNew"), "bell")
	expect("glyph for nil", model.typeGlyph(nil), "bell")

	expect("colour for Mention", model.typeColorRole("Mention"), "error")
	expect("colour for Chat", model.typeColorRole("Chat"), "primary")
	expect("colour fallback", model.typeColorRole("SomethingNew"), "on_surface")

	expect("badge shows count", model.badgeText({ unreadCount = 4 }, false), "4")
	-- At least 1: an unread item with no count still reads as one.
	expect("badge floors at one", model.badgeText({ unreadCount = 0 }, false), "1")
	expect("badge hovered is blank", model.badgeText({ unreadCount = 4 }, true), "")
end

-- ── setupPlan ───────────────────────────────────────────────────────────────
do
	-- Priority: missing beats outdated beats signed out.
	local missing = model.setupPlan(false, false, false)
	expect("missing wins", missing.kind, "missing")
	expect("missing needs setup", missing.needed, true)
	-- Deliberately does NOT run a package manager: no portable equivalent.
	expect("missing runs nothing", missing.runsInTerminal, false)
	expect("missing has docs", missing.docUrl ~= "", true)

	local outdated = model.setupPlan(true, false, false)
	expect("outdated wins over signin", outdated.kind, "outdated")
	expect("outdated runs nothing", outdated.runsInTerminal, false)

	local signin = model.setupPlan(true, true, false)
	expect("signin kind", signin.kind, "signin")
	expect("signin command", signin.command, "basecamp auth login")
	expect("signin runs in terminal", signin.runsInTerminal, true)

	local fine = model.setupPlan(true, true, true)
	expect("healthy needs nothing", fine.needed, false)
	expect("healthy has no kind", fine.kind, "")
end

-- ── summary ─────────────────────────────────────────────────────────────────

print(`{checks - failures}/{checks} checks passed`)
if failures > 0 then
	-- The luau CLI has no os.exit; a bare error still exits non-zero.
	error(`{failures} of {checks} checks failed`, 0)
end
