-- @description REAPER Timeline Screensaver
-- @version 1.0.0
-- @author Aleksei Vorobev / Patch34
-- @link
--   GitHub repository https://github.com/patch-34/reaper-timeline-screensaver
-- @about
--   Animates media items in a separate REAPER project tab as traveling waves.

local GRID_W        = 120
local GRID_H        = 30
local CELL_WIDTH    = 0.15
local BASE_LENGTH   = 0.12
local VISIBLE_W     = 80
local VISIBLE_H     = 24
local FPS_TARGET    = 20
local SPEED         = 1.5
local TRACK_HEIGHT  = 16

local items = {}
local tracks = {}
local base_pos = {}
local running = true
local t = 0
local frame_interval = 1.0 / FPS_TARGET
local last_frame_time = 0
local prev_length = {}
local prev_pos = {}
local prev_colors = {}

---------------------------------------------------------------------
local function hsv_to_native(h, s, v)
  h = h % 1.0
  local i = math.floor(h * 6)
  local f = h * 6 - i
  local p = v * (1 - s)
  local q = v * (1 - f * s)
  local tt = v * (1 - (1 - f) * s)
  local r, g, b
  local m = i % 6
  if     m == 0 then r, g, b = v, tt, p
  elseif m == 1 then r, g, b = q, v, p
  elseif m == 2 then r, g, b = p, v, tt
  elseif m == 3 then r, g, b = p, q, v
  elseif m == 4 then r, g, b = tt, p, v
  else               r, g, b = v, p, q
  end
  r = math.floor(r * 255 + 0.5)
  g = math.floor(g * 255 + 0.5)
  b = math.floor(b * 255 + 0.5)
  return reaper.ColorToNative(r, g, b) + 0x1000000
end

---------------------------------------------------------------------
local function compute_wave(col, row, time)
  local nx = col / GRID_W
  local ny = row / GRID_H

  local phase = (nx + ny) * 6.0 - time * 3.5
  local wave = math.sin(phase)
  local wave2 = math.sin(phase * 2.3 + 1.5) * 0.4
  local combined = wave + wave2
  local len_mult = 0.1 + 0.9 * math.max(0, combined / 1.4)
  local pos_off = combined * CELL_WIDTH * 0.4
  local hue = (nx + ny) * 0.3 + time * 0.25
  return len_mult, pos_off, hue
end

---------------------------------------------------------------------
local function is_project_alive()
  return tracks[1] and reaper.ValidatePtr2(0, tracks[1], "MediaTrack*")
end

---------------------------------------------------------------------
local function setup()
  reaper.Main_OnCommand(41929, 0)

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  for row = 1, GRID_H do
    reaper.InsertTrackAtIndex(row - 1, false)
    local track = reaper.GetTrack(0, row - 1)
    if not track then
      reaper.PreventUIRefresh(-1)
      reaper.Undo_EndBlock("Wave Motion - Setup (failed)", -1)
      return false
    end
    tracks[row] = track
    reaper.SetMediaTrackInfo_Value(track, "I_HEIGHTOVERRIDE", TRACK_HEIGHT)
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "~wm" .. row, true)

    items[row] = {}
    base_pos[row] = {}
    prev_length[row] = {}
    prev_pos[row] = {}
    prev_colors[row] = {}

    for col = 1, GRID_W do
      local pos = (col - 1) * CELL_WIDTH
      local item = reaper.AddMediaItemToTrack(track)
      if item then
        reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", BASE_LENGTH)
        reaper.SetMediaItemInfo_Value(item, "B_UISEL", 0)
        local color = hsv_to_native(col / GRID_W, 0.9, 0.85)
        reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", color)
        items[row][col] = item
        base_pos[row][col] = pos
        prev_length[row][col] = BASE_LENGTH
        prev_pos[row][col] = pos
        prev_colors[row][col] = color
      end
    end
  end

  reaper.PreventUIRefresh(-1)

  -- Zoom to VISIBLE area only
  local visible_length = VISIBLE_W * CELL_WIDTH
  reaper.GetSet_LoopTimeRange2(0, true, false, 0, visible_length, false)
  reaper.Main_OnCommand(40031, 0)
  reaper.GetSet_LoopTimeRange2(0, true, false, 0, 0, false)

  if tracks[1] then
    reaper.SetOnlyTrackSelected(tracks[1])
    reaper.Main_OnCommand(40913, 0)
  end

  reaper.TrackList_AdjustWindows(true)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Wave Motion - Setup", -1)
  return true
end

---------------------------------------------------------------------
local function update_frame()
  reaper.PreventUIRefresh(1)

  for row = 1, GRID_H do
    for col = 1, GRID_W do
      local item = items[row][col]
      if item then
        local len_mult, pos_off, hue = compute_wave(col, row, t)

        local new_len = math.max(0.002, BASE_LENGTH * len_mult)
        if math.abs(new_len - prev_length[row][col]) > 0.001 then
          reaper.SetMediaItemInfo_Value(item, "D_LENGTH", new_len)
          prev_length[row][col] = new_len
        end

        local new_pos = base_pos[row][col] + pos_off
        if math.abs(new_pos - prev_pos[row][col]) > 0.001 then
          reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
          prev_pos[row][col] = new_pos
        end

        local brightness = 0.4 + 0.6 * len_mult
        local color = hsv_to_native(hue, 0.85, brightness)
        if color ~= prev_colors[row][col] then
          reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", color)
          prev_colors[row][col] = color
        end
      end
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
end

---------------------------------------------------------------------
local function init_gui()
  gfx.init("Timeline Screensaver | [Esc] quit", 450, 36, 0, 550, 1000)
  gfx.setfont(1, "Roboto", 18)
end

local function check_input()
  local char = gfx.getchar()
  if char == -1 or char == 27 then running = false end
end

local function draw_gui()
  gfx.set(0.10, 0.10, 0.14, 1)
  gfx.rect(0, 0, gfx.w, gfx.h, 1)
  local label = "||||||||||||||||||||||||||||||||||"
  for i = 1, #label do
    local hue = (i / #label + t * 0.4) % 1.0
    local h6 = hue * 6
    local s = math.floor(h6) % 6
    local f = h6 - math.floor(h6)
    local r, g, b
    if     s == 0 then r, g, b = 1, f, 0
    elseif s == 1 then r, g, b = 1-f, 1, 0
    elseif s == 2 then r, g, b = 0, 1, f
    elseif s == 3 then r, g, b = 0, 1-f, 1
    elseif s == 4 then r, g, b = f, 0, 1
    else               r, g, b = 1, 0, 1-f
    end
    gfx.set(r, g, b, 1)
    gfx.x = 10 + (i - 1) * 13; gfx.y = 8
    gfx.drawchar(string.byte(label, i))
  end
  gfx.update()
end

---------------------------------------------------------------------
local function main_loop()
  if not running or not is_project_alive() then
    gfx.quit()
    if is_project_alive() then
      reaper.Main_OnCommand(40860, 0)
    end
    return
  end
  check_input()
  local now = reaper.time_precise()
  local dt = now - last_frame_time
  if dt >= frame_interval then
    t = t + dt * SPEED
    local ok, err = pcall(update_frame)
    if not ok then running = false; return end
    draw_gui()
    last_frame_time = now
  end
  reaper.defer(main_loop)
end

---------------------------------------------------------------------
math.randomseed(os.time())
if setup() then
  init_gui()
  last_frame_time = reaper.time_precise()
  main_loop()
end
