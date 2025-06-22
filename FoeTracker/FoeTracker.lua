--[[

Copyright © 2025, Quenala of Asura
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of FoeTracker nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL QUENALA BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

]]

_addon.name = 'FoeTracker'
_addon.author = 'Quenala'
_addon.version = '1.2.2.0'
_addon.commands = {'FoeT','FoeTracker'}
-- Special thanks to Rubenator for guidance and help with code-structure.

require('luau')
texts = require('texts')
images = require('images')
packets = require('packets')

--static images location
images.image_path = function(image, path)
	images.path(image, windower.addon_path..'images/'..path)
end

mapstatus = false

local windower_settings = windower.get_windower_settings()

-- Change max_division to change the size scale of the addon. Lower value = bigger size
local max_division = 5
local calc_width = math.min(500, windower_settings.ui_x_res / max_division)
local image_scale = calc_width / 500
local text_scale = math.sqrt(image_scale)

local quest_position = 0

-- Dont change these values. You can change position and quest order in \FoeTracker\data\settings.xml
default = {
    quest_order = L{1,2,3,4,5,6,7,8,9,10,11,12,13,14,15},
    pos = {
        x = 300,
        y = 120,
    },
    draggable = true,
    text = {
        font = 'MV Boli',
        red = 0,
        green = 0,
        blue = 0,
        stroke = {
            width = 1,
            alpha = 50,
            red = 255,
            green = 255,
            blue = 255,
        }
    }
}

settings = config.load(default)

text_settings_override = {
    bg = {
        visible = false,
    },
    text = {
        size = math.floor(text_scale*10)
    },
    flags = {
        draggable = false,
    },
    visible = false,
}
text_settings = T(settings):copy(true --[[deep copy]]):update(text_settings_override, true)

image_settings_override = {
    draggable = false,
    texture = {
        fit = false,
    },
    size = {
        width = calc_width,
        height = calc_width,
    },
    visible = false,
}
image_settings = T(settings):copy(true --[[deep copy]]):update(image_settings_override, true)

scroll_image = images.new('scroll', image_settings)
scroll_image:image_path('scroll.png')
scroll_image:pos(settings.pos.x, settings.pos.y)
scroll_image:draggable(settings.draggable)

map_image = images.new('map', image_settings)
map_image:pos(settings.pos.x + 500*image_scale, settings.pos.y)
map_image:draggable(false)

textbox = texts.new("textbox", text_settings)

textbox:pos(settings.pos.x + math.floor(140*image_scale), settings.pos.y + math.floor(185*image_scale))

local _roman = {[10]="X",[9]="IX",[5]="V",[4]="IV",[1]="I"}
local _roman_keys = L{10,9,5,4,1}

function to_roman(num)
    local result = ''
    for k in _roman_keys:it() do
        local v = _roman[k]
        while num >= k do
            num = num - k
            result = result .. _roman[k]
        end
    end
    return result
end

function get_roman(num)
    return num == 1 and "" or " " .. to_roman(num)
end

zone_map = T{
    [51] = {map_num=0, quest_num=1, footprint="(H-13)"},
    [61] = {map_num=0, quest_num=2, footprint="(I-10)"},
	[79] = {maps={
        [2] = {quest_num=7,message="Enter Arrapago Reef (G-6)\n(next to Survival Guide)"},
        [4] = {quest_num=3,map_num=3, footprint="(I-6)"},
    }},
    [204] = {map_num=0, quest_num=4, message="Exit to Beaucedine Glacier"},
    [111] = {map_num=0, quest_num=4, footprint="(K-6)"},
    [143] = {map_num=2, quest_num=5, footprint="(G-10)"},
    [68] = {map_num=1, quest_num=6, footprint="(E-7)"},
    [54] = {map_num=2, quest_num=7, footprint="Map 3 (H-6)"},
    [291] = {map_num=0, quest_num=8, footprint="Etheral Ingress #9"},
    [125] = {map_num=0, quest_num=9, footprint="(I-6)"},
    [244] = {map_num=0, quest_num=10, message="Zone into Batallia Downs"},
    [105] = {map_num=0, quest_num=10, footprint="(J-7)"},
    [126] = {map_num=0, quest_num=11, footprint="(G-8)"},
	[276] = {map_num=0, quest_num=12, message="Cast escape \nto enter Kamihr Drifts."},
    [274] = {map_num=0, quest_num=12, message="Exit to Kamihr Drifts. \nDoor is east up the stairs"},
    [267] = {quest_num=12, footprint="(F-8)"},
    [258] = {map_num=0, quest_num=13, footprint="(N-5)"},
    [12] = {quest_num=14, footprint="(L-9)"},
    [161] = {map_num=0, quest_num=15, message="Exit to Xarcabard"},
    [112] = {quest_num=15, footprint="Just south of\ncastle entrance (D-8)"},
}

function init()
    local info = windower.ffxi.get_info()
    if not info.logged_in then return end
    set_quest_position(1)
end

function update_zone_message(zone)
    local data = zone_map[zone]
    if not data then
        map_image:hide()
		mapstatus = false
        return
    end
    if data.maps then
        coroutine.sleep(2)
        local current_map_num = windower.ffxi.get_map_data()
        map_info = data.maps[current_map_num]
        if not map_info then return end
        data = T(table.copy(data, true)):update(map_info)
    end
    local roman = get_roman(data.quest_num)
    local footprint = data.message and "" or ("Peculiar Footprints location:\n")
    local zone_name = data.footprint and res.zones[zone].name .. " " or ""
    local position = data.message or data.footprint or ""
    local spacing = position:count('\n') > 0 and "\n" or "\n\n"
	local text = "Peculiar Foes%s\n\n%s%s%s.%s":format(roman, footprint, zone_name, position, spacing)
    textbox:text(text)
    textbox:show()
    scroll_image:show()
