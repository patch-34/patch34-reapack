-- Region Time Counter
-- @description Region Time Counter
-- @version 3.1.0
-- @author Aleksei Vorobev / Patch34
-- @link https://github.com/patch-34/patch34-reapack
-- @about
--   Region Time Counter is a REAPER ReaScript for browsing markers and regions,
--   selecting regions, and calculating the total and selected timeline duration
--   without double-counting overlapping regions.
--   Features searchable marker/region lists, per-project checked state,
--   REAPER custom color swatches and double-click timeline navigation.
--   Requires ReaImGui. No SWS or js_ReaScriptAPI required.
--   License: MIT. Documentation: https://github.com/patch-34/patch34-reapack
-- @changelog
--   Public name is now Region Time Counter (formerly Region Time Counter Pro).
--   Refreshed table and controls; improved search and mouse interaction.
--   Show user-assigned REAPER marker and region colors in the list.
--   Keep checked selections independent across open project tabs.
--   Clean up deleted marker/region IDs in saved project state.
--   Add a clear message when ReaImGui is missing and streamline auto-refresh.

local r = reaper
local proj = nil  -- active ReaProject handle; never use 0 for cross-tab state

-- =============================================================
-- WINDOW
-- =============================================================
local WINDOW_TITLE = "Region Time Counter"
local INIT_W, INIT_H = 500, 560
local MIN_W,  MIN_H  = 470, 340

-- =============================================================
-- ╔══════════════════════════════════════════════════════════╗
-- ║              БЛОК UI-НАСТРОЕК (ВСЁ ЗДЕСЬ)               ║
-- ╚══════════════════════════════════════════════════════════╝
-- =============================================================

-- РАЗДЕЛ 1 — РАЗМЕРЫ ШРИФТОВ В ПИКСЕЛЯХ (CreateFont)
-- Каждая роль получает свой font object через ImGui_CreateFont.
-- Если нужно изменить размер — меняется только здесь.
local FONT_SIZE_BODY        = 14   -- кнопки, fallback
local FONT_SIZE_STATS_LABEL = 22   -- "Total:" / "Selected:"
local FONT_SIZE_STATS_VALUE = 18   -- таймкоды в stats
local FONT_SIZE_LIST        = 13   -- текст строк таблицы
local FONT_SIZE_LIST_TC     = 12   -- таймкоды строк таблицы

-- РАЗДЕЛ 2 — ЦВЕТА
local UI_TEXT_R, UI_TEXT_G, UI_TEXT_B, UI_TEXT_A = 0.0, 0.0, 0.0, 1.0
local UI_TEXT_LABEL_A = 0.70
local UI_TEXT_DIM_A   = 0.55

-- РАЗДЕЛ 3 — РАЗМЕРЫ КНОПОК
local BTN_W_ALL   = 50
local BTN_W_CLEAR = 80
local BTN_H   = 26
local BTN_GAP = 10
local CORNER_RADIUS = 5  -- ◄ NEW v0.5.19: скругление углов кнопок, поиска и таблицы (px)

-- РАЗДЕЛ 4 — ПОЛЕ ПОИСКА
local SEARCH_W = 275  -- фиксированная ширина (прижата к правому краю)

-- РАЗДЕЛ 5 — ОТСТУПЫ ОКНА
local PAD = 14
local GAP = 6
local TITLEBAR_FRAMEPAD_X = 6
local TITLEBAR_FRAMEPAD_Y = 2

-- РАЗДЕЛ 6 — КОЛОНКИ ТАБЛИЦЫ
local COL_CHECKBOX_W = 10
local COL_ID_W       = 30
local COL_TIMECODE_W = 60
local CELL_PAD_X     = 4   -- горизонтальный padding ячейки (совпадает со StyleVar_CellPadding)

-- РАЗДЕЛ 7 — ЧЕКБОКС
local CHECKBOX_SIZE = 12

-- РАЗДЕЛ 8 — STATS
local STATS_VALUE_GAP    = 4
local STATS_VALUE_Y_TUNE = 2  -- ручная вертикальная подстройка значений (px, + = вниз)

-- РАЗДЕЛ 9 — CLICK CONTRACT
local ROW_DOUBLECLICK_WINDOW_SEC = 0.15
local ROW_SINGLE_CLICK_WAIT_SEC  = 0.15

-- АВТООБНОВЛЕНИЕ И ПЕРСИСТЕНТНОСТЬ
local AUTO_REFRESH         = true
local REFRESH_INTERVAL_SEC = 0.5
local EXT_SECTION          = "RTCPro"   -- legacy key, kept for backwards compatibility with saved project state
local EXT_KEY_CHECKED      = "checked_keys"

-- =============================================================
-- ЦВЕТА ИНТЕРФЕЙСА
-- =============================================================
local BG_R,     BG_G,     BG_B     = 223/255, 225/255, 225/255
local SEL_R,    SEL_G,    SEL_B    = 241/255, 241/255, 241/255
local BORDER_R, BORDER_G, BORDER_B = 192/255, 202/255, 202/255

local BTN_BORDER_R,    BTN_BORDER_G,    BTN_BORDER_B    = 210/255, 210/255, 208/255
local SEARCH_BORDER_R, SEARCH_BORDER_G, SEARCH_BORDER_B = 210/255, 210/255, 208/255

local SQ_REGION_R, SQ_REGION_G, SQ_REGION_B = 0.55, 0.55, 0.55
local SQ_MARKER_R, SQ_MARKER_G, SQ_MARKER_B = 0.75, 0.10, 0.10
local SQ_FILL_A   = 0.06
local SQ_BORDER_A = 0.85
local SQ_CUSTOM_FILL_A = 0.88 -- Custom REAPER colors must remain visible in small swatches.

local COL_TOTAL = {0.10, 0.55, 0.15, 1.0}
local COL_SEL   = {0.65, 0.52, 0.05, 1.0}


-- =============================================================
-- СОСТОЯНИЕ
-- =============================================================
local items        = {}
local region_by_id = {}
local checked      = {}

local total_sec    = 0.0
local selected_sec = 0.0
local last_refresh = 0.0

local search_query = ""
local search_buf   = ""
local display      = {}

local last_clicked_disp_index = nil
local last_clicked_disp_key   = nil

local pending_row_click = nil
local suppress_next_release_click_key = nil

local ctx         = nil
local window_open = true

-- Font objects (created at init, attached to context)
local font_body        = nil
local font_stats_label = nil
local font_stats_value = nil
local font_list        = nil
local font_list_tc     = nil

-- Стартап-стабилизация
local STARTUP_HIDE_FRAMES = 2
local startup_frames = 0

-- =============================================================
-- УТИЛИТЫ
-- =============================================================

local UI_FALLBACK_TEXT_H = 13
local UI_FALLBACK_CHAR_W = 9

