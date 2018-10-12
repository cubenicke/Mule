--[[
MuleFrame.lua

Written by CubeNicke aka Yrrol

email: cubenicke@gmail.com

Purpose is to visualize some parts of Mule addon
Mules - list of all mules and their filters, also possible to add/remove item filters
Profiles - Possible to add/remove items to profiles and change the count
]]
local MFVars = {
	tree = nil,
	startRow = 1,
	noRows = 1,
	mode = "MULE",
	maxRows = 1,
	keepPos = false
	}

function MuleFrame_SetTree(_tree, mode)
	MFVars.tree = _tree
	MFVars.sorted = {}
	for k,_ in pairs(MFVars.tree) do table.insert(MFVars.sorted,k) end
	table.sort(MFVars.sorted, function(a,b) return string.lower(a) < string.lower(b) end)
	if not MFVars.keepPos then
		MFVars.startRow = 1
	end
	MFVars.keepPos = false
	MFVars.mode = mode
	MFVars.maxRows = 1
end

-- String split helper
local function splitOnFirst(input, pattern)
	local space = (string.find(input, pattern) or (string.len(input) + 1))
	return string.sub(input, 1, space - 1), string.sub(input, space + string.len(pattern))
end

-- change tree appearance
local function collapseRow(row)
	local r = 0
	local src_r = 0
	local dst_r = 0
	for _,k in pairs(MFVars.sorted) do
		local v = MFVars.tree[k]
		src_r = src_r + 1
		if src_r >= MFVars.startRow and dst_r < MFVars.noRows then
			dst_r = dst_r + 1
			if row == dst_r then
				v.collapsed = not v.collapsed
				return
			end
		end
		-- iterate childs if not collapsed to count up src_r and dst_r
		if v.collapsed == false then
			for l,m in pairs(v) do
				if l ~= "collapsed" then
					src_r = src_r + 1
					if src_r >= MFVars.startRow and dst_r < MFVars.noRows then
						dst_r = dst_r + 1
						if row == dst_r then
							-- trying to collapse a leaf in the tree
							return
						end
					end
				end
			end
		end
	end
	return
end

-- Parse tree for parent
local function getOwner(row)
	local r = 0
	local owner = nil
	for _,k in pairs(MFVars.sorted) do
		local v = MFVars.tree[k]
		r = r + 1
		owner = k
		if MFVars.startRow + row - 1 <= r then
			-- Clicked on Mule
			return nil
		end
		if v.collapsed == false then
			for l,m in pairs(v) do
				if l ~= "collapsed" then
					r = r + 1
					if MFVars.startRow + row - 1 <= r then
						return owner
					end
				end
			end
		end
	end
	return owner
end

-- add amount to an existing item count
local function addToProfile(row, frame, add)
	local profile = splitOnFirst(getOwner(row), " %(Active%)")
	local name = splitOnFirst(frame.text:GetText(), " x ")
	if profile == nil then
		return 0
	end
	local item = Mule_GetItemFromName(name)
	if item == nil then
		return 0
	end
	--("Trying to add "..item.name)
	local newCount = Mule_AddToProfile(UnitName("player"), profile, item.id, add)
	if newCount == 0 then
		frame.dec_icon:Hide()
	else
		frame.dec_icon:Show()
	end
	for _,k in pairs(MFVars.sorted) do
		local v = MFVars.tree[k]
		for l,x in pairs(v) do
			if x == frame.text:GetText() then
				MFVars.tree[k][l] = name.." x "..newCount
				return newCount
			end
		end
	end
	return 0
end

-- Reuse frames
local function GetFrame(type, name, parent, override)
	for _, child in ipairs(parent) do
		if child:GetName() == name then
			return child
		end
	end
	return CreateFrame(type, name, parent, override)
end

