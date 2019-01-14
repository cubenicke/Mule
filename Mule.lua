--[[
Mule, a helper for raiders

Written by CubeNicke aka Yrrol

-- Role: Raider
/mule profile [<profile>] - Create a profile of current inventory of consumables/items
/mule activate <name> - Activate profile
/mule show [<profile>] - show a specific profile
/mule profiles - show available profiles
/mule remove <profile> - remove a profile
/mule supply - resupply items (at bank or at vendor)
/mule unload - store excess items for current profile (at bank)

-- Role: Farmer
/mule register <mule name> - register a mule
/mule <name> <itemname>|<type> - add item filter to a mule, a name or type of items
/mule registered - list of mules 
/mule unregister <name> - remove a mule
/mule unload - send excess items to mules (at mailbox)
/mule synq <name> - synq known mules with another player on another account

-- Role: Mule
/mule supply <name> - Restock a raider get his inventories via same account or via party/whispers, send items via mail (at mailbox)
]]--

--------------------------------------
-- Definitions
local BankBags = {-1, 5, 6, 7, 8, 9, 10}
local PersonalBags = {0, 1, 2, 3, 4}
--------------------------------------
-- Locals
local _G, _M = getfenv(0)
local curSupplyName = nil
local MuleMail = { okToSend = false, lastSend = 0 }
local Mule_Dragged = nil
local atVendor = false
local atMail = false
local atBank = false
local inCombat = false
local altTriggered = 0
local MailOpened = false
--------------------------------------
-- Key Bindings
BINDING_NAME_MULES = "Show Mules"
BINDING_NAME_PROFILES = "Show Profiles"
BINDING_HEADER_MULE = "Mule"
--------------------------------------
-- returned dragged item
function Mule_getDragged()
	return Mule_Dragged
end
--------------------------------------
-- check if bag is a bank bag
local function isBankBag(bag)
	for _,v in pairs(BankBags) do
		if v == bag then
			return true
		end
	end
	return false
end
--------------------------------------
-- Output helpers
local debug = false

-- Print message
local function Print(msg)
	if (not DEFAULT_CHAT_FRAME) then
		return
	end
	DEFAULT_CHAT_FRAME:AddMessage("Mule: "..(msg or ""))
end

-- Print debug message
local function Debug(msg) 
	if (not debug or not DEFAULT_CHAT_FRAME) then
		return
	end
	DEFAULT_CHAT_FRAME:AddMessage("MuleDbg: "..(msg or ""))
end

-- toggle debug output
local function toggleDebug()
	debug = not debug
	return debug
end
--------------------------------------
-- Lock functions for bag positions, since locked isn't set until server locks it
-- thanks to nnn
local slotLocks = {}

-- Lock slot for nn seconds
local function lockPosition(container,position)
	local slots = slotLocks[container] or {}
	if not slotLocks[container] then 
		slotLocks[container] = slots
	end
	slots[position] = GetTime()
end

-- Check if slot is locked by internal lock
local function isLocked(container,position)
	local slots = slotLocks[container]
	if not slots then
		return false
	end
	return GetTime() - (slots[position] or 0) < 2
end
--------------------------------------
local function fixName(name)
	return strupper(string.sub(name, 1, 1))..strlower(string.sub(name, 2))
end

--------------------------------------
-- Get info from tooltip
function TooltipInfo(container, position)
	local chargesPattern = '^' .. gsub(gsub(ITEM_SPELL_CHARGES_P1, '%%d', '(%%d+)'), '%%%d+%$d', '(%%d+)') .. '$'

	MuleTooltip:SetOwner(UIParent, 'ANCHOR_NONE')
	MuleTooltip:ClearLines()
	MuleTooltip:SetBagItem(container, position)

	local charges, usable, soulbound, quest, conjured, bop, requires
	for i = 1, MuleTooltip:NumLines() do
		local text = getglobal('MuleTooltipTextLeft' .. i):GetText()
		local _, _, chargeString = strfind(text, chargesPattern)
		if chargeString then
			charges = tonumber(chargeString)
		elseif strfind(text, '^' .. ITEM_SPELL_TRIGGER_ONUSE) then
			usable = true
		elseif text == ITEM_SOULBOUND then
			soulbound = true
		elseif text == ITEM_BIND_QUEST then
			quest = true
		elseif text == ITEM_CONJURED then
			conjured = true
		elseif text == ITEM_BIND_ON_PICKUP then
			bop = true
		end
		if strfind(text, '^' .. "Requires ") then
			local s = { "Alchemy", "Enchanting", "Tailoring", "Leatherworking", "Engineering", "Blacksmithing", "Cooking"}
			for _,v in s do
				if strfind(text, v) then
					requires = v
				end
			end
		end
	end

	return charges or 1, usable, soulbound, quest, conjured, bop, requires or ""
end
--------------------------------------
-- Get item id from a link
local function getIdFromLink(link)
	local _, _, Color, Ltype, Id, Enchant, Gem1, Gem2, Gem3, Gem4, Suffix, Unique, LinkLvl, Name = string.find(link, "|?c?f?f?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(%-?%d*):?(%-?%d*):?(%d*):?(%d*):?(%-?%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?")
	return tonumber(Id), Name
end
--------------------------------------
-- Get item id from bag position
local function ItemID(container, position)
	local link = GetContainerItemLink(container, position)
	if link then
		return getIdFromLink(link)
	end
	return nil
end
--------------------------------------
function Mule_GetItemFromName(name)
	for _, container in pairs(PersonalBags) do
		for position = 1, GetContainerNumSlots(container) do
			local itemId = ItemID(container, position)
			if itemId then
				local item = Mule_GetItem(itemId)
				if item.name == name then
					return item
				end
			end
		end
	end
