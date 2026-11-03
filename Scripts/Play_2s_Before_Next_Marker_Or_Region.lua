-- @description Play 2s Before Next Marker or Region
-- @version 1.0.0
-- @author Aleksei Vorobev / Patch34
-- @link
--   GitHub repository https://github.com/patch-34/edit-play-2s-before-next-marker-or-region
-- @about
--   Seeks to two seconds before the next marker or region start, starting playback if stopped.

local PRE_ROLL_SEC = 2.0
local EPS = 1e-9

local function msg(s)
  reaper.ShowMessageBox(tostring(s), "Play 2s before next marker/region", 0)
end

local function is_transport_active(play_state)
  return (play_state == 1) or (play_state == 2) or (play_state == 5)
end

local function find_next_marker_or_region_start(cur_pos)
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local total = (num_markers or 0) + (num_regions or 0)

  local best_pos = nil
  local best_kind = nil
  local best_name = ""

  for i = 0, total - 1 do
    local retval, isrgn, pos, rgnend, name = reaper.EnumProjectMarkers(i)
    if retval then
      local candidate_pos = pos
      if candidate_pos > (cur_pos + EPS) then
        if (best_pos == nil) or (candidate_pos < best_pos) then
          best_pos = candidate_pos
          best_kind = (isrgn and "region") or "marker"
          best_name = name or ""
        end
      end
    end
  end

  return best_pos, best_kind, best_name
end

reaper.Undo_BeginBlock()

local play_state = reaper.GetPlayState()
local transport_active = is_transport_active(play_state)

local cur_pos
if transport_active then
  cur_pos = reaper.GetPlayPosition()
else
  cur_pos = reaper.GetCursorPosition()
end

local next_pos, kind, name = find_next_marker_or_region_start(cur_pos)

if not next_pos then
  reaper.Undo_EndBlock("Play 2s before next marker/region (no next found)", -1)
  msg("No next marker or region start found to the right of the current position.")
  return
end

local start_pos = next_pos - PRE_ROLL_SEC
if start_pos < 0 then start_pos = 0 end

if transport_active then
  reaper.SetEditCurPos(start_pos, true, true)
else
  reaper.SetEditCurPos(start_pos, true, false)
  reaper.Main_OnCommand(1007, 0)
end

reaper.Undo_EndBlock("Play 2s before next marker/region", -1)
