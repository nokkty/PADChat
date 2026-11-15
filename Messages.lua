-- The default PAD Chat menu shipped with the addon. Players edit their own copy in
-- the editor window (the "PADEdit" macro or minimap button); this table seeds it on first run
-- and on "Reset to defaults".
--
-- Each level is keyed by the button that picks it: A, X or Y (B is always Cancel),
-- or C-K for those three with LT, RT or both triggers held (see SLOTS in PADChat.lua).
-- A node with `text` is a message and sends immediately; a node without it is a
-- category that opens the next level, up to four presses deep, so "X then Y
-- then A" works the same as Tribes 2's "V G Y".
--
-- The selected Whisper, Say, Guild, Group or Battleground tab determines where
-- messages go. `variants.WHISPER`, `variants.GUILD`, `variants.GROUP` and
-- `variants.RAID` replace options on those tabs; Whisper and Guild inherit Say
-- (Group variants never reach Guild), Battleground inherits Group, and false
-- clears a slot.
-- A message sends chat text, an `emote` token, or both: "Wave" is emote-only
-- and says nothing. Chat text can hold {location}, {LEVEL} and {CLASS}
-- placeholders. The LFG tab (`variants.LFG`) inherits Whisper.
-- `battlegrounds[instanceID]` supplies a menu for a specific battleground.
-- On a PlayStation pad A = Cross, X = Square, Y = Triangle, B = Circle.

local _, ns = ...

ns.DefaultMenu = {
	A = { label = "Respond",
		A = { label = "Yes",     text = "Yes!" },
		X = { label = "No",      text = "No." },
		Y = { label = "Thanks",  text = "Thanks!" },
		-- LT is the polite or positive version of a button (C D E = LT+A X Y) and
		-- RT is the "not right now" version (F G H = RT+A X Y). LT+RT is left to players.
		F = { label = "One moment",     text = "One moment, please." },
		G = { label = "I cannot",       text = "I cannot right now." },
		H = { label = "Sorry",          text = "Sorry!" },
	},
	X = { label = "Social",
		A = { label = "Greet",
			A = { label = "Hello",   text = "Hello" },
			-- An emote only reaches players nearby, never the whisper target, so
			-- the Whisper tab sends text alone.
			X = { label = "Goodbye", text = "Farewell", emote = "WAVE",
				variants = { WHISPER = { label = "Goodbye", text = "Farewell" } } },
			Y = { label = "Wave",    emote = "WAVE",
				variants = { WHISPER = { label = "Thanks for the group", text = "Thanks for the group!" } } },
			D = { label = "Have a good one",  text = "Have a good one!" },
			G = { label = "Gotta go",         text = "Gotta go, sorry!" },
		},
		X = { label = "Group",
			A = { label = "Invite please!",  text = "Invite please!" },
			X = { label = "Want to group?",  text = "Want to group up?" },
			Y = { label = "Inviting you",    text = "Inviting you now!" },
			D = { label = "Not grouping",       text = "No thanks, not grouping right now." },
			E = { label = "Of course",      text = "Of course!" },
			G = { label = "Group is full",      text = "Group is full, sorry." },
			H = { label = "Can't invite",       text = "Can't invite right now." },
		},
	},
	Y = { label = "Callout",
		A = { label = "Help!",      text = "Help!" },
		X = { label = "Incoming!",  text = "Incoming!" },
		Y = { label = "Follow me",  text = "Follow me!" },
		C = { label = "On my way",        text = "On my way!" },
		F = { label = "Can't reach you",  text = "Can't reach you!" },
		H = { label = "Wait here",        text = "Wait here." },
	},
}

ns.DefaultMenu.X.variants = {
	GROUP = { label = "Readiness",
		A = { label = "Resources",
			A = { label = "Need mana", text = "Need mana.", emote = "OOM" },
			X = { label = "Need healing", text = "Need healing, please!" },
			Y = { label = "Wait up", text = "Wait up!" },
		},
		X = { label = "Preparation",
			A = { label = "Ready", text = "Ready when you are." },
			X = { label = "Buffs please", text = "Buffs please!" },
			Y = { label = "Drinking", text = "Drinking, please wait." },
			C = { label = "Good to go",    text = "Good to go!" },
			E = { label = "Back",          text = "Back." },
			F = { label = "Not ready yet", text = "Not ready yet." },
			H = { label = "AFK",           text = "AFK, one minute." },
		},
	},
	RAID = { label = "Objectives",
		A = { label = "Help {location}", text = "Need help at {location}!" },
		X = { label = "Defend {location}", text = "Defend {location}!" },
		Y = { label = "{location} clear", text = "{location} clear." },
	},
}
ns.DefaultMenu.Y.variants = {
	GROUP = { label = "Coordination",
		A = { label = "Help", text = "Need help!" },
		X = { label = "Incoming", text = "Incoming!" },
		Y = { label = "Follow me", text = "Follow me!" },
	},
	RAID = { label = "Team",
		A = { label = "Regroup", text = "Regroup!" },
		X = { label = "Need healing", text = "Need healing, please!" },
		Y = { label = "Need mana", text = "Need mana.", emote = "OOM" },
	},
}
-- The Group tab's Coordination mirrors Callout, trigger slots included.
for _, key in ipairs({ "C", "D", "E", "F", "G", "H" }) do ns.DefaultMenu.Y.variants.GROUP[key] = ns.DefaultMenu.Y[key] end
ns.DefaultMenu.A.variants = {
	RAID = { label = "Incoming",
		A = { label = "2-3 inc {location}", text = "2-3 inc {location}" },
		X = { label = "4-6 inc {location}", text = "4-6 inc {location}" },
		Y = { label = "Big INC {location}!", text = "Big INC {location}!" },
	},
}

-- The LFG tab answers a Looking For Group listing with the player's role.
ns.DefaultMenu.A.variants.LFG = { text = "{LEVEL} {CLASS} DPS" }
ns.DefaultMenu.X.variants.LFG = { text = "{LEVEL} {CLASS} HEALS" }
ns.DefaultMenu.Y.variants.LFG = { text = "{LEVEL} {CLASS} TANK" }

-- These replacements keep the same button paths as the generic BG menu.
ns.DefaultMenu.A.variants.RAID.battlegrounds = {
	[489] = { label = "Flag route",
		A = { label = "Flag going ramp", text = "Flag going ramp!" },
		X = { label = "Flag going tunnel", text = "Flag going tunnel!" },
		Y = { label = "Flag going graveyard", text = "Flag going graveyard!" },
	},
}
ns.DefaultMenu.X.variants.RAID.battlegrounds = {
	[489] = { label = "Flag support",
		A = { label = "Escort our carrier", text = "Escort our flag carrier!" },
		X = { label = "Intercept enemy carrier", text = "Intercept the enemy flag carrier!" },
		Y = { label = "Return our flag", text = "Return our flag!" },
	},
}