end
--------------------------------------
-- Get item info from id
function Mule_GetItem(id)
	if id == nil then
		return nil
	end
	local name, link, quality, _, type, subType, stack, invType = GetItemInfo(id)
	if not link then
		Print("Failed to find id '"..id.."'")
		return nil
	end
	for _, container in pairs(PersonalBags) do
		for position = 1, GetContainerNumSlots(container) do
			local charges, usable, soulbound, quest, conjured, bop, requires = TooltipInfo(container, position)
			local itemId = ItemID(container, position)
			if itemId and tonumber(itemId) == id then
				local item = {}
				item.id = id
				item.name = name
				item.link = link
				item.type = type
				item.quality = quality
				item.subtype = subtype
				item.stack = stack
				item.charges = charges
				item.soulbound = soulbound
				item.quest = quest
				item.bop = bop
				item.conjured = conjured
				item.requires = requires
				return item
			end
		end
	end
	return nil
end
--------------------------------------
-- Get current inventory
local function getCurrentInventory(name)
	-- Get items in bags
	local inventory = {}

	if name == nil or name == UnitName("player") then
		for _, container in pairs(PersonalBags) do
			for position = 1, GetContainerNumSlots(container) do
				local itemId = ItemID(container, position)
				if itemId ~= nil then
					local _, count = GetContainerItemInfo(container, position)
					Debug("Found "..tostring(count).." x "..tostring(itemId).." on "..tostring(container).." "..tostring(position))
					inventory[tonumber(itemId)] = (inventory[tonumber(itemId)] or 0) + count
				end
			end
		end
		return inventory
	else
		if Mule["players"][name] then
			Print("Checking player on same account "..name)
			for k,v in pairs(Mule["players"][name]["bags"]) do
				for ix,item in pairs(Mule["players"][name]["bags"][k]) do
					Debug("Found "..tostring(item.id).." "..tostring(item.count or item.no).." on "..tostring(k).." "..tostring(ix))
					inventory[tonumber(item.id)] = (inventory[tonumber(item.id)] or 0) + (item.count or item.no)
				end
			end
		else
			return nil
		end
		return inventory
	end
	return nil
end
--------------------------------------
-- Save current bag content...
local function saveBags()
	local bags = {}
	local name = UnitName("player")
	for _, container in pairs(PersonalBags) do
		local contents = {}
		bags[container] = contents
		for position = 1, GetContainerNumSlots(container) do
			local item = ItemID(container, position)
			if item then
				local _, _count = GetContainerItemInfo(container, position)
				contents[position] = { id = tonumber(item), count = _count }
			end
		end
	end
	Mule["players"][name]["bags"] = bags
end

--------------------------------------
-- send cursor item to...
local function SendMailItem(name, id)
	local name2, texture, count, quality = GetSendMailItem(1)
	local item = Mule_GetItem(id)
	if not name then
		Print("Trying to send to no name")
		return false
	end
	if not item or not name2 then
		return false
	end
	local title
	if name2 and ((count or 0) > 1) then
		title = name2.." x "..count
	else
		title = name2 or "Mule mail"
	end
	Print("Sending to "..name.." "..title)
	SendMail(name, title)
	return true
end
--------------------------------------
local sendQueue = {}

-- Add an item x count to the send queue 
local function addSendQueue(_name, _id, _count)
	tinsert(sendQueue, {name = _name, id = _id, count = _count})
end
--------------------------------------
-- Send a mail with items in...
local sendCorrect = false
function sendItem(name, item, count)
	local is_SendMailFrame_Shown = SendMailFrame:IsShown();
	if not is_SendMailFrame_Shown then
		-- Delay first mail sent
		MuleMail.lastSend = GetTime() + 5
		MailFrameTab2:Click()
		MailOpened = true
		return 0
	end
	for _, container in pairs(PersonalBags) do
		for position = 1, GetContainerNumSlots(container) do
			local i = ItemID(container, position)
			if i and tonumber(i) == item and count > 0 then
				Debug("Found item in bag "..tostring(i).." vs "..tostring(item).." "..tostring(count))
				local _, c = GetContainerItemInfo(container, position)
				if count < c then
					Print("Spliting stack "..tostring(c).." "..tostring(count))
					if atMail then
						local _, dst_container, dst_position = MoveTo(false, container, position, count)
						if dst_container ~= nil and dst_position ~= nil then
							UseContainerItem(dst_container, dst_position)
							if SendMailItem(name, tonumber(i)) then
								Debug("Sending stack "..tostring(c).." "..tostring(count))
							else
								return 0
							end
						end
						return count
					else
						Print("Unhandled split")
					end
				elseif count >= c then
					UseContainerItem(container, position)
					if atMail then
						if SendMailItem(name, tonumber(i)) then
							Debug("Sending stack "..tostring(c).." "..tostring(count))
							count = count - c
						else
							return 0
						end
						return c
					elseif atVendor or atBank then
						local itm = Mule_GetItem(i)
						Print("Unloading "..itm.name.." x "..tostring(c))
						count = count - c
					end
				end
			end
		end
	end
	sendCorrect = false
	Debug("No items in bags "..tostring(item))
	return -1
end

------------------------------------------------
-- try empty the q of items to send
local function sendFromQueue()
	local inq = false
	for k, v in pairs(sendQueue) do
		if not v or v.name == nil or v.count <= 0 then
			sendQueue[k] = nil
			Debug("Dropping from Queue, no name or no count")
			return true
		end
		Debug("Send "..tostring(v.id).." x"..tostring(v.count).." to "..v.name)
		local c = sendItem(v.name, v.id, v.count)
		if c > 0 then
			v.count = v.count - c
			if v.count <= 0 then
				sendQueue[k] = nil
			end
			return true
		elseif c < 0 then
			sendQueue[k] = nil
		else
			inq = true
		end
	end
	return inq
end
------------------------------------------------
local function numInQueue()
	local num = 0
	for _,_ in pairs(sendQueue) do
		num = num + 1
	end
	return num
end
local function isQueueEmpty()
	for _,_ in pairs(sendQueue) do
		return false
	end
	return true
end

------------------------------------------------
-- return if item is mailable
function isMailable(id)
	local item = Mule_GetItem(id)
	if item and (item.quest or item.soulbound or item.bop) then
		Debug(item.name.." can't be mailed")
		return false
	end
	return true
