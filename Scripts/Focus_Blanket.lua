-- @description Focus Blanket
-- @version 1.0.0
-- @author Aleksei Vorobev / Patch34
-- @link
--   GitHub repository https://github.com/patch-34/focus-blanket
-- @about
--   Toggles a tall neutral-colored track and item to cover the arrange view during listening.

local r = reaper
local proj = 0

-- ===== Config =====
local EXT_KEY = "P_EXT:patch34_focusblanket"
local EXT_VAL = "1"

local TRACK_NAME = "∪＾ェ＾∪"

-- Calm solid color (RGB 0..255)
local SOLID_R, SOLID_G, SOLID_B = 60, 60, 60

-- If project is empty/short, still create a visible item
local MIN_LEN = 30.0

-- Make it VERY tall to "fill the screen"
-- (REAPER clamps internally to what fits, so "very large" is enough)
local TRACK_HEIGHT = 2000

-- On enable: arrange view span around edit cursor (seconds)
local VIEW_SPAN_ON_ENABLE = 180.0

-- On disable: keep ORIGINAL zoom (span) from before enabling,
-- but re-center the view around the play cursor (or edit cursor if stopped).
local CENTER_ON_CURSOR_ON_DISABLE = true

-- ===== Helpers =====
local function set_track_color(track, rr, gg, bb)
  local native = r.ColorToNative(rr, gg, bb)
  r.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", native | 0x1000000)
end

local function set_item_color(item, rr, gg, bb)
  local native = r.ColorToNative(rr, gg, bb)
  r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", native | 0x1000000)
end

local function set_track_ext(track, key, val)
  r.GetSetMediaTrackInfo_String(track, key, val, true)
end

local function get_track_ext(track, key)
  local ok, val = r.GetSetMediaTrackInfo_String(track, key, "", false)
  if ok then return val end
  return ""
end

local function select_only_track(tr)
  r.Main_OnCommand(40297, 0) -- unselect all tracks
  if tr then r.SetOnlyTrackSelected(tr) end
end

-- Save/restore selection + arrange view range (used to preserve zoom/span)
local function save_context()
  local sel = r.GetSelectedTrack(proj, 0)
  local prev_guid = sel and r.GetTrackGUID(sel) or ""
  r.SetProjExtState(proj, "patch34_focusblanket", "prev_guid", prev_guid)

  local start_t, end_t = r.GetSet_ArrangeView2(proj, false, 0, 0, 0, 0)
  r.SetProjExtState(proj, "patch34_focusblanket", "view_start", tostring(start_t))
  r.SetProjExtState(proj, "patch34_focusblanket", "view_end", tostring(end_t))
end

local function restore_selection_only()
  local _, prev_guid = r.GetProjExtState(proj, "patch34_focusblanket", "prev_guid")
  if prev_guid and prev_guid ~= "" then
    local n = r.CountTracks(proj)
    for i = 0, n - 1 do
      local tr = r.GetTrack(proj, i)
      if tr and r.GetTrackGUID(tr) == prev_guid then
        select_only_track(tr)
        break
      end
    end
  end
end

local function get_saved_view_span()
  local _, s = r.GetProjExtState(proj, "patch34_focusblanket", "view_start")
  local _, e = r.GetProjExtState(proj, "patch34_focusblanket", "view_end")
  local a = tonumber(s or "")
  local b = tonumber(e or "")
  if a and b and b > a then
    return (b - a), a, b
  end
  return nil, nil, nil
end

local function set_arrange_view_centered(pos, span)
  if not span or span <= 0 then return end
  local half = span * 0.5
  local a = pos - half
  if a < 0 then a = 0 end
  local b = a + span
  r.GetSet_ArrangeView2(proj, true, 0, 0, a, b)
end

local function get_follow_pos()
  local st = r.GetPlayState() -- bitmask: 0 stop, 1 play, 2 pause, 5 rec
  if st ~= 0 then
    return r.GetPlayPosition()
  end
  return r.GetCursorPosition()
end

local function find_focus_track()
  local n = r.CountTracks(proj)
  for i = 0, n - 1 do
    local tr = r.GetTrack(proj, i)
    if tr and get_track_ext(tr, EXT_KEY) == EXT_VAL then
      return tr, i
    end
  end
  return nil, -1
end

local function delete_focus_track(idx)
  local tr = r.GetTrack(proj, idx)
  if tr then r.DeleteTrack(tr) end
end

local function set_arrange_view_span_on_enable()
  local t = r.GetCursorPosition()
  local half = VIEW_SPAN_ON_ENABLE * 0.5
  local a = math.max(0, t - half)
  local b = a + VIEW_SPAN_ON_ENABLE
  r.GetSet_ArrangeView2(proj, true, 0, 0, a, b)
end

-- ===== Create =====
local function create_single_focus()
  save_context()

  local proj_len = r.GetProjectLength(proj)
  local item_len = math.max(MIN_LEN, proj_len)

  -- Insert at TOP
  r.InsertTrackAtIndex(0, true)
  local tr = r.GetTrack(proj, 0)

  set_track_ext(tr, EXT_KEY, EXT_VAL)
  r.GetSetMediaTrackInfo_String(tr, "P_NAME", TRACK_NAME, true)

  r.SetMediaTrackInfo_Value(tr, "I_HEIGHTOVERRIDE", TRACK_HEIGHT)
  set_track_color(tr, SOLID_R, SOLID_G, SOLID_B)

  local item = r.AddMediaItemToTrack(tr)
  r.SetMediaItemInfo_Value(item, "D_POSITION", 0.0)
  r.SetMediaItemInfo_Value(item, "D_LENGTH", item_len)
  set_item_color(item, SOLID_R, SOLID_G, SOLID_B)

  -- Blank take name to avoid "empty track" label
  local take = r.AddTakeToMediaItem(item)
  if take then
    r.GetSetMediaItemTakeInfo_String(take, "P_NAME", " ", true)
  end

  set_arrange_view_span_on_enable()
  select_only_track(tr)
end

-- ===== Toggle =====
local function main()
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  local tr, idx = find_focus_track()
  if tr and idx >= 0 then
    -- Disable: remove focus track
    delete_focus_track(idx)

    -- Restore selection (but not the old view position)
    restore_selection_only()

    if CENTER_ON_CURSOR_ON_DISABLE then
      -- Keep original zoom/span, but center on play/edit cursor
      local span = get_saved_view_span()
      local pos = get_follow_pos()
      if span then
        set_arrange_view_centered(pos, span)
      end
    end
  else
    -- Enable
    create_single_focus()
  end

  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock("Focus Blanket — Toggle", -1)
end

main()
