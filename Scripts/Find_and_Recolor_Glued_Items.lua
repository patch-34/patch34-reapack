-- @description Find and Recolor Glued Items
-- @version 1.2.0
-- @author Aleksei Vorobev / Patch34
-- @link
--   GitHub repository https://github.com/patch-34/find-and-recolor-glued-items
-- @about
--   Finds and recolors glued derivatives of a selected item, with automatic coloring while running.
-- @changelog
--   1.2.0: Glued-derivative matching, Find action, automatic coloring on Glue events, and UI improvements.

local r = reaper

-- ──────────────────────────────────────────────
-- WINDOW
-- ──────────────────────────────────────────────
local WIN_W     = 250
local WIN_H     = 96
local WIN_TITLE = "Glued Items"
local WIN_X     = 280
local WIN_Y     = 630
local FONT_SZ   = 14
local BAR_H     = 6

-- ── Cross glyph tuning ────────────────────────
local CROSS_FONT_SZ  = 35
local CROSS_OFFSET_Y = 1
local CROSS_OFFSET_X = 0

-- ──────────────────────────────────────────────
-- PALETTE  — muted amber
-- ──────────────────────────────────────────────
local CLR = {
  bg         = { 0.13, 0.13, 0.13 },
  bar        = { 0.52, 0.32, 0.04 },
  btn_idle   = { 0.20, 0.20, 0.20 },
  btn_hover  = { 0.27, 0.27, 0.27 },
  btn_press  = { 0.14, 0.14, 0.14 },
  btn_dim    = { 0.15, 0.15, 0.15 },
  btn_border = { 0.09, 0.09, 0.09 },
  label_dim  = { 0.70, 0.70, 0.70 },
  label_key  = { 1.00, 1.00, 1.00 },
  label_stat = { 0.88, 0.88, 0.88 },
}

-- ──────────────────────────────────────────────
-- STATE
-- ──────────────────────────────────────────────
local remembered_name  = ""
local last_color_r     = -1
local last_color_g     = -1
local last_color_b     = -1
local last_native      = 0
local status           = "Select an item → Set"

local last_undo_pos    = r.Undo_GetPos2 and r.Undo_GetPos2(0) or nil
local last_fallback_cc = r.GetProjectStateChangeCount(0)

-- ──────────────────────────────────────────────
-- HELPERS
-- ──────────────────────────────────────────────
local function sc(t, a)
  gfx.set(t[1], t[2], t[3], a or 1.0)
end

local function get_visible_name(item)
  if not item then return "" end
  local _, iname = r.GetSetMediaItemInfo_String(item, "P_NAME", "", false)
  if iname and iname ~= "" then return iname end
  local take = r.GetActiveTake(item)
  if take then return r.GetTakeName(take) or "" end
  return ""
end

local function fit_str(s, max_w)
  if gfx.measurestr(s) <= max_w then return s end
  while #s > 1 do
    s = s:sub(1, -2)
    if gfx.measurestr(s .. "…") <= max_w then return s .. "…" end
  end
  return "…"
end

-- Case-insensitive: name contains source (or its stem) AND "glued"
local function item_matches(vname)
  if vname == "" or remembered_name == "" then return false end
  local lv = vname:lower()
  local lr = remembered_name:lower()
  if not lv:find("glued", 1, true) then return false end
  if lv:find(lr, 1, true) then return true end
  local stem = lr:match("^(.+)%.[^%.]+$") or lr
  return lv:find(stem, 1, true) ~= nil
end

local function for_each_match(fn)
  for t = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, t)
    for i = 0, r.CountTrackMediaItems(tr) - 1 do
      local it = r.GetTrackMediaItem(tr, i)
      if item_matches(get_visible_name(it)) then fn(it) end
    end
  end
end

-- ──────────────────────────────────────────────
-- ACTIONS
-- ──────────────────────────────────────────────
local function action_set()
  local sel = r.GetSelectedMediaItem(0, 0)
  if not sel then status = "No item selected"; return end
  local name = get_visible_name(sel)
  if name == "" then status = "Item has no name"; return end
  remembered_name = name
  status = "Find and/or choose color"
end

local function action_color()
  if remembered_name == "" then status = "Press Set first"; return end
  local init_col = last_native ~= 0 and last_native or r.ColorToNative(128, 128, 128)
  local rv, native = r.GR_SelectColor(init_col)
  if rv == 0 then status = "Cancelled"; return end

  last_native = native
  last_color_r, last_color_g, last_color_b = r.ColorFromNative(native)

  local col_flagged = r.ColorToNative(last_color_r, last_color_g, last_color_b) | 0x1000000
  r.Undo_BeginBlock()
  local changed = 0
  r.PreventUIRefresh(1)
  for_each_match(function(it)
    r.SetMediaItemInfo_Value(it, "I_CUSTOMCOLOR", col_flagged)
    changed = changed + 1
  end)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock(
    ("Find and Recolor Glued Items — Recolor \"%s\" (%d items)"):format(remembered_name, changed), -1)
  status = changed == 0
    and "No matches found"
    or  ("Colored %d item%s"):format(changed, changed == 1 and "" or "s")