-- Create graphic controls for a row
local function CreateRow(hParent, id)
	local frame = GetFrame("Button", "Mulerow"..id, hParent)
	frame:SetPoint("TOPLEFT", hParent, "TOPLEFT", 0, 0)
	
	-- Row extenssion
	frame:SetWidth(200)
	frame:SetHeight(15)

	-- Handler for dropped item
	frame:SetScript("OnReceiveDrag", function()
		local owner = getOwner(id)
		if owner == nil then
			owner = frame.text:GetText()
		end
		local name = Mule_getDragged()
		if CursorHasItem() and owner and name then
			if MFVars.mode == "MULE" then
				if IsShiftKeyDown() then
					local item = Mule_GetItemFromName(name)
					if item then
						Mule_AddToMule(UnitName("player"), owner, item.type)
					end
				else
					Mule_AddToMule(UnitName("player"), owner, name)
				end
			elseif MFVars.mode == "PROFILE" then
				-- owner Strip (Active)
				local ownername = splitOnFirst(owner, " %(Active%)")
				-- name Strip " x <nn>"
				name = splitOnFirst(name, " x ")
				local item = Mule_GetItemFromName(name)
				if item then
					MFVars.keepPos = true
					Mule_AddToProfile(UnitName("player"), ownername, item.id, item.stack)
					Mule_ShowProfiles(UnitName("player"))
				end
			end
		end
		ClearCursor()
	end)

	-- handler for clicked row
	frame:SetScript("OnClick", function ()
		if MFVars.mode == "MULE" then
			if IsAltKeyDown() then
				local owner = getOwner(id)
				-- Remove mule or a filter for mule
				if owner == nil then
					owner = frame.text:GetText()
					Mule_UnRegister(UnitName("player"), owner)
					return
				end
				Mule_RemoveFromMule(UnitName("player"), owner, frame.text:GetText())
				return
			end
		elseif MFVars.mode == "PROFILE" then
			if IsAltKeyDown() then
				-- Remove profile or a item in profile
				local owner = getOwner(id)
				if owner == nil then
					owner = frame.text:GetText()
					-- owner Strip (Active)
					owner = splitOnFirst(owner, " %(Active%)")
					Mule_RemoveProfile(UnitName("player"), owner)
					MFVars.keepPos = true
					Mule_ShowProfiles(UnitName("player"))
					return
				end
				local name = frame.text:GetText()
				-- name strip " x <nn>"
				name = splitOnFirst(name, " x ")
				Mule_RemoveFromProfile(UnitName("player"), owner, name)
				for _,k in pairs(MFVars.sorted) do
					local v = MFVars.tree[k]
					if owner == k then
						for l,x in pairs(v) do
							if x == frame.text:GetText() then
								MFVars.tree[k][l] = nil
							end
						end
					end
				end
			else
				local owner = getOwner(id)
				if owner == nil then
					owner = frame.text:GetText()
					owner = splitOnFirst(owner, " %(Active%)")
					MFVars.keepPos = true
					Mule_ActivateProfile(owner)
					Mule_ShowProfiles(UnitName("player"))
				end
			end
		end
	end)

	-- expand icon
	local plus_icon = GetFrame("Button", "icon_plus"..id, frame)
	plus_icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	plus_icon:SetWidth(13)
	plus_icon:SetHeight(13)

	plus_icon:SetScript("OnClick", function()
		collapseRow(id)
	end)

	local icon = plus_icon:CreateTexture("Texture", "Background")
	icon:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
	icon:SetAllPoints(plus_icon)
	frame.plus_icon = plus_icon

	-- collapse icon
	local minus_icon = GetFrame("Button", "icon_minus"..id, frame)
	minus_icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	minus_icon:SetWidth(13)
	minus_icon:SetHeight(13)

	minus_icon:SetScript("OnClick", function()
		collapseRow(id)
	end)

	local icon_minus = minus_icon:CreateTexture("Texture", "Background")
	icon_minus:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
	icon_minus:SetAllPoints(minus_icon)
	frame.minus_icon = minus_icon

	-- The text
	local text = frame:CreateFontString("text"..id, "ARTWORK", "GameFontNormalSmall")
	text:SetPoint("TOPLEFT", frame, "TOPLEFT", 13, 0)
	text:SetJustifyH("LEFT")
	--text:SetWordWrap(false)
	text:SetTextColor(1, 1, 1, 1)
	text:SetText("Row "..id)
	text:SetWidth(200 - 13)
	frame.text = text

	-- Increase count icon
	local inc_icon = GetFrame("Button", "icon_inc"..id, frame)
	inc_icon:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -13, 0)
	inc_icon:SetWidth(13)
	inc_icon:SetHeight(13)
	inc_icon:SetScript("OnClick", function()
		addToProfile(id, frame, 1)
	end)
	inc_icon:Hide()

	local icon_inc = inc_icon:CreateTexture("Texture", "Background")
	icon_inc:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
	icon_inc:SetAllPoints(inc_icon)
	frame.inc_icon = inc_icon

	-- Decrease count icon
	local dec_icon = GetFrame("Button", "icon_dec"..id, frame)
	dec_icon:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -26, 0)
	dec_icon:SetWidth(13)
	dec_icon:SetHeight(13)
	dec_icon:SetScript("OnClick", function()
		addToProfile(id, frame, -1)
	end)
	dec_icon:Hide()

	local icon_dec = dec_icon:CreateTexture("Texture", "Background")
	icon_dec:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
	icon_dec:SetAllPoints(dec_icon)
	frame.dec_icon = dec_icon

	return frame
end