end
------------------------------------------------
-- Authenticate that name is ok with current player
local function checkAuthor(player, name)
	if not name then
		return false
	end
	local n = name
	for k,v in pairs(Mule["players"][player]["mules"]) do
		if k == n then
			return true
		end
	end
	for k, v in pairs(Mule["players"]) do
		if k == n then
			return true
		end
	end
	if curSupplyName ~= nil and curSupplyName == n then
		return true
	end
	return false
end
------------------------------------------------
-- Raider
------------------------------------------------
-- Create a new profile or update existing
function createProfile(profile)
	local name = UnitName("player")
	-- Remove all items for profile
	if Mule["players"][name]["active"] == nil then
		if not profile then
			profile = "base"
		end
		Mule["players"][name]["active"] = profile
	elseif not profile then
		profile = Mule["players"][name]["active"]
	end
	Mule["players"][name]["profiles"][profile] = {}
	local inv = Mule["players"][name]["profiles"][profile]
	local curInv = getCurrentInventory()
	for k,v in pairs(curInv) do
		item = Mule_GetItem(k)
		if item then
			Debug("Adding "..tostring(k).." "..item.name)
			item.count = v
			inv[k] = item
		end
	end
	Print("Inventory updated")
	return true
end

-- Empty an existing profile
function removeProfile(profile)
	local name = UnitName("player")
	if profile == "base" then
		Print("Not allowed to remove base profile")
		return
	end
	for k, v in pairs(Mule["players"][name]["profiles"]) do
		if k == profile then
			Print("Removing profile: "..profile)
			Mule["players"][name]["profiles"][profile] = nil
			if Mule["players"][name]["active"] == profile then
				Mule["players"][name]["active"] = base
			end
			return
		end
	end
	Print("Profile doesn't exists")
	return
end

-- Set an existing profile as active
function Mule_ActivateProfile(profile)
	local name = UnitName("player")
	for k, v in pairs(Mule["players"][name]["profiles"]) do
		if k == profile then
			Print("Setting active profile: "..profile)
			Mule["players"][name]["active"] = profile
			return
		end
	end
	Print("Profile doesn't exists")
	return
end

-- Get item from a profile
function Mule_GetItemFromProfile(player, name)
	for k, v in pairs(Mule["players"][player]["profiles"]) do
		for l,s in pairs(Mule["players"][player]["profiles"][k]) do
			if s.name == name then
				return s
			end
		end
	end
	return nil
end

-- Remove a complete profile
function Mule_RemoveProfile(player, profile)
	for k, v in pairs(Mule["players"][player]["profiles"]) do
		if k == profile then
			Mule["players"][player]["profiles"][k] = nil
			Mule["players"][player]["profiles"][k].count = 0
			return true
		end
	end
	return false
end
-- Remove item from profile
function Mule_RemoveFromProfile(player, profile, name)
	for k, v in pairs(Mule["players"][player]["profiles"]) do
		if k == profile then
			for l,s in pairs(Mule["players"][player]["profiles"][k]) do
				Debug("Profileitem "..s.name)
				if s.name == name then
					Print("Removing "..name.." from "..k)
					Mule["players"][player]["profiles"][k][l] = nil
					return id
				end
			end
			Print("Not in profile "..name)
			return 0
		end
	end
	Debug("No profile exists for this player "..profile.. "player "..player)
	return 0
end

-- list profiles
local function listProfiles(name)
	if Mule["players"][name] == nil or Mule["players"][name]["profiles"] == nil then
		return false
	end
	Print("Showing profiles for: "..name)
	for k,v in pairs(Mule["players"][name]["profiles"]) do
		if k == Mule["players"][name]["active"] then
			Print(k .. " (Active)")
		else
			Print(k)
		end
	end
	return true
end

-- Show available profiles or content of a specific profile
local function showProfile(name, profile)
	if Mule["players"][name] == nil or Mule["players"][name]["profiles"] == nil then
		return false
	end
	if profile == nil then
		profile = Mule["players"][name]["active"]
	end
	Print("Showing profile: "..profile)
	for k,v in pairs(Mule["players"][name]["profiles"][profile]) do
		Print(v.name.." = "..tostring(v.count))
	end
	return false
end

-- create tree for showing profiles in frame
function Mule_ShowProfiles(name)
	local view = {}
	if Mule["players"][name] == nil or Mule["players"][name]["profiles"] == nil then
		return false
	end
	for k,v in pairs(Mule["players"][name]["profiles"]) do
		local key
		if k == Mule["players"][name]["active"] then
			key = k.." (Active)"
			collapsed = false
		else
			key = k
			collapsed = true
		end
		view[key] = {}
		view[key].collapsed = collapsed
		for l,s in pairs(Mule["players"][name]["profiles"][k]) do
			tinsert(view[key], s.name.." x "..tostring(s.count))
		end
		table.sort(view[key])
	end
	MuleFrame_SetTree(view, "PROFILE")
	if not MuleFrame:IsVisible() then
		ShowUIPanel(MuleFrame)
	end 
end

-- Find profiles where item exists
function findProfiles(item)
	local name = UnitName("player")
	local ps = {}
	for k,v in pairs(Mule["players"][name]["profiles"]) do
		for l,s in pairs(Mule["players"][name]["profiles"][k]) do
			if s.name == item.name then
				ps[k] = s.count
			end
		end
	end
	return ps
end

-- Add a item to a profile
function Mule_AddToProfile(player, profile, id, count)
	if Mule["players"][player] == nil or Mule["players"][player]["profiles"] == nil then
		Print("Can't find player"..player)
		return 0
	end
	if Mule["players"][player]["profiles"][profile] == nil then
		Print("Can't find profile "..profile)
		return 0
	end
	if Mule["players"][player]["profiles"][profile][id] and Mule["players"][player]["profiles"][profile][id].count and Mule["players"][player]["profiles"][profile][id].count + count >= 0 then
		Mule["players"][player]["profiles"][profile][id].count = Mule["players"][player]["profiles"][profile][id].count + count
	else
		local item = Mule_GetItem(id)
		if not item then
			return 0
		end
		Mule["players"][player]["profiles"][profile][id] = item
		Mule["players"][player]["profiles"][profile][id].count = count
	end
	return Mule["players"][player]["profiles"][profile][id].count