end

local function action_find()
  if remembered_name == "" then return end
  for t = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, t)
    for i = 0, r.CountTrackMediaItems(tr) - 1 do
      r.SetMediaItemSelected(r.GetTrackMediaItem(tr, i), false)
    end
  end
  local count = 0
  for_each_match(function(it)
    r.SetMediaItemSelected(it, true)
    count = count + 1
  end)
  r.UpdateArrange()
  status = count == 0
    and "No glued items found"
    or  ("Found %d item%s"):format(count, count == 1 and "" or "s")
end

local function action_reset()
  remembered_name = ""
  last_color_r    = -1
  last_color_g    = -1
  last_color_b    = -1
  last_native     = 0   -- stops auto-color of new glued items
  status          = "Select an item → Set"
end

-- Auto-color on Glue: fires when undo stack gets a glue step
local function color_glued_selected()
  if last_native == 0 or remembered_name == "" then return end
  local rr, gg, bb = r.ColorFromNative(last_native)
  local col_flagged = r.ColorToNative(rr, gg, bb) | 0x1000000
  local n = r.CountSelectedMediaItems(0)
  local changed = 0
  r.PreventUIRefresh(1)
  for i = 0, n - 1 do
    local it = r.GetSelectedMediaItem(0, i)
    if item_matches(get_visible_name(it)) then
      r.SetMediaItemInfo_Value(it, "I_CUSTOMCOLOR", col_flagged)
      changed = changed + 1
    end
  end
  r.PreventUIRefresh(-1)
  if changed > 0 then r.UpdateArrange() end
end

local function is_glue_desc(s)
  return type(s) == "string" and s:lower():find("glue", 1, true) ~= nil
end

local function check_undo_for_glue()
  local desc = r.Undo_CanUndo2 and r.Undo_CanUndo2(0) or ""
  if r.Undo_GetPos2 then
    local pos = r.Undo_GetPos2(0)
    if pos ~= last_undo_pos then
      last_undo_pos = pos
      if is_glue_desc(desc) then color_glued_selected() end
    end
  else
    local cc = r.GetProjectStateChangeCount(0)
    if cc ~= last_fallback_cc then
      last_fallback_cc = cc
      if is_glue_desc(desc) then color_glued_selected() end
    end
  end
end

-- ──────────────────────────────────────────────
-- MOUSE
-- ──────────────────────────────────────────────
local mouse = { x = 0, y = 0, down = false, prev = false }

local function mouse_tick()
  mouse.x    = gfx.mouse_x
  mouse.y    = gfx.mouse_y
  mouse.down = (gfx.mouse_cap & 1) == 1
  local clicked = mouse.down and not mouse.prev
  mouse.prev = mouse.down
  return clicked
end

local function hit(px, py, x, y, w, h)
  return px >= x and px <= x + w and py >= y and py <= y + h
end

-- ──────────────────────────────────────────────
-- DRAW
-- ──────────────────────────────────────────────
local function draw_btn(x, y, w, h, label, hovered, pressed, disabled)
  if disabled    then sc(CLR.btn_dim)
  elseif pressed then sc(CLR.btn_press)
  elseif hovered then sc(CLR.btn_hover)
  else                sc(CLR.btn_idle) end
  gfx.rect(x, y, w, h, 1)

  sc(CLR.btn_border)
  gfx.rect(x, y, w, h, 0)

  if not pressed and not disabled then
    gfx.set(1, 1, 1, 0.03)
    gfx.rect(x + 1, y + 1, w - 2, 1, 1)
  end

  gfx.set(1, 1, 1, disabled and 0.22 or (pressed and 0.55 or 0.88))
  local tw, th = gfx.measurestr(label)
  gfx.x = math.floor(x + (w - tw) / 2)
  gfx.y = math.floor(y + (h - th) / 2)
  gfx.drawstr(label)
end

-- ──────────────────────────────────────────────
-- LAYOUT
-- (WIN_W - 2×PAD - 2×GAP) / 3 = (250 - 34) / 3 = 72
-- ──────────────────────────────────────────────
local PAD     = 10
local TEXT_X  = PAD + 1
local GAP     = 7

local BTN_H   = 26
local BTN_W   = 72
local BTN_Y   = BAR_H + PAD           -- 16
local SET_X   = PAD                    -- 10,  right edge 82
local COL_X   = PAD + BTN_W + GAP     -- 89,  right edge 161
local SEL_X   = COL_X + BTN_W + GAP   -- 168, right edge 240 = WIN_W-PAD ✓

