--!nonstrict
-- Basecamp CLI responses, as `noctalia.json.decode` hands them to model.luau.
--
-- Transcribed from real `basecamp accounts list --json` and
-- `basecamp notifications list --json` output on a live account, then scrubbed:
-- no real names, e-mail addresses, project names or sgids reach this repo. The
-- shape is what matters and the shape is verbatim, including the things that
-- caught the port out:
--
--   * `id` is a JSON NUMBER, not a string (1000001, not "1000001")
--   * `unreads` is OMITTED entirely when nothing is unread
--   * `bubble_ups_count` sits beside the arrays and is an int, not a list
--   * keys vary per item: unread items carry `unread_count` and no `read_at`,
--     and plenty of items have no `content_excerpt` or `participants` at all
--   * `named` is null on every ping observed, so the "Ping with <names>" path
--     is the normal one rather than an edge case
--   * `type` is capitalised: Comment, Chat, Mention, Reminder, BoostReport,
--     Bulletin, Event, Assignment, Message
--   * `app_url` is usually app.basecamp.com but sometimes 3.basecampapi.com
--   * excerpts contain REAL newlines, not the literal "\n" sequences Model.js
--     filtered for, and run to ~300 characters
--
-- JSON null decodes to nil, which in a Lua table is indistinguishable from an
-- absent key, so nulls are simply left out here.

local M = {}

M.accounts = {
	ok = true,
	data = {
		{ href = "https://3.basecampapi.com/1000001", id = 1000001, name = "The Shire" },
		{ href = "https://3.basecampapi.com/1000002", id = 1000002, name = "bree traders" },
		-- No id: must be skipped rather than becoming "--account nil".
		{ href = "https://3.basecampapi.com/1000003", name = "Dropped, no id" },
	},
	summary = "2 accounts",
}

