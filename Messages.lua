-- The default VGS menu shipped with the addon. Players edit their own copy in
-- the editor window (the "VGSEdit" macro); this table seeds it on first run
-- and on "Reset to defaults".
--
-- Each level is keyed by the button that picks it: A, X or Y (B is always Cancel).
-- A node with `text` is a message and sends immediately; a node without it is a
-- category that opens the next level, up to four presses deep, so "X then Y
-- then A" works the same as Tribes 2's "V G Y".
--
-- The selected Say, Group or Battleground tab determines where messages go.
-- `variants.GROUP` and `variants.RAID` replace options on the Group and
-- Battleground tabs; Battleground inherits Group, and false clears a slot.
-- A message can include an `emote` token and a {location} placeholder.
-- `battlegrounds[instanceID]` supplies a menu for a specific battleground.
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
			Y = { label = "Wave",    text = "Hello there!" },
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
ns.DefaultMenu.A.variants = {
	RAID = { label = "Incoming",
		A = { label = "2-3 inc {location}", text = "2-3 inc {location}" },
		X = { label = "4-6 inc {location}", text = "4-6 inc {location}" },
		Y = { label = "Big INC {location}!", text = "Big INC {location}!" },
	},
}

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