local function trim(s)
  if not s then return "" end
  return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function utf8_chars(s)
  return tostring(s or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*")
end

local function utf8_len(s)
  local n = 0
  for _ in utf8_chars(s) do n = n + 1 end
  return n
end

local function rgbaf_u32(rv, gv, bv, av)
  local function c01(v) if v < 0 then return 0 elseif v > 1 then return 1 else return v end end
  local ri = math.floor(c01(rv) * 255 + 0.5)
  local gi = math.floor(c01(gv) * 255 + 0.5)
  local bi = math.floor(c01(bv) * 255 + 0.5)
  local ai = math.floor(c01(av) * 255 + 0.5)
  return ri * 0x1000000 + gi * 0x10000 + bi * 0x100 + ai
end

-- EnumProjectMarkers3 returns a platform-dependent native RGB value; bit 24
-- indicates that the marker/region has a custom color. REAPER's default color
-- is represented by zero and must keep the original UI palette.
local function marker_custom_rgb(native_color)
  native_color = tonumber(native_color) or 0
  if (native_color & 0x1000000) == 0 or not r.ColorFromNative then return nil end
  local red, green, blue = r.ColorFromNative(native_color & 0xFFFFFF)
  if red == nil or green == nil or blue == nil then return nil end
  return { red / 255, green / 255, blue / 255 }
end

local function enum_or(name, fallback)
  local fn = r[name]
  if fn then
    local ok, v = pcall(fn)
    if ok and v ~= nil then return v end
  end
  return fallback
end

-- ImGui enums
local function Col_Text()                 return enum_or('ImGui_Col_Text', 0)                  end
local function Col_WindowBg()             return enum_or('ImGui_Col_WindowBg', 2)              end
local function Col_Border()               return enum_or('ImGui_Col_Border', 5)                end
local function Col_FrameBg()              return enum_or('ImGui_Col_FrameBg', 7)               end
local function Col_FrameBgHovered()       return enum_or('ImGui_Col_FrameBgHovered', 8)        end
local function Col_Button()               return enum_or('ImGui_Col_Button', 21)               end
local function Col_ButtonHovered()        return enum_or('ImGui_Col_ButtonHovered', 22)        end
local function Col_ButtonActive()         return enum_or('ImGui_Col_ButtonActive', 23)         end
local function Col_ScrollbarBg()          return enum_or('ImGui_Col_ScrollbarBg', 14)          end
local function Col_ScrollbarGrab()        return enum_or('ImGui_Col_ScrollbarGrab', 15)        end
local function Col_ScrollbarGrabHovered() return enum_or('ImGui_Col_ScrollbarGrabHovered', 16) end
local function Col_ScrollbarGrabActive()  return enum_or('ImGui_Col_ScrollbarGrabActive', 17)  end
local function Col_TableBorderStrong()    return enum_or('ImGui_Col_TableBorderStrong', 27)    end
local function Col_TableBorderLight()     return enum_or('ImGui_Col_TableBorderLight', 28)     end
local function Col_TableRowBg()           return enum_or('ImGui_Col_TableRowBg', 29)           end
local function Col_Header()               return enum_or('ImGui_Col_Header', 24)               end
local function Col_HeaderHovered()        return enum_or('ImGui_Col_HeaderHovered', 25)        end
local function Col_HeaderActive()         return enum_or('ImGui_Col_HeaderActive', 26)         end

local function StyleVar_WindowPadding()   return enum_or('ImGui_StyleVar_WindowPadding', 0)    end
local function StyleVar_WindowRounding()  return enum_or('ImGui_StyleVar_WindowRounding', 1)   end
local function StyleVar_FrameRounding()   return enum_or('ImGui_StyleVar_FrameRounding', 5)    end  -- ◄ NEW v0.5.19
local function StyleVar_ChildRounding()   return enum_or('ImGui_StyleVar_ChildRounding', 3)    end  -- ◄ NEW v0.5.19
local function StyleVar_FramePadding()    return enum_or('ImGui_StyleVar_FramePadding', 7)     end
local function StyleVar_CellPadding()     return enum_or('ImGui_StyleVar_CellPadding', 18)     end
local function StyleVar_FrameBorderSize() return enum_or('ImGui_StyleVar_FrameBorderSize', 6)  end

local function WindowFlags_NoCollapse()   return enum_or('ImGui_WindowFlags_NoCollapse', 32)   end

local function TableFlags_BordersInnerH() return enum_or('ImGui_TableFlags_BordersInnerH', 128)  end
local function TableFlags_BordersInnerV() return enum_or('ImGui_TableFlags_BordersInnerV', 512)  end
local function TableFlags_BordersOuterH() return enum_or('ImGui_TableFlags_BordersOuterH', 64)   end
local function TableFlags_BordersOuterV() return enum_or('ImGui_TableFlags_BordersOuterV', 256)  end
local function TableFlags_ScrollY()       return enum_or('ImGui_TableFlags_ScrollY', 4096)       end
local function TableFlags_NoHostExtendX() return enum_or('ImGui_TableFlags_NoHostExtendX', 16)   end

local function TableColumnFlags_WidthFixed()   return enum_or('ImGui_TableColumnFlags_WidthFixed', 16)    end
local function TableColumnFlags_WidthStretch() return enum_or('ImGui_TableColumnFlags_WidthStretch', 32)  end
local function TableColumnFlags_NoResize()     return enum_or('ImGui_TableColumnFlags_NoResize', 2)       end

local function SelectableFlags_SpanAllColumns() return enum_or('ImGui_SelectableFlags_SpanAllColumns', 2)  end
local function SelectableFlags_AllowOverlap()   return enum_or('ImGui_SelectableFlags_AllowOverlap', 16)   end

local function TableBgTarget_CellBg()     return enum_or('ImGui_TableBgTarget_CellBg', 3)      end

local function Cond_FirstUseEver()        return enum_or('ImGui_Cond_FirstUseEver', 4)         end

-- =============================================================
-- FONT MANAGEMENT
-- =============================================================
-- ReaImGui has two API contracts for fonts:
--   OLD: CreateFont('sans-serif', size) + PushFont(ctx, font)
--   NEW: CreateFont('sans-serif')       + PushFont(ctx, font, size)
-- We probe once at init to determine which one works.
-- font_role_sizes stores the px size per font object (used in NEW contract).

local font_contract = nil  -- 'old' | 'new' | nil (not yet determined)
local font_role_sizes = {} -- font_obj -> px_size (for NEW contract PushFont calls)

local function push_font(ctx_arg, font)
  if not font or not r.ImGui_PushFont then return false end
  if font_contract == 'new' then
    local px = font_role_sizes[font] or FONT_SIZE_BODY
    local ok = pcall(r.ImGui_PushFont, ctx_arg, font, px)
    if ok then return true end
  elseif font_contract == 'old' then
    local ok = pcall(r.ImGui_PushFont, ctx_arg, font)
    if ok then return true end
  end
  return false
end

local function pop_font(ctx_arg, pushed)
  if pushed and r.ImGui_PopFont then
    pcall(r.ImGui_PopFont, ctx_arg)
  end
end

-- =============================================================
-- SAFE WRAPPERS
-- =============================================================

local function safe_push_color(ctx_arg, idx, rv, gv, bv, av)
  if not r.ImGui_PushStyleColor then return false end
  return pcall(r.ImGui_PushStyleColor, ctx_arg, idx, rgbaf_u32(rv, gv, bv, av)) == true
end

local function safe_pop_color(ctx_arg, count)
  if r.ImGui_PopStyleColor then pcall(r.ImGui_PopStyleColor, ctx_arg, count or 1) end
end

local function safe_push_style_var1(ctx_arg, idx, v)
  if not r.ImGui_PushStyleVar then return false end
  return pcall(r.ImGui_PushStyleVar, ctx_arg, idx, v) == true
end

local function safe_push_style_var2(ctx_arg, idx, x, y)
  if not r.ImGui_PushStyleVar then return false end
  return pcall(r.ImGui_PushStyleVar, ctx_arg, idx, x, y) == true
end

local function safe_pop_style_var(ctx_arg, count)
  if r.ImGui_PopStyleVar then pcall(r.ImGui_PopStyleVar, ctx_arg, count or 1) end
end

local function calc_text_size(ctx_arg, text)
  text = tostring(text or "")
  if r.ImGui_CalcTextSize then
    local ok, w, h = pcall(r.ImGui_CalcTextSize, ctx_arg, text)
    if ok and w ~= nil then return w or 0, h or UI_FALLBACK_TEXT_H end
  end
  return utf8_len(text) * UI_FALLBACK_CHAR_W, UI_FALLBACK_TEXT_H
end

local function get_content_avail(ctx_arg)
  if not r.ImGui_GetContentRegionAvail then return 0, 0 end
  local ok, w, h = pcall(r.ImGui_GetContentRegionAvail, ctx_arg)
  if ok and w ~= nil then return w or 0, h or 0 end
  return 0, 0
end

local function safe_same_line(ctx_arg, offset, spacing)
  if not r.ImGui_SameLine then return end
  if offset ~= nil and spacing ~= nil then
    if pcall(r.ImGui_SameLine, ctx_arg, offset, spacing) then return end
  end
  pcall(r.ImGui_SameLine, ctx_arg)
end

local function safe_dummy(ctx_arg, w, h)
  if r.ImGui_Dummy then
    if pcall(r.ImGui_Dummy, ctx_arg, w or 0, h or 0) then return end
  end
  if r.ImGui_Spacing then pcall(r.ImGui_Spacing, ctx_arg) end
end

local function safe_input_text_with_hint(ctx_arg, label, hint, buf)
  if r.ImGui_InputTextWithHint then
    local ok, changed, new_buf = pcall(r.ImGui_InputTextWithHint, ctx_arg, label, hint, buf, 0)
    if ok then return changed, new_buf end
    local ok2, changed2, new_buf2 = pcall(r.ImGui_InputTextWithHint, ctx_arg, label, hint, buf)
    if ok2 then return changed2, new_buf2 end
  end
  if r.ImGui_InputText then
    local ok3, changed3, new_buf3 = pcall(r.ImGui_InputText, ctx_arg, label, buf, 0)
    if ok3 then return changed3, new_buf3 end
    local ok4, changed4, new_buf4 = pcall(r.ImGui_InputText, ctx_arg, label, buf)
    if ok4 then return changed4, new_buf4 end
  end
  return false, buf
end

local function safe_set_next_item_width(ctx_arg, w)
  if r.ImGui_SetNextItemWidth then pcall(r.ImGui_SetNextItemWidth, ctx_arg, w) end
end

local function is_shift_held(ctx_arg)
  if not r.ImGui_IsKeyDown then return false end
  if r.ImGui_Key_LeftShift and r.ImGui_Key_RightShift then
    local ok, value = pcall(function()
      return r.ImGui_IsKeyDown(ctx_arg, r.ImGui_Key_LeftShift())
          or r.ImGui_IsKeyDown(ctx_arg, r.ImGui_Key_RightShift())
    end)
    if ok then return value == true end
  end
  local ok1, v1 = pcall(r.ImGui_IsKeyDown, ctx_arg, 340)
  local ok2, v2 = pcall(r.ImGui_IsKeyDown, ctx_arg, 344)
  return (ok1 and v1 == true) or (ok2 and v2 == true)
end

-- =============================================================
-- ФОРМАТИРОВАНИЕ
-- =============================================================

local function format_hhmmss(sec)
  sec = math.max(0, math.floor((sec or 0) + 0.5))
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = sec % 60
  return string.format('%02d:%02d:%02d', h, m, s)
end

-- =============================================================
-- БИЗНЕС-ЛОГИКА (без изменений)
-- =============================================================

local function union_length(intervals)
  if not intervals or #intervals == 0 then return 0.0 end
  table.sort(intervals, function(a, b)
    if a[1] == b[1] then return a[2] < b[2] end
    return a[1] < b[1]
  end)
  local total  = 0.0
  local cur_s, cur_e = intervals[1][1], intervals[1][2]
  for i = 2, #intervals do
    local s, e = intervals[i][1], intervals[i][2]
    if s <= cur_e then
      if e > cur_e then cur_e = e end
    else
      total  = total + (cur_e - cur_s)
      cur_s, cur_e = s, e
    end
  end
  total = total + (cur_e - cur_s)
  return total
end

local function lower(s)
  s = string.lower(tostring(s or ''))
  s = s:gsub('\xD0\x81', '\xD1\x91')                                            -- Ё → ё
  s = s:gsub('\xD0[\x90-\x9F]', function(c) return string.char(0xD0, c:byte(2) + 0x20) end)
  s = s:gsub('\xD0[\xA0-\xAF]', function(c) return string.char(0xD1, c:byte(2) - 0x20) end)
  return s
end

local function contains_ci(hay, needle)
  if needle == '' then return true end
  return lower(tostring(hay or '')):find(lower(tostring(needle or '')), 1, true) ~= nil
end

local function make_key(isrgn, id)
  return (isrgn and 'R' or 'M') .. tostring(tonumber(id) or 0)
end

local function save_checked()
  local keys = {}
  for k, on in pairs(checked) do if on then keys[#keys + 1] = tostring(k) end end
  table.sort(keys)
  r.SetProjExtState(proj, EXT_SECTION, EXT_KEY_CHECKED, table.concat(keys, ','))
end

local function load_checked()
  -- Clear first: an empty project must never inherit checkmarks from the
  -- previously active tab.
  checked = {}
  local ret, s = r.GetProjExtState(proj, EXT_SECTION, EXT_KEY_CHECKED)
  if ret ~= 1 or not s or s == '' then return end
  for token in tostring(s):gmatch('[RM]%d+') do checked[token] = true end
end

local function rebuild_items()
  items      = {}
  region_by_id = {}
  local _, numMarkers, numRegions = r.CountProjectMarkers(proj)
  local total = numMarkers + numRegions
  for enum_idx = 0, total - 1 do
    local retval, isrgn, pos, rgnend, name, shown_id, native_color = r.EnumProjectMarkers3(proj, enum_idx)
    if retval then
      shown_id = tonumber(shown_id) or 0
      local it = {
        enum_idx = enum_idx,
        isrgn    = (isrgn == true),
        pos      = pos or 0,
        rgnend   = rgnend or 0,
        name     = name or '',
        shown_id = shown_id,
        custom_rgb = marker_custom_rgb(native_color),
        key      = make_key(isrgn == true, shown_id),
        len      = 0.0,
      }
      if it.isrgn and (it.rgnend > it.pos) then
        it.len = it.rgnend - it.pos
        region_by_id[shown_id] = { start = it.pos, ['end'] = it.rgnend }
      end
      items[#items + 1] = it
    end
  end
  table.sort(items, function(a, b)
    if a.pos == b.pos then
      if a.isrgn == b.isrgn then return a.shown_id < b.shown_id end
      return (a.isrgn == false)
    end
    return a.pos < b.pos
  end)
  local existing = {}
  for _, it in ipairs(items) do existing[it.key] = true end
  local removed_checked = false
  for k, _ in pairs(checked) do
    if not existing[k] then
      checked[k] = nil
      removed_checked = true
    end
  end
  -- Keep project ExtState in sync: otherwise a new marker/region reusing an
  -- old ID can inherit the removed item's checkmark after restarting.
  if removed_checked then save_checked() end
  if pending_row_click and not existing[pending_row_click.key] then
    pending_row_click = nil
  end
end

local function compute_total()
  local intervals = {}
  for _, reg in pairs(region_by_id) do intervals[#intervals + 1] = { reg.start, reg['end'] } end
  total_sec = union_length(intervals)
end

local function compute_selected()
  local intervals = {}
  for k, on in pairs(checked) do
    if on and k:sub(1, 1) == 'R' then
      local id  = tonumber(k:sub(2))
      local reg = id and region_by_id[id]
      if reg then intervals[#intervals + 1] = { reg.start, reg['end'] } end
    end
  end
  selected_sec = union_length(intervals)
end

local function rebuild_display(reset_anchor)
  display = {}
  local q = trim(search_query)
  for _, it in ipairs(items) do
    local tag = (it.isrgn and 'R' or 'M') .. tostring(it.shown_id)
    if q == '' or contains_ci(it.name, q) or contains_ci(tag, q) then
      display[#display + 1] = it
    end
  end
  if reset_anchor then
    last_clicked_disp_index = nil
    last_clicked_disp_key   = nil
  end
end

local function refresh(reset_anchor)
  rebuild_items()
  compute_total()
  compute_selected()
  rebuild_display(reset_anchor)
  last_refresh = r.time_precise()
end

local function sync_active_project()
  -- EnumProjects(-1) returns the active project's stable ReaProject handle.
  -- proj=0 follows whichever tab is active, which would mix saved selections.
  local active = r.EnumProjects(-1, '')
  if active == nil or active == proj then return end
  proj = active
  pending_row_click = nil
  suppress_next_release_click_key = nil
  last_clicked_disp_index = nil
  last_clicked_disp_key = nil
  load_checked()
  refresh(true)
end

local function set_all(on)
  if on then
    for _, it in ipairs(items) do checked[it.key] = true end
  else
    checked = {}
  end
  compute_selected()
  save_checked()
end

local function apply_range(from_i, to_i, on)
  if from_i > to_i then from_i, to_i = to_i, from_i end
  for i = from_i, to_i do
    local it = display[i]
    if it then
      if on then checked[it.key] = true else checked[it.key] = nil end
    end
  end
end

-- =============================================================
-- CLICK CONTRACT
-- =============================================================

-- Resolve a key to its current index in display[]. Returns nil if not found
-- (item may have been removed by refresh since the click was registered).
local function display_index_of(key)
  if not key then return nil end
  for i, it in ipairs(display) do
    if it.key == key then return i end
  end
  return nil
end

local function commit_pending()
  if not pending_row_click then return end
  -- A removed target must not be written back by a delayed click.
  local target_exists = false
  for _, it in ipairs(items) do
    if it.key == pending_row_click.key then
      target_exists = true
      break
    end
  end
  if not target_exists then
    pending_row_click = nil
    return
  end
  if pending_row_click.shift and pending_row_click.anchor_key then
    -- Resolve both keys to current display indices.
    -- This is safe even if refresh rebuilt display[] between click and commit.
    local anchor_i = display_index_of(pending_row_click.anchor_key)
    local target_i = display_index_of(pending_row_click.key)
    if anchor_i and target_i then
      apply_range(anchor_i, target_i, pending_row_click.desired)
    else
      -- Anchor or target disappeared after refresh — fall back to single toggle
      if pending_row_click.desired then
        checked[pending_row_click.key] = true
      else
        checked[pending_row_click.key] = nil
      end
    end
  else
    if pending_row_click.desired then
      checked[pending_row_click.key] = true
    else
      checked[pending_row_click.key] = nil
    end
  end
  last_clicked_disp_key   = pending_row_click.key
  last_clicked_disp_index = display_index_of(pending_row_click.key)
  compute_selected()
  save_checked()
  pending_row_click = nil
end

-- =============================================================
-- GEOMETRIC TICK (две линии внутри квадрата)
-- =============================================================
-- Рисует галку как два отрезка: короткий и длинный.
-- Все координаты — в геометрии чекбокса, привязка к sx, sy, sq.
-- Никакой зависимости от font system.
local function draw_tick(dl, sx, sy, sq, col_u32)
  if not r.ImGui_DrawList_AddLine then return end
  -- Tick вписан в квадрат с инсетом 2px от каждого края.
  local inset = 3
  local x1 = sx + inset
  local y1 = sy + math.floor(sq * 0.55)
  local x_mid = sx + math.floor(sq * 0.4)
  local y_mid = sy + sq - inset
  local x2 = sx + sq - inset
  local y2 = sy + inset
  local thick = 1.5
  pcall(r.ImGui_DrawList_AddLine, dl, x1, y1, x_mid, y_mid, col_u32, thick)
  pcall(r.ImGui_DrawList_AddLine, dl, x_mid, y_mid, x2, y2, col_u32, thick)
end

-- =============================================================
-- FRAME
-- =============================================================

local function frame()
  if not ctx then return end

  -- Detect project tab changes on every frame, not just on the timer.
  sync_active_project()

  if AUTO_REFRESH then
    local now = r.time_precise()
    if (now - last_refresh) >= REFRESH_INTERVAL_SEC then
      local keep = search_query
      refresh(false)
      search_query = keep
      search_buf   = keep
    end
  end

  -- Window style
  local pushed_sv = 0
  local pushed_cl = 0
  if safe_push_style_var2(ctx, StyleVar_WindowPadding(), PAD, PAD)                                     then pushed_sv = pushed_sv + 1 end
  if safe_push_style_var1(ctx, StyleVar_WindowRounding(), 0)                                           then pushed_sv = pushed_sv + 1 end
  if safe_push_style_var2(ctx, StyleVar_FramePadding(), TITLEBAR_FRAMEPAD_X, TITLEBAR_FRAMEPAD_Y)      then pushed_sv = pushed_sv + 1 end
  if safe_push_color(ctx, Col_WindowBg(), BG_R, BG_G, BG_B, 1)                                        then pushed_cl = pushed_cl + 1 end
  if safe_push_color(ctx, Col_Border(),   BORDER_R, BORDER_G, BORDER_B, 1)                             then pushed_cl = pushed_cl + 1 end

  if r.ImGui_SetNextWindowSizeConstraints then
    pcall(r.ImGui_SetNextWindowSizeConstraints, ctx, MIN_W, MIN_H, 10000, 10000)
  end
  if r.ImGui_SetNextWindowSize then
    pcall(r.ImGui_SetNextWindowSize, ctx, INIT_W, INIT_H, Cond_FirstUseEver())
  end

  local visible
  visible, window_open = r.ImGui_Begin(ctx, WINDOW_TITLE, window_open, WindowFlags_NoCollapse())

  if pushed_cl > 0 then safe_pop_color(ctx, pushed_cl) end
  if pushed_sv > 0 then safe_pop_style_var(ctx, pushed_sv) end

  if visible then
    local text_col_pushed = 0
    if safe_push_color(ctx, Col_Text(), UI_TEXT_R, UI_TEXT_G, UI_TEXT_B, UI_TEXT_A) then
      text_col_pushed = 1
    end

    -- Стартап-стабилизация
    if startup_frames < STARTUP_HIDE_FRAMES then
      startup_frames = startup_frames + 1
      if text_col_pushed > 0 then safe_pop_color(ctx, text_col_pushed) end
      r.ImGui_End(ctx)
      if window_open then r.defer(frame) else
        if r.ImGui_DestroyContext then pcall(r.ImGui_DestroyContext, ctx) end
        ctx = nil
      end
      return
    end

    local content_w = select(1, get_content_avail(ctx))
    if content_w < 100 then content_w = 100 end

    -- =========================================================
    -- STATS BLOCK — PushFont для каждой роли
    -- =========================================================
    do
      safe_dummy(ctx, 0, 0)

      local total_str = format_hhmmss(total_sec)
      local sel_str   = format_hhmmss(selected_sec)

      local label_total    = 'Total:'
      local label_selected = 'Selected:'

      -- Измеряем ширины в правильных шрифтах
      local lf = push_font(ctx, font_stats_label)
      local w_total_label    = select(1, calc_text_size(ctx, label_total))
      local w_selected_label = select(1, calc_text_size(ctx, label_selected))
      local label_h          = select(2, calc_text_size(ctx, label_total))
      local label_col_w      = math.max(w_total_label, w_selected_label)
      pop_font(ctx, lf)

      local vf = push_font(ctx, font_stats_value)
      local value_col_w   = select(1, calc_text_size(ctx, '000:00:00'))
      local value_h       = select(2, calc_text_size(ctx, '000:00:00'))
      pop_font(ctx, vf)

      local stats_block_w = label_col_w + STATS_VALUE_GAP + value_col_w

      -- Центрируем по ширине окна (а не по content_w, который зависит от cursor pos).
      -- GetWindowSize возвращает полную ширину окна, вычитаем 2*PAD.
      local stats_area_w = content_w
      if r.ImGui_GetWindowSize then
        local ok_ws, win_w = pcall(r.ImGui_GetWindowSize, ctx)
        if ok_ws and win_w and win_w > 0 then
          stats_area_w = win_w - 2 * PAD
        end
      end

      -- SetCursorPos X=0 is at the window edge (before padding), so we add PAD
      -- to offset into the content area before centering the block.
      local center_x = PAD + math.floor((stats_area_w - stats_block_w) * 0.5 + 0.5)
      if center_x < 0 then center_x = 0 end

      local value_x = center_x + label_col_w + STATS_VALUE_GAP

      local row_h = math.max(label_h or 14, value_h or 14) + 2

      -- Вертикальное выравнивание label и value при разных размерах
      local label_y_offset = 0
      local value_y_offset = 0
      if (label_h or 0) > (value_h or 0) then
        value_y_offset = math.floor(((label_h or 0) - (value_h or 0)) * 0.5)
      elseif (value_h or 0) > (label_h or 0) then
        label_y_offset = math.floor(((value_h or 0) - (label_h or 0)) * 0.5)
      end

      if r.ImGui_GetCursorPos then
        local ok_cp, base_x, base_y = pcall(r.ImGui_GetCursorPos, ctx)
        if ok_cp and base_x ~= nil then
          -- Labels right-aligned within label column (colons line up)
          local total_label_x    = center_x + label_col_w - w_total_label
          local selected_label_x = center_x + label_col_w - w_selected_label

          -- Row 1: Total
          pcall(r.ImGui_SetCursorPos, ctx, total_label_x, base_y + label_y_offset)
          local lf1 = push_font(ctx, font_stats_label)
          if safe_push_color(ctx, Col_Text(), UI_TEXT_R, UI_TEXT_G, UI_TEXT_B, UI_TEXT_LABEL_A) then
            r.ImGui_Text(ctx, label_total)
            safe_pop_color(ctx, 1)
          else
            r.ImGui_Text(ctx, label_total)
          end
          pop_font(ctx, lf1)

          local total_val_x = value_x
          local total_val_y = base_y + value_y_offset + STATS_VALUE_Y_TUNE
          pcall(r.ImGui_SetCursorPos, ctx, total_val_x, total_val_y)
          local vf1 = push_font(ctx, font_stats_value)
          if safe_push_color(ctx, Col_Text(), COL_TOTAL[1], COL_TOTAL[2], COL_TOTAL[3], COL_TOTAL[4]) then
            r.ImGui_Text(ctx, total_str)
            safe_pop_color(ctx, 1)
          else
            r.ImGui_Text(ctx, total_str)
          end
          pop_font(ctx, vf1)

          -- Row 2: Selected
          local row2_y = base_y + row_h
          pcall(r.ImGui_SetCursorPos, ctx, selected_label_x, row2_y + label_y_offset)
          local lf2 = push_font(ctx, font_stats_label)
          if safe_push_color(ctx, Col_Text(), UI_TEXT_R, UI_TEXT_G, UI_TEXT_B, UI_TEXT_LABEL_A) then
            r.ImGui_Text(ctx, label_selected)
            safe_pop_color(ctx, 1)
          else
            r.ImGui_Text(ctx, label_selected)
          end
          pop_font(ctx, lf2)

          local sel_val_x = value_x
          local sel_val_y = row2_y + value_y_offset + STATS_VALUE_Y_TUNE
          pcall(r.ImGui_SetCursorPos, ctx, sel_val_x, sel_val_y)
          local vf2 = push_font(ctx, font_stats_value)
          if safe_push_color(ctx, Col_Text(), COL_SEL[1], COL_SEL[2], COL_SEL[3], COL_SEL[4]) then
            r.ImGui_Text(ctx, sel_str)
            safe_pop_color(ctx, 1)
          else
            r.ImGui_Text(ctx, sel_str)
          end
          pop_font(ctx, vf2)

          pcall(r.ImGui_SetCursorPos, ctx, base_x, base_y + row_h * 2)
        end
      end
    end

    safe_dummy(ctx, 0, GAP)

    -- =========================================================
    -- КНОПКИ ALL / CLEAR + SEARCH
    -- =========================================================
    do
      local btn_sv = 0
      local btn_cl = 0

      local btn_font_pushed = push_font(ctx, font_body)

      -- Compute vertical padding to center text in BTN_H
      local btn_text_h = select(2, calc_text_size(ctx, "All"))
      local btn_pad_y = math.max(0, math.floor((BTN_H - btn_text_h) / 2))
      if safe_push_style_var1(ctx, StyleVar_FrameRounding(), CORNER_RADIUS)                                   then btn_sv = btn_sv + 1 end  -- ◄ NEW v0.5.19
      if safe_push_style_var1(ctx, StyleVar_FrameBorderSize(), 1)                                              then btn_sv = btn_sv + 1 end
      if safe_push_style_var2(ctx, StyleVar_FramePadding(), 6, btn_pad_y)                                    then btn_sv = btn_sv + 1 end
      if safe_push_color(ctx, Col_Button(),        BG_R + 0.04,   BG_G + 0.04,   BG_B + 0.04,   1)        then btn_cl = btn_cl + 1 end
      if safe_push_color(ctx, Col_ButtonHovered(),  SEL_R,         SEL_G,         SEL_B,         1)         then btn_cl = btn_cl + 1 end
      if safe_push_color(ctx, Col_ButtonActive(),   SEL_R - 0.05,  SEL_G - 0.05,  SEL_B - 0.05,  1)       then btn_cl = btn_cl + 1 end
      if safe_push_color(ctx, Col_Border(),         BTN_BORDER_R,  BTN_BORDER_G,  BTN_BORDER_B,  1)        then btn_cl = btn_cl + 1 end

      if r.ImGui_Button(ctx, 'All',   BTN_W_ALL, BTN_H) then set_all(true)  end
      safe_same_line(ctx, 0, BTN_GAP)
      if r.ImGui_Button(ctx, 'Clear', BTN_W_CLEAR, BTN_H) then set_all(false) end

      pop_font(ctx, btn_font_pushed)

      if btn_cl > 0 then safe_pop_color(ctx, btn_cl) end
      if btn_sv > 0 then safe_pop_style_var(ctx, btn_sv) end

      -- SEARCH FIELD — right-aligned to content area.
      -- Layout (window-relative X): [PAD] [All BTN_W_ALL] [BTN_GAP] [Clear BTN_W_CLEAR] ... [Search actual_search_w] [PAD]
      -- SetCursorPosX is window-relative (X=0 = window edge, X=PAD = content start).
      local content_right = PAD + content_w  -- right edge of content area in window coords
      local actual_search_w = math.min(SEARCH_W, math.max(80, content_w - (BTN_W_ALL + BTN_W_CLEAR + 2 * BTN_GAP)))
      local search_x = content_right - actual_search_w

      -- Guard: don't overlap with Clear button.
      -- Clear button right edge = PAD + BTN_W_ALL + BTN_GAP + BTN_W_CLEAR. Plus min gap = BTN_GAP.
      local search_min_x = PAD + BTN_W_ALL + BTN_W_CLEAR + 2 * BTN_GAP
      if search_x < search_min_x then search_x = search_min_x end

      safe_same_line(ctx)
      pcall(r.ImGui_SetCursorPosX, ctx, search_x)

      local search_font_pushed = push_font(ctx, font_body)

      local search_cl = 0
      local search_sv = 0
      -- Text + cursor color: try all known cursor color enums across ReaImGui versions
      if safe_push_color(ctx, Col_Text(),           UI_TEXT_R,       UI_TEXT_G,       UI_TEXT_B,       UI_TEXT_A) then search_cl = search_cl + 1 end
      for _, enum_name in ipairs({'ImGui_Col_InputTextCursor', 'ImGui_Col_TextCursor'}) do
        local col_val = enum_or(enum_name, nil)
        if col_val then
          if safe_push_color(ctx, col_val, UI_TEXT_R, UI_TEXT_G, UI_TEXT_B, UI_TEXT_A) then search_cl = search_cl + 1 end
        end
      end
      if safe_push_color(ctx, Col_FrameBg(),        BG_R + 0.01,     BG_G + 0.01,     BG_B + 0.01,     1) then search_cl = search_cl + 1 end
      if safe_push_color(ctx, Col_FrameBgHovered(),  SEL_R,           SEL_G,           SEL_B,           1) then search_cl = search_cl + 1 end
      if safe_push_color(ctx, Col_Border(),          SEARCH_BORDER_R, SEARCH_BORDER_G, SEARCH_BORDER_B, 1) then search_cl = search_cl + 1 end
      if safe_push_style_var2(ctx, StyleVar_FramePadding(), 8, 5)                                           then search_sv = search_sv + 1 end
      if safe_push_style_var1(ctx, StyleVar_FrameRounding(), CORNER_RADIUS)                                 then search_sv = search_sv + 1 end  -- ◄ NEW v0.5.19
      if safe_push_style_var1(ctx, StyleVar_FrameBorderSize(), 1)                                           then search_sv = search_sv + 1 end

      safe_set_next_item_width(ctx, actual_search_w)
      local changed, new_buf = safe_input_text_with_hint(ctx, '##search', 'Search markers/regions…', search_buf)
      if changed and new_buf ~= nil then
        search_buf   = tostring(new_buf)
        search_query = search_buf
        rebuild_display(true)
      end

      if search_sv > 0 then safe_pop_style_var(ctx, search_sv) end
      if search_cl > 0 then safe_pop_color(ctx, search_cl) end
      pop_font(ctx, search_font_pushed)
    end

    safe_dummy(ctx, 0, 4)

    -- =========================================================
    -- ТАБЛИЦА РЕГИОНОВ/МАРКЕРОВ — ImGui_BeginTable
    -- =========================================================
    do
      local _, list_h = get_content_avail(ctx)
      if list_h < 40 then list_h = 40 end

      local table_flags = TableFlags_BordersInnerH()
                        + TableFlags_BordersInnerV()
                        + TableFlags_BordersOuterH()
                        + TableFlags_BordersOuterV()
                        + TableFlags_ScrollY()
                        + TableFlags_NoHostExtendX()

      -- Стили таблицы
      local tbl_cl = 0
      local tbl_sv = 0
      -- Note v0.5.19: ChildRounding не работает для BeginTable со ScrollY —
      -- ImGui применяет rounding только к явным BeginChild, а не к внутреннему child окну таблицы.
      if safe_push_color(ctx, Col_TableBorderStrong(), BORDER_R, BORDER_G, BORDER_B, 1) then tbl_cl = tbl_cl + 1 end
      if safe_push_color(ctx, Col_TableBorderLight(),  BORDER_R, BORDER_G, BORDER_B, 1) then tbl_cl = tbl_cl + 1 end
      if safe_push_color(ctx, Col_TableRowBg(),        BG_R, BG_G, BG_B, 1)             then tbl_cl = tbl_cl + 1 end
      -- Header colors — невидимые (не показываем подсветку через Selectable)
      if safe_push_color(ctx, Col_Header(),            BG_R, BG_G, BG_B, 0)             then tbl_cl = tbl_cl + 1 end
      if safe_push_color(ctx, Col_HeaderHovered(),     BG_R, BG_G, BG_B, 0)             then tbl_cl = tbl_cl + 1 end
      if safe_push_color(ctx, Col_HeaderActive(),      BG_R, BG_G, BG_B, 0)             then tbl_cl = tbl_cl + 1 end
      if safe_push_color(ctx, Col_ScrollbarBg(),       BG_R, BG_G, BG_B, 0)             then tbl_cl = tbl_cl + 1 end
      if safe_push_color(ctx, Col_ScrollbarGrab(),     0, 0, 0, 0.38)                   then tbl_cl = tbl_cl + 1 end
      if safe_push_color(ctx, Col_ScrollbarGrabHovered(), 0, 0, 0, 0.50)                then tbl_cl = tbl_cl + 1 end
      if safe_push_color(ctx, Col_ScrollbarGrabActive(),  0, 0, 0, 0.65)                then tbl_cl = tbl_cl + 1 end
      if safe_push_style_var2(ctx, StyleVar_CellPadding(), CELL_PAD_X, 4)                  then tbl_sv = tbl_sv + 1 end

      local col_fixed   = TableColumnFlags_WidthFixed() + TableColumnFlags_NoResize()
      local col_stretch = TableColumnFlags_WidthStretch()

      local table_ok = false
      if r.ImGui_BeginTable then
        local ok, ret = pcall(r.ImGui_BeginTable, ctx, '##items', 4, table_flags, 0, list_h)
        if ok and ret then table_ok = true end
      end

      if table_ok then
        pcall(r.ImGui_TableSetupColumn, ctx, '##chk',  col_fixed,   COL_CHECKBOX_W)
        pcall(r.ImGui_TableSetupColumn, ctx, '##id',   col_fixed,   COL_ID_W)
        pcall(r.ImGui_TableSetupColumn, ctx, '##name', col_stretch,  0)
        pcall(r.ImGui_TableSetupColumn, ctx, '##time', col_fixed,   COL_TIMECODE_W)

        -- DrawList для чекбоксов и row highlight
        local dl = nil
        if r.ImGui_GetWindowDrawList then
          local ok_dl, got = pcall(r.ImGui_GetWindowDrawList, ctx)
          if ok_dl then dl = got end
        end

        local u32_sq_reg_b = rgbaf_u32(SQ_REGION_R, SQ_REGION_G, SQ_REGION_B, SQ_BORDER_A)
        local u32_sq_reg_f = rgbaf_u32(SQ_REGION_R, SQ_REGION_G, SQ_REGION_B, SQ_FILL_A)
        local u32_sq_mrk_b = rgbaf_u32(SQ_MARKER_R, SQ_MARKER_G, SQ_MARKER_B, SQ_BORDER_A)
        local u32_sq_mrk_f = rgbaf_u32(SQ_MARKER_R, SQ_MARKER_G, SQ_MARKER_B, SQ_FILL_A)
        local u32_text     = rgbaf_u32(UI_TEXT_R, UI_TEXT_G, UI_TEXT_B, UI_TEXT_A)
        local u32_sel_bg   = rgbaf_u32(SEL_R, SEL_G, SEL_B, 1)

        local shift     = is_shift_held(ctx)
        local frame_now = r.time_precise()

        local sel_flags = SelectableFlags_SpanAllColumns() + SelectableFlags_AllowOverlap()

        -- Measure single-line text height in font_list for checkbox vertical alignment.
        -- Checkbox aligns with the first text line, not with the full Selectable height.
        local chk_text_line_h = 0
        do
          local mf = push_font(ctx, font_list)
          chk_text_line_h = select(2, calc_text_size(ctx, "Ay"))
          pop_font(ctx, mf)
        end

        local extended_hit_claimed = false  -- prevents double-claiming across overlapping rows

        for i = 1, #display do
          local it         = display[i]
          local is_checked = (checked[it.key] == true)

          pcall(r.ImGui_TableNextRow, ctx)

          -- ============ COLUMN 0: Checkbox + Selectable ============
          pcall(r.ImGui_TableNextColumn, ctx)

          -- Per-cell highlight (fixes: covers full cell height, doesn't cross borders)
          if is_checked and r.ImGui_TableSetBgColor then
            pcall(r.ImGui_TableSetBgColor, ctx, TableBgTarget_CellBg(), u32_sel_bg)
          end

          -- Save column 0 cursor position for deferred checkbox drawing
          local col0_sx, col0_sy = 0, 0
          local row_max_y = 0  -- tracks the lowest rendered item Y for extended hit area
          do
            local ok_p, sx, sy = pcall(r.ImGui_GetCursorScreenPos, ctx)
            if ok_p and sx then col0_sx, col0_sy = sx, sy; row_max_y = sy end
          end

          -- Selectable for click handling (invisible, spans all columns)
          local list_pushed = push_font(ctx, font_list)
          local row_clicked = false
          do
            local ok_sel, ret_sel = pcall(r.ImGui_Selectable, ctx, '##row' .. i, false, sel_flags)
            if ok_sel then row_clicked = (ret_sel == true) end
          end

          -- Guard: reject Selectable click if mouse is above this row's content start.
          -- ImGui may assign border-zone clicks to the row below; col0_sy is content top.
          if row_clicked and r.ImGui_GetMousePos then
            local ok_my, _, click_y = pcall(r.ImGui_GetMousePos, ctx)
            if ok_my and click_y and click_y < col0_sy then
              row_clicked = false
            end
          end

          -- Double-click detection
          local double_clicked = false
          if r.ImGui_IsItemHovered and r.ImGui_IsMouseDoubleClicked then
            local ok_hv, hov = pcall(r.ImGui_IsItemHovered, ctx)
            local ok_dc, dc  = pcall(r.ImGui_IsMouseDoubleClicked, ctx, 0)
            if ok_hv and ok_dc and hov == true and dc == true then
              double_clicked = true
            end
          end

          -- Guard: reject double-click if mouse is above this row's content start.
          if double_clicked and r.ImGui_GetMousePos then
            local ok_my, _, click_y = pcall(r.ImGui_GetMousePos, ctx)
            if ok_my and click_y and click_y < col0_sy then
              double_clicked = false
            end
          end

          -- Get Selectable line height for checkbox vertical centering
          -- Selectable line height (kept for potential future use in click area expansion)
          local sel_line_h = 0
          do
            local ok_min, _, ry1 = pcall(r.ImGui_GetItemRectMin, ctx)
            local ok_max, _, ry2 = pcall(r.ImGui_GetItemRectMax, ctx)
            if ok_min and ok_max and ry1 and ry2 then
              sel_line_h = ry2 - ry1
              if ry2 > row_max_y then row_max_y = ry2 end
            end
          end

          pop_font(ctx, list_pushed)

          -- ============ COLUMN 1: ID ============
          pcall(r.ImGui_TableNextColumn, ctx)
          if is_checked and r.ImGui_TableSetBgColor then
            pcall(r.ImGui_TableSetBgColor, ctx, TableBgTarget_CellBg(), u32_sel_bg)
          end
          local id_pushed = push_font(ctx, font_list)
          local label = (it.isrgn and 'R' or 'M') .. tostring(it.shown_id)
          do
            local label_w = select(1, calc_text_size(ctx, label))
            local avail   = select(1, get_content_avail(ctx))
            local offset  = avail - label_w
            if offset > 0 and r.ImGui_GetCursorPosX then
              local ok_gx, cur_x = pcall(r.ImGui_GetCursorPosX, ctx)
              if ok_gx and cur_x then
                pcall(r.ImGui_SetCursorPosX, ctx, cur_x + offset)
              end
            end
          end
          r.ImGui_Text(ctx, label)
          -- Click detection on ID cell
          if not row_clicked and r.ImGui_IsItemClicked then
            local ok_ic, ic = pcall(r.ImGui_IsItemClicked, ctx, 0)
            if ok_ic and ic then row_clicked = true end
          end
          if not double_clicked and r.ImGui_IsItemHovered and r.ImGui_IsMouseDoubleClicked then
            local ok_hv, hv = pcall(r.ImGui_IsItemHovered, ctx)
            local ok_dc, dc = pcall(r.ImGui_IsMouseDoubleClicked, ctx, 0)
            if ok_hv and hv and ok_dc and dc then double_clicked = true end
          end
          pop_font(ctx, id_pushed)

          -- ============ COLUMN 2: Name ============
          pcall(r.ImGui_TableNextColumn, ctx)
          if is_checked and r.ImGui_TableSetBgColor then
            pcall(r.ImGui_TableSetBgColor, ctx, TableBgTarget_CellBg(), u32_sel_bg)
          end
          local name_pushed = push_font(ctx, font_list)
          local name_text = trim(it.name)
          if name_text ~= '' then
            if r.ImGui_TextWrapped then
              r.ImGui_TextWrapped(ctx, name_text)
            else
              r.ImGui_Text(ctx, name_text)
            end
            -- Click detection on Name cell (covers all wrapped text lines)
            if not row_clicked and r.ImGui_IsItemClicked then
              local ok_ic, ic = pcall(r.ImGui_IsItemClicked, ctx, 0)
              if ok_ic and ic then row_clicked = true end
            end
            if not double_clicked and r.ImGui_IsItemHovered and r.ImGui_IsMouseDoubleClicked then
              local ok_hv, hv = pcall(r.ImGui_IsItemHovered, ctx)
              local ok_dc, dc = pcall(r.ImGui_IsMouseDoubleClicked, ctx, 0)
              if ok_hv and hv and ok_dc and dc then double_clicked = true end
            end
            -- Update row_max_y — wrapped text is the main source of tall rows
            if r.ImGui_GetItemRectMax then
              local ok_rm, _, ry = pcall(r.ImGui_GetItemRectMax, ctx)
              if ok_rm and ry and ry > row_max_y then row_max_y = ry end
            end
          end
          pop_font(ctx, name_pushed)

          -- ============ COLUMN 3: Timecode ============
          pcall(r.ImGui_TableNextColumn, ctx)
          if is_checked and r.ImGui_TableSetBgColor then
            pcall(r.ImGui_TableSetBgColor, ctx, TableBgTarget_CellBg(), u32_sel_bg)
          end
          if it.isrgn and (it.len or 0) > 0 then
            local tc_pushed = push_font(ctx, font_list_tc)
            local dur_str = format_hhmmss(it.len)
            do
              local tc_w  = select(1, calc_text_size(ctx, dur_str))
              local avail = select(1, get_content_avail(ctx))
              local offset = avail - tc_w
              if offset > 0 and r.ImGui_GetCursorPosX then
                local ok_gx, cur_x = pcall(r.ImGui_GetCursorPosX, ctx)
                if ok_gx and cur_x then
                  pcall(r.ImGui_SetCursorPosX, ctx, cur_x + offset)
                end
              end
            end
            if safe_push_color(ctx, Col_Text(), UI_TEXT_R, UI_TEXT_G, UI_TEXT_B, UI_TEXT_DIM_A) then
              r.ImGui_Text(ctx, dur_str)
              safe_pop_color(ctx, 1)
            else
              r.ImGui_Text(ctx, dur_str)
            end
            -- Click detection on Timecode cell
            if not row_clicked and r.ImGui_IsItemClicked then
              local ok_ic, ic = pcall(r.ImGui_IsItemClicked, ctx, 0)
              if ok_ic and ic then row_clicked = true end
            end
            if not double_clicked and r.ImGui_IsItemHovered and r.ImGui_IsMouseDoubleClicked then
              local ok_hv, hv = pcall(r.ImGui_IsItemHovered, ctx)
              local ok_dc, dc = pcall(r.ImGui_IsMouseDoubleClicked, ctx, 0)
              if ok_hv and hv and ok_dc and dc then double_clicked = true end
            end
            pop_font(ctx, tc_pushed)
          end

          -- ============ DEFERRED: Checkbox drawing ============
          -- Draw checkbox centered in FULL cell (content + padding on both sides).
          -- col0_sx is at content start (after left CellPadding), so we shift left
          -- by CELL_PAD_X to get the cell's left edge, then center in the full width.
          if dl then
            local sq = CHECKBOX_SIZE
            local cell_full_w = COL_CHECKBOX_W + 2 * CELL_PAD_X
            local sx = (col0_sx - CELL_PAD_X) + math.floor((cell_full_w - sq) / 2)
            local sy = col0_sy + math.floor(math.max(chk_text_line_h - sq, 0) / 2)
            -- Custom colors take priority over the default region/marker
            -- palette. They are decoded when the list refreshes, so manual
            -- REAPER color edits also appear while this window is open.
            local sq_border = it.isrgn and u32_sq_reg_b or u32_sq_mrk_b
            local sq_fill   = it.isrgn and u32_sq_reg_f or u32_sq_mrk_f
            local tick_col  = u32_text
            if it.custom_rgb then
              local cr, cg, cb = it.custom_rgb[1], it.custom_rgb[2], it.custom_rgb[3]
              local luminance = 0.2126 * cr + 0.7152 * cg + 0.0722 * cb
              -- Darken the outline of very light colors (including white).
              local border_scale = (luminance > 0.75) and 0.55 or 1.0
              sq_border = rgbaf_u32(cr * border_scale, cg * border_scale, cb * border_scale, 1.0)
              sq_fill   = rgbaf_u32(cr, cg, cb, SQ_CUSTOM_FILL_A)
              tick_col  = (luminance < 0.54) and rgbaf_u32(1, 1, 1, 1) or u32_text
            end
            pcall(r.ImGui_DrawList_AddRect,       dl, sx, sy, sx + sq, sy + sq, sq_border)
            pcall(r.ImGui_DrawList_AddRectFilled, dl, sx + 1, sy + 1, sx + sq - 1, sy + sq - 1, sq_fill)
            if is_checked then
              draw_tick(dl, sx, sy, sq, tick_col)
            end
          end

          -- ============ EXTENDED HIT AREA ============
          -- Catch clicks in empty row space (below wrapped text, empty cells).
          -- Uses manual mouse position check instead of IsMouseHoveringRect, because
          -- in a scrollable table the clip rect may be limited to the current column.
          -- Bottom padding = CellPadding.y (4px) — do NOT extend further to avoid
          -- overlapping into the next row's territory and triggering the wrong row.
          -- extended_hit_claimed prevents the same click from firing on adjacent rows.
          if (not row_clicked or not double_clicked)
             and not extended_hit_claimed
             and r.ImGui_GetMousePos then
            local row_bottom = row_max_y + 4
            local ok_wh, win_hovered = pcall(r.ImGui_IsWindowHovered, ctx)
            if ok_wh and win_hovered then
              local ok_mp, mx, my = pcall(r.ImGui_GetMousePos, ctx)
              if ok_mp and mx and my and my >= col0_sy and my < row_bottom then
                if not row_clicked and r.ImGui_IsMouseClicked then
                  local ok_mc, mc = pcall(r.ImGui_IsMouseClicked, ctx, 0)
                  if ok_mc and mc then
                    row_clicked = true
                    extended_hit_claimed = true
                  end
                end
                if not double_clicked and r.ImGui_IsMouseDoubleClicked then
                  local ok_dc, dc = pcall(r.ImGui_IsMouseDoubleClicked, ctx, 0)
                  if ok_dc and dc then
                    double_clicked = true
                    extended_hit_claimed = true
                  end
                end
              end
            end
          end

          -- ============ INTERACTION ============
          if double_clicked and pending_row_click
             and pending_row_click.key == it.key
             and (frame_now - pending_row_click.first_click_time) <= ROW_DOUBLECLICK_WINDOW_SEC then
            pending_row_click = nil
            suppress_next_release_click_key = it.key
            pcall(r.SetEditCurPos, it.pos, true, false)

          elseif row_clicked then
            if suppress_next_release_click_key == it.key then
              suppress_next_release_click_key = nil
            else
              local desired = not (checked[it.key] == true)

              if pending_row_click and pending_row_click.key ~= it.key then
                commit_pending()
              end

              if pending_row_click
                 and pending_row_click.key == it.key
                 and (frame_now - pending_row_click.first_click_time) >= ROW_SINGLE_CLICK_WAIT_SEC then
                commit_pending()
                desired = not (checked[it.key] == true)
              end

              pending_row_click = {
                key = it.key,
                row_index = i,
                desired = desired,
                shift = shift,
                anchor_key = last_clicked_disp_key,
                anchor_index = last_clicked_disp_index,
                first_click_time = frame_now,
              }
            end
          end
        end -- for each display item

        -- Post-loop: commit expired pending
        if pending_row_click and (r.time_precise() - pending_row_click.first_click_time) >= ROW_SINGLE_CLICK_WAIT_SEC then
          commit_pending()
        end

        if suppress_next_release_click_key ~= nil and r.ImGui_IsMouseDown then
          local ok_down, is_down = pcall(r.ImGui_IsMouseDown, ctx, 0)
          if ok_down and is_down == false then
            suppress_next_release_click_key = nil
          end
        end

        pcall(r.ImGui_EndTable, ctx)
      end -- if table_ok

      if tbl_sv > 0 then safe_pop_style_var(ctx, tbl_sv) end
      if tbl_cl > 0 then safe_pop_color(ctx, tbl_cl) end
    end

    if text_col_pushed > 0 then safe_pop_color(ctx, text_col_pushed) end
  end

  r.ImGui_End(ctx)

  if window_open then
    r.defer(frame)
  else
    if r.ImGui_DestroyContext then pcall(r.ImGui_DestroyContext, ctx) end
    ctx = nil
  end
end

-- =============================================================
-- INIT — создание шрифтов и контекста
-- =============================================================

-- ReaImGui is an extension; give a readable installation hint if unavailable.
if type(r.ImGui_CreateContext) ~= 'function' then
  r.ShowMessageBox(
    'Region Time Counter requires the ReaImGui extension.\nInstall ReaImGui via ReaPack and restart REAPER.',
    'Region Time Counter — ReaImGui required', 0)
  return
end

ctx = r.ImGui_CreateContext(WINDOW_TITLE)

-- Probe font API contract and create font objects.
-- Try NEW contract first (CreateFont without size), then OLD (with size).
-- Attach tries ImGui_Attach first, then ImGui_AttachFont for older builds.
local function safe_attach(ctx_arg, font_obj)
  if r.ImGui_Attach then
    local ok = pcall(r.ImGui_Attach, ctx_arg, font_obj)
    if ok then return true end
  end
  if r.ImGui_AttachFont then
    local ok = pcall(r.ImGui_AttachFont, ctx_arg, font_obj)
    if ok then return true end
  end
  return false
end

if r.ImGui_CreateFont then
  -- Probe: try CreateFont('sans-serif') without size (NEW contract)
  local probe_ok, probe_font = pcall(r.ImGui_CreateFont, 'sans-serif')
  if probe_ok and probe_font then
    -- NEW contract: CreateFont returns font without size, size goes to PushFont
    font_contract = 'new'
    safe_attach(ctx, probe_font)
    local function create_new(px)
      local ok, f = pcall(r.ImGui_CreateFont, 'sans-serif')
      if ok and f then
        safe_attach(ctx, f)
        font_role_sizes[f] = px
        return f
      end
      return nil
    end
    font_body        = create_new(FONT_SIZE_BODY)
    font_stats_label = create_new(FONT_SIZE_STATS_LABEL)
    font_stats_value = create_new(FONT_SIZE_STATS_VALUE)
    font_list        = create_new(FONT_SIZE_LIST)
    font_list_tc     = create_new(FONT_SIZE_LIST_TC)
  else
    -- Try OLD contract: CreateFont('sans-serif', size)
    local ok2, f2 = pcall(r.ImGui_CreateFont, 'sans-serif', FONT_SIZE_BODY)
    if ok2 and f2 then
      font_contract = 'old'
      local function create_old(px)
        local ok, f = pcall(r.ImGui_CreateFont, 'sans-serif', px)
        if ok and f then
          safe_attach(ctx, f)
          return f
        end
        return nil
      end
      font_body        = create_old(FONT_SIZE_BODY)
      font_stats_label = create_old(FONT_SIZE_STATS_LABEL)
      font_stats_value = create_old(FONT_SIZE_STATS_VALUE)
      font_list        = create_old(FONT_SIZE_LIST)
      font_list_tc     = create_old(FONT_SIZE_LIST_TC)
    end
    -- If neither works, font_contract stays nil and push_font() is a no-op.
  end
end

sync_active_project()
search_buf = search_query
frame()