M.notifications = {
	ok = true,
	data = {
		bubble_ups_count = 0,
		scheduled_bubble_ups_count = 2,

		unreads = {
			{
				id = 9000000008,
				type = "Chat",
				section = "pings",
				title = "Ping",
				-- named = nil, exactly as the API sends it
				participants = { { id = 2000001, name = "Frodo Baggins" } },
				creator = { id = 2000001, name = "Frodo Baggins", avatar_url = "https://example.invalid/a.png" },
				bucket_name = "Frodo Baggins + Samwise Gamgee",
				created_at = "2026-09-03T15:16:25.678Z",
				updated_at = "2026-09-03T15:16:25.678Z",
				unread_at = "2026-09-03T15:16:25.678Z",
				unread_count = 3,
				app_url = "https://app.basecamp.com/1000001/circles/3000001",
				readable_identifier = "Z2lkOi8vYmMzL1JlY29yZGluZy85MDAwMDAwMDA4",
				readable_sgid = "BAh7BkkiC19yYWlsc--deadbeef",
				subscription_url = "https://3.basecampapi.com/1000001/my/subscriptions/x.json",
			},
			{
				id = 9000000007,
				type = "Mention",
				section = "inbox",
				title = "Samwise Gamgee mentioned you in Sprint planning",
				content_excerpt = "Can you take a look\n\n\nbefore   Friday?",
				creator = { name = "Samwise Gamgee" },
				bucket_name = "Fellowship",
				created_at = "2026-09-03T09:41:00.000Z",
				updated_at = "2026-09-03T09:41:00.000Z",
				unread_at = "2026-09-03T09:41:00.000Z",
				unread_count = 1,
				app_url = "https://app.basecamp.com/1000001/buckets/1/todos/2",
			},
			{
				id = 9000000006,
				type = "BoostReport",
				section = "inbox",
				title = "Your week in boosts",
				creator = { name = "Basecamp" },
				updated_at = "2026-09-02T08:00:00.000Z",
				unread_at = "2026-09-02T08:00:00.000Z",
				unread_count = 0,
				-- API host: must be rewritten to app.basecamp.com before opening.
				app_url = "https://3.basecampapi.com/1000001/my/boosts/7",
			},
		},

		reads = {
			{
				id = 9000000005,
				type = "Comment",
				section = "inbox",
				title = "Gandalf Greyhame commented on Homepage copy",
				-- Double-encoded markup plus real markup plus a bare entity: the
				-- decode-then-strip order has to leave this inert.
				content_excerpt = "Looks good &amp;lt;script&amp;gt;alert(1)&amp;lt;/script&amp;gt; <b>bold</b>&nbsp;&amp; done",
				creator = { name = "Gandalf Greyhame" },
				created_at = "2026-09-01T13:33:53.579Z",
				updated_at = "2026-09-01T13:33:53.579Z",
				unread_at = "2026-09-01T13:33:53.579Z",
				read_at = "2026-09-01T14:00:00.000Z",
				bucket_name = "Fellowship",
				app_url = "https://app.basecamp.com/1000001/buckets/1/messages/3",
			},
			{
				id = 9000000004,
				type = "Reminder",
				section = "inbox",
				title = "Agenda - Weekly team meeting",
				-- 290 characters: longer than the excerpt cap.
				content_excerpt = "Time: 09:00 to 10:00 (max one hour). Present: the whole team. Goal: everyone up to date on the sprint, blockers named out loud, and the release date confirmed. Bring your own notes, keep the round short, and put anything that needs a decision at the top so it does not fall off the end again.",
				creator = { name = "Peregrin Took" },
				updated_at = "2026-08-30T07:00:00.000Z",
				read_at = "2026-08-30T07:05:00.000Z",
				bucket_name = "Fellowship",
				app_url = "https://app.basecamp.com/1000001/buckets/1/schedule_entries/9",
			},
			{
				id = 9000000003,
				type = "Chat",
				section = "chats",
				title = "Campfire",
				creator = { name = "Meriadoc Brandybuck" },
				-- Last year, so the label must carry a year.
				updated_at = "2025-12-24T22:15:00.000Z",
				read_at = "2025-12-24T22:20:00.000Z",
				bucket_name = "Fellowship",
				app_url = "https://app.basecamp.com/1000001/buckets/1/chats/4",
			},
			{
				id = 9000000002,
				type = "Assignment",
				section = "inbox",
				-- No title at all: the fallback must be bucket_name, never the
				-- opaque readable_identifier.
				readable_identifier = "Z2lkOi8vYmMzL1RvZG8vOTAwMDAwMDAwMg",
				bucket_name = "Internal",
				updated_at = "2026-08-29T10:00:00.000Z",
				read_at = "2026-08-29T10:01:00.000Z",
				app_url = "https://app.basecamp.com/1000001/buckets/2/todos/5",
			},
			{
				-- id 0 is not a real Basecamp id. Model.js dropped it because 0 is
				-- falsy in JS; in Lua 0 is truthy, so this has to be dropped on
				-- purpose or it becomes `--account 0`.
				id = 0,
				type = "Comment",
				section = "inbox",
				title = "Dropped, id is zero",
				updated_at = "2026-08-28T10:00:00.000Z",
				read_at = "2026-08-28T10:00:00.000Z",
				app_url = "https://app.basecamp.com/1000001/buckets/1/messages/6",
			},
		},
	},
	summary = "3 unread, 5 read",
}

-- Nothing unread: the `unreads` key is absent, not an empty array.
M.notificationsAllRead = {
	ok = true,
	data = {
		bubble_ups_count = 0,
		scheduled_bubble_ups_count = 0,
		reads = {
			{
				id = 1,
				type = "Comment",
				section = "inbox",
				title = "Only read item",
				creator = { name = "Frodo Baggins" },
				updated_at = "2026-09-01T10:00:00.000Z",
				read_at = "2026-09-01T10:05:00.000Z",
				app_url = "https://app.basecamp.com/1000001/buckets/1/messages/1",
			},
		},
	},
}

-- A `reads` entry the server has not actually marked read. The section says
-- "read", the item says otherwise, and the item wins.
M.notificationsReadSectionUnreadItem = {
	ok = true,
	data = {
		reads = {
			{
				id = 42,
				type = "Comment",
				section = "inbox",
				title = "Section says read, item says unread",
				creator = { name = "Frodo Baggins" },
				updated_at = "2026-09-01T10:00:00.000Z",
				read_at = "",
				app_url = "https://app.basecamp.com/1000001/buckets/1/messages/42",
			},
		},
	},
}

M.authRequired = {
	ok = false,
	error = "You are not signed in. Run `basecamp auth login`.",
	code = "auth_required",
	retryable = false,
}

M.apiError = {
	ok = false,
	error = "Rate limited, try again shortly",
	code = "rate_limited",
	retryable = true,
}

return M