end

-- Helper to move item to pesonal bags
function MoveTo(toBank, src_container, src_position, dest_count)
	-- sort item into bag 
	local _, src_count, srcLocked = GetContainerItemInfo(src_container, src_position)
	local src_id = ItemID(src_container, src_position)
	local found = false
	local insertitem = false
	local item = Mule_GetItem(src_id)
	local copy_count = 0
	ClearCursor()
	Debug("Pickup "..tostring(src_id).." bag: "..tostring(src_container)..", "..tostring(src_position).." "..tostring(src_count).." "..tostring(dest_count))
	if srcLocked or isLocked(src_container, src_position) then
		Debug("Locked")
		return 0
	end
	if not src_count or not dest_count then
		Debug("no count")
		return 0
	end
	if src_count > dest_count then
		copy_count = dest_count
		SplitContainerItem(src_container, src_position, dest_count)
	else
		copy_count = src_count
		PickupContainerItem(src_container, src_position)
	end
	local dstBags
	if toBank then
		dstBags = BankBags
	else
		dstBags = PersonalBags
	end
	lockPosition(src_container, src_position)
	if not toBank and isBankBag(src_container) then
		PutItemInBackpack()
	else
		-- since we want to split item then only put in empty slot or copying to bank
		for _, container in pairs(dstBags) do
			for position = 1, GetContainerNumSlots(container) do
				local _, count, dstLocked = GetContainerItemInfo(container, position)
				local id = ItemID(container, position)
				if not dstLocked and not isLocked(container, position) then
					if id == nil then
						Debug("Placing in "..tostring(container)..", "..tostring(position).." "..tostring(copy_count).." "..tostring(count))
						PickupContainerItem(container, position)
						if not CursorHasItem() then
							Debug("Placed in bank")
							lockPosition(container, position)
							return copy_count, container, position
						else
							Debug("Failed to place in bank")
						end
						return copy_count
					end
				end
			end
		end
		-- No empty slot found
		Print("Error: bags full")
		return copy_count
	end
	return copy_count
end

-- find items and move to/from bank
function moveItem(tobank, id, idcount)
	local srcBags
	if tobank then
		srcBags = PersonalBags
	else
		srcBags = BankBags
	end
	for _, container in pairs(srcBags) do
		for position = 1, GetContainerNumSlots(container) do
			local itemId = ItemID(container, position)
			if itemId and tonumber(itemId) == id then
				local _, count = GetContainerItemInfo(container, position)
				local item = Mule_GetItem(id)
				if count >= idcount then
					local n = MoveTo(tobank, container, position, idcount)
					if item then
						Print("Moving "..tostring(idcount).." "..(item.name or "").." (Moved "..tostring(n)..")")
					end
					idcount = idcount - n
				else
					local n = MoveTo(tobank, container, position, count)
					if item then
						Print("Moving "..tostring(idcount).." "..(item.name or "").." (Moved "..tostring(n)..")")
					end
					idcount = idcount - n
				end
				if idcount == 0 then
					return 0
				end
			end
		end
	end
	return idcount
end

-- Find those items that we have too much of
function findWhatsExcess(mailable)
	local inv = getCurrentInventory()
	local name = UnitName("player")
	local noe = 0
	local excess = {}
	if Mule["players"][name]["active"] == nil then
		Print("Need to activate a profile before unloading")
		return
	end
	local active = Mule["players"][name]["active"]
	local check = Mule["players"][name]["profiles"][active]
	for s, t in pairs(inv) do
		for k, v in pairs(check) do
			if tonumber(v.id) == s then
				inv[s] = inv[s] - v.count
			end
		end
		if inv[s] > 0 then
			Debug("Extra items "..tostring(s))
			if (not mailable) or isMailable(s) then
				excess[s] = inv[s]
				noe = noe + 1
			end
		end
	end
	return noe, excess
end

-- Compare inventory with saved profile to see whats missing
local function findWhatsMissing(name)
	local inv = getCurrentInventory(name)
	local diff = {}
	local diffs = 0
	if name == nil then
		name = UnitName("player")
	elseif inv == nil then
		Debug("No inventory found")
		return 0, nil
	elseif Mule["players"][name] == nil then
		Debug("player doesn't exists")
		return 0, nil
	end
	local active = Mule["players"][name]["active"]
	if active == nil then
		Print("Player have no active profile")
		return 0, nil
	end
	local check = Mule["players"][name]["profiles"][active]
	if check == nil then
		return 0, nil
	end
	for k, v in pairs(check) do
		local found = false
		for s, t in pairs(inv) do
			if tonumber(v.id) == tonumber(s) then
				inv[s] = (v.count or 0) - (inv[s] or 0)
				found = true
			end
		end
		if found == false then
			Debug("Not found "..tostring(v.count).." of "..tostring(k))
			diff[k] = v.count
			diffs = diffs + 1
		elseif inv[k] > 0 then
			diff[k] = inv[k]
			diffs = diffs + 1
		end
	end
	return diffs, diff
end

-- Some item might exist in bank then 
local function supplyFromBank()
	-- We know the inv check bank items and try refill them
	Print("Supply from bank")
	local diffs, diff = findWhatsMissing(UnitName("player"))
	if diffs == 0 then
		Print("Inventory ok")
		return true
	end
	-- find items corresponding to diff in bank and move to bags
	local fail = 0
	for k, v in pairs(diff) do
		fail = fail + moveItem(false, k, v)
	end
	--return fail == 0
	return 0
end

