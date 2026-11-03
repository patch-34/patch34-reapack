-- @description Delete Nearest Marker to Cursor
-- @version 1.0.0
-- @author Aleksei Vorobev / Patch34
-- @link
--   GitHub repository https://github.com/patch-34/delete-nearest-marker-to-cursor
-- @about
--   Deletes the marker closest to the edit cursor by absolute timeline distance. Regions are ignored.

local function main()
  local cursor_pos = reaper.GetCursorPosition()

  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local total = num_markers + num_regions
  if total == 0 then return end

  local nearest_enum_idx = nil
  local nearest_dist = math.huge

  for i = 0, total - 1 do
    local retval, isrgn, pos = reaper.EnumProjectMarkers3(0, i)
    if retval and not isrgn then
      local d = math.abs(pos - cursor_pos)
      if d < nearest_dist then
        nearest_dist = d
        nearest_enum_idx = i
      end
    end
  end

  if not nearest_enum_idx then return end

  reaper.Undo_BeginBlock()
  reaper.DeleteProjectMarkerByIndex(0, nearest_enum_idx)
  reaper.Undo_EndBlock("Delete nearest marker to edit cursor", -1)
  reaper.UpdateArrange()
end

main()