--[[
	frame.fs_title = fs_title

	frame.cb = {}

	for k,v in ipairs(tCheck) do
		local cb = CreateFrame("CheckButton", v[1], frame, "UICheckButtonTemplate")
		cb:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 8, -(4+(k-1)*14))
		cb:SetWidth(16)
		cb:SetHeight(16)
		
		if v[2] then cb.tooltipTitle = v[2] end
		if v[3] then cb.tooltipText = v[3] end

		local num = tonumber(string.sub(v[1], string.find(v[1], "%d+")))

		cb:SetScript("OnShow", function()
			LazyPig_GetOption(num)
		end)
		cb:SetScript("OnClick", function()
			LazyPig_SetOption(num);
		end)
		cb:SetScript("OnEnter", function()
			if this.tooltipTitle then
				GameTooltip:SetOwner(this, "ANCHOR_TOPRIGHT")
				--GameTooltip:SetScale(.71)
				GameTooltip:SetBackdropColor(.01, .01, .01, .91)
				GameTooltip:SetText(this.tooltipTitle)
				if this.tooltipText then
					GameTooltip:AddLine(this.tooltipText, 1, 1, 1)
				end
				GameTooltip:Show()
			end
		end)
		cb:SetScript("OnLeave", function()
			GameTooltip:Hide();
		end)

		frame.cb[k] = cb
	end

	return frame
end
]]

-- Calculate indentation to pixels
local function MuleFrame_indent(ind)
	return 10 + 10 * ind
end

-- Calculate row Y position in pixels
local function MuleFrame_row(r)
	return -36 + -15 * r
end