local function handleLockedItem()
	for _, container in pairs(PersonalBags) do
		for position = 1, GetContainerNumSlots(container) do
			local _,_,locked = GetContainerItemInfo(container, position)
			if locked then
				local link = GetContainerItemLink(container, position)
				local id = getIdFromLink(link)
				local item = Mule_GetItem(id)
				if item then
					Mule_Dragged = item.name
				end
				return
			end
		end
	end
	Mule_Dragged = nil
end

-- check if merchant have items that are missing, if so buy em
local function supplyFromVendor()
	-- We know the inv check vendor items and try refill them
	Print("Supply from vendor")
	local diffs, diff = findWhatsMissing(UnitName("player"))
	if diffs == 0 then
		Print("Inventory ok")
		return true
	end
	-- find items corresponding to diff in bank and move to bags
	local fail = 0
	for index=1, GetMerchantNumItems() do
		local link = GetMerchantItemLink(index)
		if link then
			local found	= false
			local name, _, price, quantity, numAvailable, _, _ = GetMerchantItemInfo(index)
			local _, _, _, _, id, _, _, _, _, _, _, _, _, _ = string.find(link, "|?c?f?f?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(%-?%d*):?(%-?%d*):?(%d*):?(%d*):?(%-?%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?")
			Debug("Found id: "..tostring(id).." "..name..tostring(quantity))
			for k, v in pairs(diff) do
				if tonumber(k) == tonumber(id) then
					local amount = math.floor(v / quantity)
					found = true
					if amount and quantity then
						Print("Buying "..name.." x "..tostring(quantity * amount))
						for j = 1, amount do
							BuyMerchantItem(index)
						end
					end
				end
			end
			if not found then
				fail = fail + 1
			end
		end
	end
	if CanMerchantRepair() then
		RepairAllItems()
	end
	CloseMerchant()
	atVendor = false
	return fail == 0
end

-- Request diff from remote source if not remote function will fail
local function reqDiff(name, addon)
	-- return false if it is a local player
	local dest = nil
	for k,v in pairs(Mule["players"]) do
		if k == name then
			dest = name
		end
	end
	if dest == nil then
		if (UnitName("party1") or "") == name then
			if (addon) then
				SendAddonMessage("Mule", "Mule:DiffReq-"..name, "PARTY")
			else
				SendChatMessage("Mule:DiffReq-"..name, "PARTY", nil, name)
			end
		elseif UnitLevel("player") >= 10 then
			SendChatMessage("Mule:DiffReq-"..name, "WHISPER", nil, name)
		else
			Print("Inviting "..name)
			InviteByName(name)
		end
		return true
	end
	return false
end

-- Supply player via trade interface
local function supplyViaTrade(name)
	-- First get the inv by asking the recipient what it he wants or if he exists on the same account
	if name == UnitName("player") then
		Print("Can only supply to self at bank")
		return false
	end
	curSupplyName = name
	local remote = reqDiff(name, true)
	if not remote then
		-- Impossible to trade to local player (on same account)
		curSupplyName = nil
		return false
	end
	-- TODO implement trade action
	return false
end

-- Supply player at mailbox
local function supplyViaMail(name)
	-- The inv needs to be gotten through whispers or if it's on the same account 
	curSupplyName = name
	local fail = 0
	local remote = reqDiff(name, true)
	if remote then
		return true
	end
	curSupplyName = nil
	local diffs, diff = findWhatsMissing(name)
	if diffs == 0 then
		Print("Inventory Ok")
		return true
	end
	for k, v in pairs(diff) do
		addSendQueue(name, k, v)
	end
	return true
end

-- Output diff compared to active profile to console
local function handleDiff(name)
	if name == nil or name == "" then
		name = UnitName("player")
	end
	local diffs, diff = findWhatsMissing(name)
	if diffs == 0 then
		Print("Inventory Ok")
		return true
	end
	for k, v in pairs(diff) do
		local item = Mule_GetItem(k)
		if item then
			Print(item.name.." "..k.." x "..tostring(v))
		else
			Print("<NN> "..k.." x "..tostring(v))
		end
	end
	return true
end

-- Output diff compared to active profile to console
local function handleExcess(name)
	if name == nil or name == "" then
		name = UnitName("player")
	end
	local diffs, diff = findWhatsExcess(false)
	if diffs == 0 then
		Print("Inventory Ok")
		return true
	end
	for k, v in pairs(diff) do
		local item = Mule_GetItem(k)
		if item then
			Print(item.name.." "..k.." x "..tostring(v))
		else
			Print("<NN> "..k.." x "..tostring(v))
		end
	end
end


-- call the correct supplier
local function supply(name)
	-- Try refill name with consumables
	if atBank then
		if supplyFromBank() then
			if _G.SortBags ~= nil and _G.SortBankBags ~= nil then
				_G.SortBags()
				_G.SortBankBags()
			end
			return
		end
	end
	if atVendor then
		if supplyFromVendor() then
			if _G.SortBags ~= nil then
				_G.SortBags()
			end
			return
		end
	end
	if atMail then
		if supplyViaMail(name) then
			return
		end
	end
	--TODO
	--if supplyViaTrade(name) then
	--	return
	--end
	if _G.SortBags ~= nil and _G.SortBankBags ~= nil then
		_G.SortBags()
		if atBank then
			_G.SortBankBags()
		end
	end
	Print("Supplied "..name)
end

-- helper for slash supply
local function supplyHandler(options)
	local name = UnitName("player")
	if options ~= nil and options ~= "" then
		name = fixName(options)
		if not atMail then
			Print("Need to be at mailbox to supply another player")
			return
		elseif name == UnitName("player") then
			Print("Can't supply self at mailbox")
			return
		end
	elseif not atBank and not atVendor then
		Print("Need to be at bank or vendor to supply self")
		return
	end
	supply(name)
end
------------------------------------------------
-- Mule
------------------------------------------------

-- output mules for player
local function listMules(player)
	Print("Listing mules:")
	for k,v in pairs(Mule["players"][player]["mules"]) do
		Print(k)
		for l,w in pairs(v) do
			if l ~= "collapsed" then
				Print("  "..tostring(w))
			end
		end
	end