end

function next_quest(quest_num_completed)
    if quest_num_completed then
        quest_position = quest_num_completed and settings.quest_order:find(quest_num_completed)
    end
    quest_position = quest_position and quest_position + 1
    local quest_num = quest_position and settings.quest_order[quest_poisition]
    update_completion_message(quest_num)
end

function set_quest(quest_num)
    quest_position = settings.quest_order:find(quest_num)
    update_completion_message(quest_num)
end

function set_quest_position(position)
    local quest_num = settings.quest_order[position]
    quest_position = quest_num and position
    update_completion_message(quest_num)
end

objective_map = T{
    {quest_num=1, message="Unity (135) Teleport to \nWajaom Woodlands"},
    {quest_num=2, message="Voidwatch Teleport to \nMount Zhayolm. or use \nHalvung Staging point"},
    {quest_num=3, message="Unity (135) Teleport to \nCaedarva Mire"},
    {quest_num=4, message="Unity (128) Teleport to \nFei'Yin"},
    {quest_num=5, message="Home Point to \nPalborough Mines #1"},
    {quest_num=6, message="Survival Guide or \nUnity (145) to \nAydeewa Subterrane"},
    {quest_num=7, message="Survival Guide to \nCaedarva Mire"},
    {quest_num=8, message="Dimensional Ring to \nReisenjima"},
    {quest_num=9, message="Unity (125) Teleport to \nWestern Altepa Desert"},
    {quest_num=10, message="Home Point to \nUpper Jeuno #1."},
    {quest_num=11, message="Home Point to \nQufim Island"},
    {quest_num=12, message="HP/Waypoint warp to \nInner/Outer Ra'Kaznar\n(Inner requires Escape)"},
    {quest_num=13, message="Home Point to \nEastern Adoulin #1 and \nenter Rala waterways (E-7)"},
    {quest_num=14, message="Home Point to \nNewton Movalpolos #1"},
    {quest_num=15, message="Survival Guide to \nCastle Zvahl Baileys"},
    [-1]={message="Peculiar Foes Completed\n\nUnload addon with \n//lua unload FoeTracker"},
}

function update_completion_message(quest_num)
    quest_num = quest_num or quest_position and settings.quest_order[quest_position]
    local data = quest_num and objective_map[quest_num]
    if not data then
        data = objective_map[-1]
        textbox:text(data.message)
        windower.add_to_chat(8, "Peculiar Foes Completed!")
        textbox:hide()
		scroll_image:hide()
		map_image:hide()
        mapstatus = false
		tracking = false
        return
    end
    local roman = get_roman(data.quest_num)
    local text = "Peculiar Foes%s\n\n%s":format(roman, data.message)
    textbox:text(text)
    textbox:show()
    scroll_image:show()
    map_image:hide()
    mapstatus = false
end

windower.register_event('incoming chunk', function(id, original)
	if not tracking then return end
    if id ~= 0x02D then return end
    local packet = packets.parse('incoming', original)
    if packet.Message == 690 and packet['Param 1'] >= 3789 and packet['Param 1'] <= 3803 then
        local vanquished_peculiar_foe = packet['Param 1'] - 3788
		next_quest(vanquished_peculiar_foe)
    end
end)

function update_map(zone)
    local zone_data = zone_map[zone]
    if not zone_data or not zone_data.footprint then 
        mapstatus = false
		map_image:image_path('mog.png')
        map_image:hide()
        return
    end
    if zone_data.maps then
        local current_map_num = windower.ffxi.get_map_data()
        map_info = zone_data.maps[current_map_num]
        if not map_info or not map_info.footprint then
			map_image:image_path('mog.png')
            map_image:hide()
            return
        end
        zone_data = T(table.copy(zone_data, true)):update(map_info)
    end
    local map_num = zone_data.map_num
    local map_string = map_num and "_%d":format(map_num) or ""
	local zone_id_hex = "%02x":format(zone)
    local path = zone_id_hex .. map_string .. ".png"
    map_image:image_path(path)
end

windower.register_event('zone change', function(zone)
    if not tracking then return end
	update_zone_message(zone)
	update_map(zone)
end)

windower.register_event('addon command', function(command, ...)
    command = command and command:lower()
    if not command or command == '' or command == 'map' then
		if not tracking then return end
		mapstatus = not mapstatus
		map_image:visible(mapstatus)
    elseif command == 'help' then
        windower.add_to_chat(8, 'FoeTracker Commands:')
        windower.add_to_chat(8, '//foet [map] - Toggle map display.')
		windower.add_to_chat(8, '//foet skip - Skip current quest.')
		windower.add_to_chat(8, '//foet start - Starts tracking the first quest.')
		windower.add_to_chat(8, '//foet stop - Stops tracking quests.')
		windower.add_to_chat(8, '//foet help - Display this help message.')
	elseif command == 'start' then
		tracking = true
		init()
	elseif command == 'stop' then	
		tracking = false
		textbox:hide()
		scroll_image:hide()
		map_image:hide()
	elseif command == 'skip' or command == 'next' then
		if not tracking then return end
		next_quest()
    end
end)

windower.register_event('load', 'login', function()
    settings.quest_order = settings.quest_order:map(tonumber)
end)