-- Create the MuleFrame dialog
function MuleFrame_Create()
	-- Option Frame
	local frame = CreateFrame("Frame", "MuleFrame")

	tinsert(UISpecialFrames,"MuleFrame")
	--frame:SetScale(.81)

	-- Set sizes
	MFVars.noRows = 20
	frame:SetWidth(250)
	frame:SetHeight(-MuleFrame_row(MFVars.noRows + 2))
	
	frame:SetPoint("TOPLEFT", nil, "TOPLEFT", 400, -50)
	frame:SetBackdrop( {
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", 
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", 
			tile = true, 
			tileSize = 32, 
			edgeSize = 32, 
			insets = { left = 11, right = 12, top = 12, bottom = 11 }
		} );
	frame:SetBackdropColor(.01, .01, .01, .91)

	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true) 
	frame:SetClampedToScreen(false)
	frame:RegisterForDrag("LeftButton")
	frame:Hide()
	-- Handle drag of window
	frame:SetScript("OnMouseDown", function()
		if arg1 == "LeftButton" and not this.isMoving then
			this:StartMoving();
			this.isMoving = true;
		end
	end)
	frame:SetScript("OnMouseUp", function()
		if arg1 == "LeftButton" and this.isMoving then
			this:StopMovingOrSizing();
			this.isMoving = false;
		end
	end)
	frame:SetScript("OnMouseWheel", function()
		if arg1 < 0 and MFVars.startRow < MFVars.maxRows then
			MFVars.startRow = MFVars.startRow + 1
			frame.slider:SetValue(frame.slider:GetValue() + 1)
		elseif arg1 >= 0 and MFVars.startRow > 0 then
			MFVars.startRow = MFVars.startRow - 1
			frame.slider:SetValue(frame.slider:GetValue() - 1)
		end
	end)
	frame:SetScript("OnHide", function()
		if this.isMoving then
			this:StopMovingOrSizing();
			this.isMoving = false;
		end
	end)
	-- Handler for dropped item
	frame:SetScript("OnReceiveDrag", function()
		for _,k in pairs(MFVars.sorted) do
			owner = k
		end
		local name = Mule_getDragged()
		if CursorHasItem() and owner and name then
			if MFVars.mode == "MULE" then
				Mule_AddToMule(UnitName("player"), owner, name)
			elseif MFVars.mode == "PROFILE" then
				-- owner Strip (Active)
				local ownername = splitOnFirst(owner, " %(Active%)")
				-- name Strip " x <nn>"
				name = splitOnFirst(name, " x ")
				local item = Mule_GetItemFromName(name)
				if item then
					local count = Mule_AddToProfile(UnitName("player"), ownername, item.id, item.stack)
					DEFAULT_CHAT_FRAME:AddMessage("Adding to "..owner.." "..item.name.." x "..tostring(count))
					MFVars.keepPos = true
					Mule_ShowProfiles(UnitName("player"))
				else
					DEFAULT_CHAT_FRAME:AddMessage("item failed")
				end
			end
		end
		ClearCursor()
	end)
	
	-- MenuTitle Frame
	local texture_title = frame:CreateTexture("MuleFrameTitle")
	texture_title:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header", true);
	texture_title:SetWidth(266)
	texture_title:SetHeight(58)
	texture_title:SetPoint("CENTER", frame, "TOP", 0, -20)

	frame.texture_title = texture_title

	-- MenuTitle FontString
	local fs_title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	fs_title:SetPoint("CENTER", frame.texture_title, "CENTER", 0, 12)
	fs_title:SetText("Mule")

	frame.fs_title = fs_title

	-- Close Setting Window Button
	local btn_close = CreateFrame("Button", "MuleFrameCloseButton", frame, "UIPanelCloseButton")
	btn_close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -12)
	btn_close:SetWidth(24)
	btn_close:SetHeight(24)

	-- Create Mule icon
	local icon = CreateFrame("Frame", nil, frame)
	icon:SetFrameStrata("BACKGROUND")
	icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -18)
	icon:SetWidth(32)
	icon:SetHeight(32)
	
	local icon_tex = icon:CreateTexture(nil, "BACKGROUND")
	icon_tex:SetTexture("Interface\\Addons\\Mule\\icons\\donkey-icon-32x32.tga")
	icon_tex:SetAllPoints(icon)
	icon.texture = icon_tex

	frame.btn_close = btn_close

	frame.btn_close:SetScript("OnClick", function()
		this:GetParent():Hide()
	end)
	
	frame.row = {}
	for i=1,MFVars.noRows do
		frame.row[i] = CreateRow(frame, i)
		frame.row[i]:Hide()
	end

	-- Redraw of tree
	frame:SetScript("OnUpdate", function()
		local dst_r = 0
		local src_r = 0
		local i = 0
		if not MFVars.tree then
			return
		end
		for _,k in pairs(MFVars.sorted) do
			local v = MFVars.tree[k]
			src_r = src_r + 1
			i = 1
			-- Draw Parents
			if src_r >= MFVars.startRow then
				dst_r = dst_r + 1
				if  dst_r <= MFVars.noRows then
					frame.row[dst_r]:Show()
					frame.row[dst_r].text:SetText(k)
					frame.row[dst_r].text:SetTextColor(1,0.98431372549,0,1);
					frame.row[dst_r]:SetPoint("TOPLEFT", frame, "TOPLEFT", MuleFrame_indent(i), MuleFrame_row(dst_r))
					frame.row[dst_r].dec_icon:Hide()
					frame.row[dst_r].inc_icon:Hide()
				end
			end
			if v and v.collapsed == false then
				if src_r >= MFVars.startRow and dst_r <= MFVars.noRows then
					frame.row[dst_r].minus_icon:Show()
					frame.row[dst_r].plus_icon:Hide()
				end
				-- Draw childs
				i = i + 1
				for l,m in pairs(v) do
					if l ~= "collapsed" then
						src_r = src_r + 1
						if src_r >= MFVars.startRow and dst_r < MFVars.noRows then
							dst_r = dst_r + 1
							frame.row[dst_r]:Show()
							frame.row[dst_r].text:SetText(m)
							frame.row[dst_r].text:SetTextColor(1,1,1,1);
							frame.row[dst_r].minus_icon:Hide()
							frame.row[dst_r].plus_icon:Hide()
							frame.row[dst_r]:SetPoint("TOPLEFT", frame, "TOPLEFT", MuleFrame_indent(i), MuleFrame_row(dst_r))
							if MFVars.mode == "PROFILE" then
								frame.row[dst_r].dec_icon:Show()
								frame.row[dst_r].inc_icon:Show()
							else
								frame.row[dst_r].dec_icon:Hide()
								frame.row[dst_r].inc_icon:Hide()
							end
						end
					end
				end
			elseif src_r >= MFVars.startRow and dst_r <= MFVars.noRows then
				frame.row[dst_r].minus_icon:Hide()
				frame.row[dst_r].plus_icon:Show()
			end
		end
		MFVars.maxRows = src_r
		if src_r >= MFVars.noRows then
			frame.slider:Show()
			frame.slider:SetMinMaxValues(1, src_r)
		else
			frame.slider:Hide()
		end
		MFVars.emptyRows = false
		for i = dst_r + 1, MFVars.noRows do
			MFVars.emptyRows = true
			frame.row[i]:Hide()
		end
	end)

	-- Slider
	local slider = CreateFrame("Slider", "MuleFrameSlider", frame, "OptionsSliderTemplate")
	slider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, MuleFrame_row(1))
	slider:SetWidth(12)
	slider:SetHeight(-MuleFrame_row(MFVars.noRows) + MuleFrame_row(0))
	slider:SetMinMaxValues(1, MFVars.maxRows)
	slider:SetOrientation('VERTICAL')
	slider:SetValueStep(1)
	slider.scrollStep = 1
	getglobal(slider:GetName()..'Low'):SetText("")
	getglobal(slider:GetName()..'High'):SetText("")
	getglobal(slider:GetName()..'Text'):SetText("")
	slider:SetValue(0)
	frame.slider = slider
	slider:SetScript("OnValueChanged", function()
		local value = slider:GetValue()
		if value and value > 0 and value < MFVars.maxRows then
			MFVars.startRow = value
		end
	end)
	return frame
end