end

-- Remove a mule
function Mule_UnRegister(player, name)
	for k,v in pairs(Mule["players"][player]["mules"]) do
		if k == name then
			Mule["players"][player]["mules"][name] = nil
			Print("Removed mule: "..name)
			if MuleFrame and MuleFrame:IsShown() then
				MuleFrame_SetTree(Mule["players"][UnitName("player")]["mules"], "MULE")
			end
			return
		end
	end
	Print("Mule doesn't exist: "..name)
end

-- Add mule
local function registerMule(player, name)
	if Mule["players"][player]["mules"][name] == nil then
		Print("Registring mule: "..name)
		Mule["players"][player]["mules"][name] = {}
	else
		Print("Mule already exists: "..name)
	end
end

-- add filter to mule
function Mule_AddToMule(player, name, filter)
	local id = getIdFromLink(filter)
	local item = nil
	if not id or id == 0 then
		item = Mule_GetItemFromName(filter)
	end
	if not item then
		item = Mule_GetItem(id)
	end
	if Mule["players"][player]["mules"][name] == nil then
		Print("Mule doesn't exists: "..name)
		if id and id > 0 then
			Mule["players"][player]["mules"][name] = {}
		else
			return false
		end
	end
	if item then
		filter = item.name
		if item.bop then
			Print("Item is Bind on Pickup")
			return false
		elseif item.soulbound then
			Print("Item is soulbound")
			return false
		elseif item.quest then
			Print("Quest item can't be filter")
			return false
		end
	end
	for _, v in pairs(Mule["players"][player]["mules"][name]) do
		if v == filter then
			Print("Filter already exists")
			return false
		end
	end
	Print("Adding filter to mule: "..name..", "..filter)
	tinsert(Mule["players"][player]["mules"][name], filter)
	if MuleFrame and MuleFrame:IsShown() then
		MuleFrame_SetTree(Mule["players"][UnitName("player")]["mules"], "MULE")
	end
	return true
end

-- Remove filter from mule
function Mule_RemoveFromMule(player, mule, filter)
	if Mule["players"][player]["mules"][mule] == nil then
		return false
	end
	for k, v in pairs(Mule["players"][player]["mules"][mule]) do
		if v == filter then
			Mule["players"][player]["mules"][mule][k] = nil
			Print("Removed "..filter.." from "..mule)
			if MuleFrame and MuleFrame:IsShown() then
				MuleFrame_SetTree(Mule["players"][UnitName("player")]["mules"], "MULE")
			end
			return true
		end
	end
end

-- find Mules
local function findMules(item)
	local mules = {}
	for m,v in pairs(Mule["players"][UnitName("player")]["mules"]) do
		for n,f in pairs(v) do
			if m == UnitName("player") then
				Debug("self is mule for item")
			elseif item.soulbound then
				Debug("soulbound item "..item.name)
			elseif item.quest then
				Debug("quest item "..item.name)
			elseif item.bop then
				Debug("BOP item "..item.name)
			elseif "default" == f then
				tinsert(mules, m)
			elseif item.name == f then
				tinsert(mules, m)
			elseif ((not (item.type == "")) and item.type == f) or (not (item.requires == "")) and item.requires == f then
				Debug("Type is matching "..item.type)
				tinsert(mules, m)
			end
		end
	end
	return mules
end
------------------------------------------------
-- Farmer
------------------------------------------------
local function unload()
	local count = 0
	if not atBank and not atMail and not atVendor then
		Print("Need to be at mailbox to unload to other players, at Bank and Vendor will unload excess items")
		return 0
	end

	local noe, excess = findWhatsExcess(atMail)

	if noe == 0 then
		Print("Didn't find any excess items")
		return 0
	end
	
	for id,c in pairs(excess) do
		local item = Mule_GetItem(tonumber(id))
		Debug("Excess item "..item.name)
		if atMail and item.quality == 0 then
			Debug("Not mailing Gray items "..item.name)
		elseif atBank then
			if moveItem(true, item.id, c) == 0 then
				count = count + 1
			end
		else
			for m,v in pairs(Mule["players"][UnitName("player")]["mules"]) do
				if ((atMail and (m ~= "vendor")) or (atVendor and m == "vendor")) and item then
					for n,f in pairs(v) do
						if m == UnitName("player") then
							Debug("self is mule for item")
						elseif item.soulbound then
							Debug("soulbound item "..item.name)
						elseif item.quest then
							Debug("quest item "..item.name)
						elseif item.bop then
							Debug("BOP item "..item.name)
						elseif "default" == f then
							addSendQueue(m, item.id, c)
						elseif item.name == f then
							Debug("Name is matching "..item.name)
							count = count + 1
							if atVendor then
								sendItem(nil, tonumber(item.id), c)
							elseif atMail then
								addSendQueue(m, tonumber(item.id), c)
							end
						elseif ((not (item.type == "")) and item.type == f) or (not (item.requires == "")) and item.requires == f then
							Debug("Type is matching "..item.type)
							count = count + 1
							if atVendor then
								sendItem(nil, tonumber(item.id), c)
							elseif atMail then
								--selltovendor
								addSendQueue(m, tonumber(item.id), c)
							end
						else
							Debug("Not matching")
						end
					end
				end
			end
		end
	end
	return count
end

-------------------------------------------
local function handleLink(link)
	local _, _, itemID, enchantID, suffixID, uniqueID = strfind(link, 'item:(%d+):(%d*):(%d*):(%d*)')
	local item = nil
	if itemID and (tonumber(itemID) or 0) > 0 then
		item = Mule_GetItem(tonumber(itemID))
		Print(tostring(itemID))
	elseif link and (tonumber(link) or 0) > 0 then
		item = Mule_GetItem(tonumber(link))
		Print(tostring(link))
	else
		return false
	end
	if item then
		Print(item.name)
		Print(item.type)
		--Print(item.quality)
		if item.requires ~= "" then
			Print(item.requires)
		end
		-- Print Mules
		local ms = findMules(item)
		for _, v in pairs(ms) do
			Print("Registred mule "..v)
		end
		-- Print Profiles
		local ps = findProfiles(item)
		for k,v in pairs(ps) do
			if tonumber(v) > 1 then
				Print("Exists in profile "..k.." x "..v)
			else
				Print("Exists in profile "..k)
			end
		end
		return true
	end
	return false
