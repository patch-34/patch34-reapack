-- @description Region Time Counter Mini
-- @version 1.0.0
-- @author Aleksei Vorobev / Patch34
-- @link
--   GitHub repository https://github.com/patch-34/region-time-counter-mini
-- @about
--   Shows the combined duration of all regions without double-counting overlaps.

local proj = 0

-- ===== Layout / Typography =====
local WINDOW_TITLE = ""   -- empty titlebar to avoid macOS minimum width constraints

local PAD_L = 15
local PAD_R = 40
local GAP   = 8

local FONT_MAIN  = "Helvetica"
local TITLE_SIZE = 16
local TIME_SIZE  = 38

local AUTO_REFRESH = true
local REFRESH_INTERVAL_SEC = 1.0

-- ===== Helpers =====
local function format_hhmmss(sec)
  sec = math.max(0, math.floor(sec + 0.5))
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = sec % 60
  return string.format("%02d:%02d:%02d", h, m, s)
end

-- ===== Core: union of region intervals (no overlap double-count) =====
local function measure_regions_union(proj)
  local _, numMarkers, numRegions = reaper.CountProjectMarkers(proj)

  local intervals = {}
  for idx = 0, (numMarkers + numRegions - 1) do
    local retval, isRegion, startPos, endPos = reaper.EnumProjectMarkers3(proj, idx)
    if retval and isRegion and endPos > startPos then
      intervals[#intervals + 1] = { startPos, endPos }
    end
  end

  if #intervals == 0 then return 0.0 end

  table.sort(intervals, function(a, b)
    if a[1] == b[1] then return a[2] < b[2] end
    return a[1] < b[1]
  end)

  local total = 0.0
  local cur_s, cur_e = intervals[1][1], intervals[1][2]

  for k = 2, #intervals do
    local s, e = intervals[k][1], intervals[k][2]
    if s <= cur_e then
      if e > cur_e then cur_e = e end
    else
      total = total + (cur_e - cur_s)
      cur_s, cur_e = s, e
    end
  end

  total = total + (cur_e - cur_s)
  return total
end

-- ===== State =====
local total_sec = 0.0
local last_refresh = 0
local win_w, win_h = 0, 0

local function refresh()
  total_sec = measure_regions_union(proj)
  last_refresh = reaper.time_precise()
end

-- Fixed width so the window never jumps (99:59:59)
local FIXED_TIME_SAMPLE = "99:59:59"

local function ensure_window_size_fixed_width()
  gfx.setfont(1, FONT_MAIN, TITLE_SIZE)
  local title_w, title_h = gfx.measurestr("Region Time Counter Mini")

  gfx.setfont(1, FONT_MAIN, TIME_SIZE)
  local time_w, time_h = gfx.measurestr(FIXED_TIME_SAMPLE)

  local content_w = math.max(title_w, time_w)
  local need_w = math.ceil(content_w + PAD_L + PAD_R)
  local need_h = math.ceil(PAD_L + title_h + GAP + time_h + PAD_L)

  if need_w ~= win_w or need_h ~= win_h then
    win_w, win_h = need_w, need_h
    gfx.init(WINDOW_TITLE, win_w, win_h, 0)
  end
end

-- ===== UI loop =====
local function loop()
  local ch = gfx.getchar()
  if ch < 0 or ch == 27 then return end

  if AUTO_REFRESH then
    local now = reaper.time_precise()
    if (now - last_refresh) >= REFRESH_INTERVAL_SEC then
      refresh()
      last_refresh = now
    end
  end

  -- background
  gfx.set(0.07, 0.07, 0.07, 1)
  gfx.rect(0, 0, gfx.w, gfx.h, 1)

  -- title
  gfx.setfont(1, FONT_MAIN, TITLE_SIZE)
  gfx.set(0.95, 0.95, 0.95, 1)
  gfx.x = PAD_L
  gfx.y = PAD_L
  gfx.drawstr("Region Time Counter Mini")

  -- time
  gfx.setfont(1, FONT_MAIN, TIME_SIZE)
  gfx.set(1, 1, 1, 1)
  gfx.x = PAD_L
  gfx.y = math.floor(PAD_L + TITLE_SIZE + GAP)
  gfx.drawstr(format_hhmmss(total_sec))

  gfx.update()
  reaper.defer(loop)
end

-- ===== Init =====
gfx.init(WINDOW_TITLE, 260, 110, 0) -- seed size
refresh()
ensure_window_size_fixed_width()
loop()

