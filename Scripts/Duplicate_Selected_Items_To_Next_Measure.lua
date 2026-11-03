-- @description Duplicate Selected Items to Next Measure
-- @version 1.0.0
-- @author Aleksei Vorobev / Patch34
-- @license MIT
-- @link
--   GitHub repository https://github.com/patch-34/duplicate-items-to-next-measure
-- @about
--   Duplicates selected items one measure forward while preserving their beat offset and item properties.

local SCRIPT_NAME = "Duplicate selected items to next measure"
local PROJECT = 0

local function replace_guid_lines(chunk)
  return chunk:gsub("(\n%s*I?GUID%s+)%{[^}]+%}", function(prefix)
    return prefix .. reaper.genGuid("")
  end)
end

local function get_next_measure_position(position)
  local qn = reaper.TimeMap2_timeToQN(PROJECT, position)
  local _, measure_start_qn, measure_end_qn = reaper.TimeMap_QNToMeasures(PROJECT, qn)

  local measure_length_qn = measure_end_qn - measure_start_qn
  if measure_length_qn <= 0 then
    measure_length_qn = 4
  end

  return reaper.TimeMap2_QNToTime(PROJECT, qn + measure_length_qn)
end

local function collect_selected_items()
  local selected_count = reaper.CountSelectedMediaItems(PROJECT)
  local items = {}

  for index = 0, selected_count - 1 do
    local item = reaper.GetSelectedMediaItem(PROJECT, index)
    if item then
      local track = reaper.GetMediaItem_Track(item)
      local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local ok, chunk = reaper.GetItemStateChunk(item, "", false)

      if ok and track and chunk and chunk ~= "" then
        items[#items + 1] = {
          track = track,
          position = position,
          chunk = chunk,
        }
      end
    end
  end

  return items
end

local function clear_item_selection()
  local item_count = reaper.CountMediaItems(PROJECT)

  for index = 0, item_count - 1 do
    local item = reaper.GetMediaItem(PROJECT, index)
    reaper.SetMediaItemSelected(item, false)
  end
end

local function main()
  local items = collect_selected_items()
  if #items == 0 then
    return
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local duplicated_items = {}

  for _, data in ipairs(items) do
    local new_item = reaper.AddMediaItemToTrack(data.track)

    if new_item then
      local new_chunk = replace_guid_lines(data.chunk)
      local new_position = get_next_measure_position(data.position)

      reaper.SetItemStateChunk(new_item, new_chunk, false)
      reaper.SetMediaItemInfo_Value(new_item, "D_POSITION", new_position)

      duplicated_items[#duplicated_items + 1] = new_item
    end
  end

  clear_item_selection()

  for _, item in ipairs(duplicated_items) do
    reaper.SetMediaItemSelected(item, true)
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock(SCRIPT_NAME, -1)
end

main()