local ROW_H   = 20
local KEY_Y   = BTN_Y + BTN_H + 9     -- 51

local BOX_SZ  = 18
local BOX_GAP = 5
local RST_X   = SEL_X + BTN_W - BOX_SZ        -- 222
local RST_Y   = KEY_Y + math.floor((ROW_H - BOX_SZ) / 2)
local SW_X    = RST_X - BOX_SZ - BOX_GAP       -- 199
local SW_Y    = RST_Y

local STAT_Y  = KEY_Y + ROW_H         -- 71

-- ──────────────────────────────────────────────
-- MAIN LOOP
-- ──────────────────────────────────────────────
gfx.init(WIN_TITLE, WIN_W, WIN_H, 0, WIN_X, WIN_Y)
gfx.setfont(1, "Courier New", FONT_SZ)

local function loop()
  check_undo_for_glue()

  sc(CLR.bg)
  gfx.rect(0, 0, gfx.w, gfx.h, 1)
  sc(CLR.bar)
  gfx.rect(0, 0, gfx.w, BAR_H, 1)

  local clicked   = mouse_tick()
  local has_match = remembered_name ~= ""
  local has_color = last_color_r >= 0

  -- Hit areas
  local ov_set  = hit(mouse.x, mouse.y, SET_X, BTN_Y, BTN_W, BTN_H)
  local ov_find = hit(mouse.x, mouse.y, COL_X, BTN_Y, BTN_W, BTN_H)
  local ov_col  = hit(mouse.x, mouse.y, SEL_X, BTN_Y, BTN_W, BTN_H)
  local ov_rst  = has_match and hit(mouse.x, mouse.y, RST_X, RST_Y, BOX_SZ, BOX_SZ)

  -- ── Main button row ────────────────────────
  draw_btn(SET_X, BTN_Y, BTN_W, BTN_H, "Set",
    ov_set, ov_set and mouse.down, false)
  draw_btn(COL_X, BTN_Y, BTN_W, BTN_H, "Find",
    ov_find, ov_find and mouse.down, not has_match)
  draw_btn(SEL_X, BTN_Y, BTN_W, BTN_H, "Color",
    ov_col, ov_col and mouse.down, not has_match)

  -- ── Click handling ─────────────────────────
  if clicked then
    if ov_set                then action_set()   end
    if ov_col  and has_match then action_color() end
    if ov_find and has_match then action_find()  end
    if ov_rst                then action_reset() end
  end

  -- ── MATCH label + name ─────────────────────
  local _, fh = gfx.measurestr("M")
  local text_y = KEY_Y + math.floor((ROW_H - fh) / 2)

  sc(CLR.label_dim)
  gfx.x, gfx.y = TEXT_X, text_y
  gfx.drawstr("MATCH  ")

  sc(CLR.label_key)
  local max_key_w = SW_X - BOX_GAP - gfx.x
  gfx.drawstr(fit_str(has_match and remembered_name or "—", max_key_w))

  -- ── Swatch ─────────────────────────────────
  if has_color then
    gfx.set(last_color_r / 255, last_color_g / 255, last_color_b / 255, 1)
    gfx.rect(SW_X, SW_Y, BOX_SZ, BOX_SZ, 1)
    gfx.set(0, 0, 0, 0.30)
    gfx.rect(SW_X, SW_Y, BOX_SZ, BOX_SZ, 1)
  else
    sc(CLR.bg)
    gfx.rect(SW_X, SW_Y, BOX_SZ, BOX_SZ, 1)
  end

  -- ── Reset box ──────────────────────────────
  if has_match then
    if ov_rst then sc(CLR.btn_hover) else sc(CLR.btn_idle) end
    gfx.rect(RST_X, RST_Y, BOX_SZ, BOX_SZ, 1)
    sc(CLR.btn_border)
    gfx.rect(RST_X, RST_Y, BOX_SZ, BOX_SZ, 0)

    gfx.setfont(1, "Courier New", CROSS_FONT_SZ)
    local xw, xh = gfx.measurestr("×")
    gfx.x = math.floor(RST_X + (BOX_SZ - xw) / 2) + CROSS_OFFSET_X
    gfx.y = math.floor(RST_Y + (BOX_SZ - xh) / 2) + CROSS_OFFSET_Y
    gfx.set(1, 1, 1, ov_rst and 1.0 or 0.75)
    gfx.drawstr("×")
    gfx.setfont(1, "Courier New", FONT_SZ)
  end

  -- ── Status ─────────────────────────────────
  sc(CLR.label_stat)
  local _, sh = gfx.measurestr("A")
  gfx.x, gfx.y = TEXT_X, STAT_Y + math.floor((ROW_H - sh) / 2)
  gfx.drawstr(fit_str(status, gfx.w - PAD * 2))

  if gfx.getchar() >= 0 then
    r.defer(loop)
  end
end

loop()