end
-------------------------------------------
-- Init Mule
local MuleFrame = nil

function Mule_initSaves(arg)
	if Mule == nil then
		Mule = {}
		if Mule["players"] == nil then
			Mule["players"] = {}
		end
	end
	if MuleFrame == nil then
		CreateFrame('GameTooltip', 'MuleTooltip', nil, 'GameTooltipTemplate')
		MuleFrame = MuleFrame_Create()
		Print("by CubeNicke aka Yrrol @ vanillagaming")
	end
end

function Mule_checkVars()
	local name =UnitName("player")
	if Mule["players"][name] == nil then
		Mule["players"][name] = {}
		Mule["players"][name]["bags"] = {}
		Mule["players"][name]["profiles"] = {}
		createProfile()
	end
	if Mule["players"][name]["mules"] == nil then
		Mule["players"][name]["mules"] = { vendor = {}}
	end
end

-- refresh helper of muleframe (MULES)
local function Mule_RefreshMules()
	MuleFrame_SetTree(Mule["players"][UnitName("player")]["mules"], "MULE")
	if not MuleFrame:IsVisible() then
		ShowUIPanel(MuleFrame)
	end
end

-------------------------------------------

local slashcommands = {
	{ cmd = "activate", fn = function(args) Mule_ActivateProfile(args) Mule_ShowProfiles(UnitName("player")) end, help = "activate <profile> - sets profile as active, will show which items should be in bags"},
	{ cmd = "base", fn = function(args) createProfile() Mule_ShowProfiles(UnitName("player")) end, help = "base - update/create default profile base" },
	{ cmd = "help", fn = function(args) Mule_HelpHandler(args) end, help = "help [<cmd>]"},
	{ cmd = "list_mules", fn = function(args) listMules(UnitName("player")) end, help = "list_mules - console output mules" },
	{ cmd = "list_profiles", fn = function(args) listProfiles(UnitName("player")) end, help = "list_profiles - console output profiles"},
	{ cmd = "mules", fn = function(args) Mule_RefreshMules() end, help = "mules - show frame, to edit mules" },
	{ cmd = "profile", fn = function(args) createProfile(args); Mule_ShowProfiles(UnitName("player")); end, help = "profile <profile> - Create/update profile" },
	{ cmd = "profiles", fn = function(args) Mule_ShowProfiles(UnitName("player")) end, help = "profiles - show frame, to edit profiles" },
	{ cmd = "register", fn = function(args) registerMule(UnitName("player"), fixName(args)) MuleFrame_SetTree(Mule["players"][UnitName("player")]["mules"], "MULE") end, help = "register <mule> - register new mule" },
	{ cmd = "remove", fn = function(args) removeProfile(args); Mule_ShowProfiles(UnitName("player")); end, help = "remove <profile> - remove a profile" },
	{ cmd = "supply", fn = function(args) supplyHandler(fixName(args)) end, help = "supply [<player>] - supply player or self (only at Bank or at Vendor)" },
	{ cmd = "unload", fn = function(args) unload() end, help = "unload - sell to vendor store at bank or mail to mules" },
	{ cmd = "unregister", fn = function(args) Mule_UnRegister(UnitName("player"), fixName(args)) end, help = "unregister <mule> - Remove a mule" },
	-- Debugging
	{ cmd = "debug", fn = function(args) if toggleDebug() then Print("Debug is now on") else Print("Debug is now off") end end, help = "debug - toggle debug output" },
	{ cmd = "diff", fn = function(args) handleDiff(args) end, help = "diff - check item diff against active profile" },
	{ cmd = "excess", fn = function(args) handleExcess(args) end, help = "Excess - check items not in active profile" },
}

function Mule_HelpHandler(args)
	if args == "" then
		for _, v in pairs(slashcommands) do
			Print(v.cmd)
		end
	else
		for _, v in pairs(slashcommands) do
			if v.cmd == args and v.help then
				Print(v.cmd.." - "..v.help)
				return
			end
		end
	end
end

-- Handle slash commands
function Mule_Command(msg)
	local _, _, cmd, options = string.find(msg, "([%w%p]+)%s*(.*)$")
	local name = UnitName("player")
	local ocmd = cmd
	for _,v in pairs(slashcommands) do
		if v.cmd == cmd then
			v.fn(options)
			return
		end
	end
	-- Handle /mule <mule> <item>
	if handleLink(cmd) then
		return
	elseif Mule_AddToMule(name, fixName(ocmd), options) then
		MuleFrame_SetTree(Mule["players"][UnitName("player")]["mules"], "MULE")
		return
	end
	Print("Unknown command:")
	Print(msg)
end
------------------------------------------------
local function handleChat(msg, author, type, addon)

	if not msg then
		return false
	end
	local _,_,prefix = string.find(msg, "^(Mule:)")
	if not prefix then
		Debug("Faulty prefix")
		return false
	end
	if author == UnitName("player") then
		Debug("I am author "..msg.." "..author)
		return false
	end
	if not checkAuthor(UnitName("player"), author) then
		Print("Untrusted mule request from "..author)
		return false
	end
	local _,_,cmd,player = string.find(msg, "^Mule:(.+)-(.+)")
	if "EndDiff" == cmd then
		curSupplyName = nil
		if type == "PARTY" then
			LeaveParty()
		end
	elseif "Synq" == cmd then
		local i = 0, f
		i, _, mule = string.find(player, "(.*),")
		while true do
			i,_,f = string.find(player, ",(^,*)", i + 1)
			if i == nil then break end
			Mule_AddToMule(UnitName("player"), mule, f)
		end
	elseif "DiffReq" == cmd then
		if player == UnitName("player") then
			local diffs, diff = findWhatsMissing(player)
			Debug("Found "..tostring(diffs).." Missing items")
			for k, v in pairs(diff) do
				local send = "Mule:"..tostring(k)..":"..tostring(v).."-"..player
				if (addon) then
					SendAddonMessage("Mule", send, type)
				else
					SendChatMessage(send, type, nil, author)
				end
			end
			if (addon) then
				SendAddonMessage("Mule", "Mule:EndDiff-"..player, type)
			else
				SendChatMessage("Mule:EndDiff-"..player, type, nil, author)
			end
		else
			Print("Faulty diff request targeted to "..player)
		end
	else
		local _,_,k,v = string.find(cmd, "(%d+):(%d+)")
		if not k or not v then
			return false
		end
		addSendQueue(author, tonumber(k), tonumber(v))
	end
	return true
