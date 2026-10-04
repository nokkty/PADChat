-- The default VGS menu shipped with the addon. Players edit their own copy in
-- the editor window (the "VGSEdit" macro); this table seeds it on first run
-- and on "Reset to defaults".
--
-- Each level is keyed by the button that picks it: A, X or Y (B is always Cancel).
-- A node with `text` is a message and sends immediately; a node without it is a
-- category that opens the next level, up to four presses deep, so "X then Y
-- then A" works the same as Tribes 2's "V G Y".
--
-- `chat` is optional: "SAY" (default), "YELL" or "EMOTE".
-- On a PlayStation pad A = Cross, X = Square, Y = Triangle, B = Circle.

local _, ns = ...

ns.DefaultMenu = {
	A = { label = "Respond",
		A = { label = "Yes",     text = "Yes!" },
		X = { label = "No",      text = "No." },
		Y = { label = "Thanks",  text = "Thanks!" },
	},
	X = { label = "Social",
		A = { label = "Greet",
			A = { label = "Hello",   text = "Well met!" },
			X = { label = "Goodbye", text = "Farewell!" },
			Y = { label = "Wave",    text = "waves.", chat = "EMOTE" },
		},
		X = { label = "Group",
			A = { label = "Invite please!",  text = "Invite please!" },
			X = { label = "Want to group?",  text = "Want to group up?" },
			Y = { label = "Inviting you",    text = "Inviting you now!" },
		},
	},
	Y = { label = "Callout",
		A = { label = "Help!",      text = "Help!" },
		X = { label = "Incoming!",  text = "Incoming!" },
		Y = { label = "Follow me",  text = "Follow me!" },
	},
}