end
------------------------------------------------
--local errors = {{ "ERR_INV_FULL", "Inventory full"}}
local function handleErrorMessage(args)
	--TODO
	--for k,v in pair(errors) do
	--	if v[0] == args[1] then
	--		Print(v[1])
	--	end
	--if args[1] == "ERR_INV_FULL" then
	--end
	--(arg1 == ERR_MAIL_TO_SELF or arg1 == ERR_PLAYER_WRONG_FACTION or arg1 == ERR_MAIL_TARGET_NOT_FOUND or arg1 == ERR_MAIL_REACHED_CAP) then
	Debug("myErr:"..args[1])
end

------------------------------------------------
local function acceptSupplyRequest(leader)
	if checkAuthor(UnitName("player"), leader) then
		Print("Party invite accepted from "..(leader or ""))
		AcceptGroup()
	end
end
------------------------------------------------
-- Events
-----------------------------------------------

local events = {
	{ev = "ADDON_LOADED", fn = function (arg) Mule_initSaves(arg) end },
	{ev = "BAG_UPDATE", fn = function (arg) if not inCombat then saveBags() end end },
	{ev = "BANKFRAME_CLOSED", fn = function (arg) atBank = false end },
	{ev = "BANKFRAME_OPENED", fn = function (arg) atBank = true; atVendor = false end },
	{ev = "CHAT_MSG_PARTY", fn = function (arg) handleChat(arg[1], arg[2], "PARTY", false) end },
	{ev = "CHAT_MSG_WHISPER", fn = function (arg) handleChat(arg[1], arg[2], "WHISPER", false) end },
	{ev = "CHAT_MSG_ADDON", fn = function (arg) if (arg[1] == "Mule") then handleChat(arg[2], arg[4], arg[3], true) end end },
	{ev = "ITEM_LOCK_CHANGED", fn = function(arg) handleLockedItem() end },
	{ev = "MAIL_CLOSED", fn = function (arg) MuleMail.okToSend = false; atMail = false end},
	{ev = "MAIL_FAILED", fn = function (arg) MuleMail.okToSend = true end },
	{ev = "MAIL_SEND_SUCCESS", fn = function (arg) MuleMail.okToSend = true end },
	{ev = "MAIL_SHOW", fn = function (arg) atMail = true; atVendor = false end },
	{ev = "MERCHANT_CLOSED", fn = function (arg) atVendor = false end},
	{ev = "MERCHANT_SHOW", fn = function (arg) atVendor = true end },
	{ev = "MERCHANT_UPDATE", fn = function (arg) atVendor = true end },
	{ev = "PARTY_INVITE_REQUEST", fn = function (arg) acceptSupplyRequest(arg[1]) end },
	{ev = "PARTY_MEMBERS_CHANGED", fn = function (arg) StaticPopup_Hide("PARTY_INVITE") if curSupplyName then reqDiff(curSupplyName, true) end end },
	{ev = "PLAYER_ENTERING_WORLD", fn = function (arg) Mule_checkVars() end },
	{ev = "PLAYER_REGEN_ENABLED", fn = function (arg) inCombat = false end },
	{ev = "PLAYER_REGEN_DISABLED", fn = function (arg) inCombat = true end },
	{ev = "TRADE_ACCEPT_UPDATE", fn = function (arg) end },
	{ev = "TRADE_CLOSED", fn = function (arg) inTrade = false end },
	{ev = "TRADE_REQUEST", fn = function (arg) end },
	{ev = "TRADE_SHOW", fn = function (arg) inTrade = true end },
	{ev = "UI_ERROR_MESSAGE", fn = handleErrorMessage }
}

--Event hook
local lastEvent
function Mule_OnEvent(event)
	local args = {arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9}
	for _, ev in pairs(events) do
		if ev.ev == event then
			ev.fn(args)
			return
		end
	end
end

-- Update hook
function Mule_OnUpdate()
	if MuleMail.okToSend and atMail then
		if GetTime() > MuleMail.lastSend + 0.75 then
			if numInQueue() > 0 and sendFromQueue() == true then
				MuleMail.lastSend = GetTime()
				return
			elseif MailOpened and GetTime() > MuleMail.lastSend + 3 and numInQueue() == 0 then
				MailOpened = false
				CloseMail()
				if _G.SortBags ~= nil then
					_G.SortBags()
				end
				return
			end
			if (not MuleFrame or not MuleFrame:IsVisible()) and IsAltKeyDown() then
				if GetTime() > altTriggered + 5 then
					Print("Unloading")
					altTriggered = GetTime()
					unload()
				end
			end
		end
	elseif (not MuleFrame or not MuleFrame:IsVisible()) and (atVendor or atBank) then
		if IsAltKeyDown() then
			if GetTime() > altTriggered + 5 then
				Print("Unloading/Supplying")
				altTriggered = GetTime()
				unload()
				supply(UnitName("player"))
			end
		end
	end
end

-- low level init
function Mule_OnLoad()
	for _, ev in pairs(events) do
		this:RegisterEvent(ev.ev)
	end
	SlashCmdList["MULE"] = Mule_Command
	SLASH_MULE1 = "/mule"
end
