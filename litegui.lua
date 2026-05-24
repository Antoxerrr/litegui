-- ============================================================
--  litegui.lua — LiteGUI for OpenComputers
--  Декларативная GUI-библиотека с half-block пиксельной графикой.
--
--  Главный приём: символ "▀" с разными fg/bg = 2 "пикселя" на ячейку.
--  Это даёт эффективное разрешение 80×50 на тиере 2 и позволяет
--  рисовать настоящие круги, дуги, линии и градиенты, а не их
--  символьные карикатуры.
-- ============================================================
--
--  БЫСТРЫЙ СТАРТ
--    local GUI = require("litegui")
--    local el  = GUI.el
--    local s = el.panel { x=1, y=1, w=80, h=25, bg=0x1A1A2E, border=0x7C6FCD,
--                         title="hello", shadow=true }
--    s:add(el.text { x=2, y=3, text="привет", fg=0xFFFFFF })
--    GUI.run(s)
--
--  КОМПОНЕНТЫ
--    rect       — заливка + опц. рамка (border, borderStyle)
--    panel      — rect с заголовком, тенью, скруглением
--    text       — строка
--    button     — кликабельная кнопка
--    progress   — горизонтальный bar (sub-cell precision)
--    gradient   — линейный градиент (direction = "h"|"v")
--    line       — линия в char-координатах
--    circle     — круг в pixel-координатах (fill=true для заливки)
--    arc        — дуга (a0, a1 в радианах, thickness)
--    gauge      — круговой индикатор (value 0..1)
--    sparkline  — мини-график из массива values
--    barchart   — столбчатая диаграмма
--    slider     — визуальный слайдер (value 0..1)
--    badge      — маленький цветной лейбл
--    pixelGrid  — массив пикселей cells[r][c] = color
--
--  Координаты детей — относительно родителя. :add() возвращает родителя.
-- ============================================================

local component = component or require("component")
local event     = event     or require("event")
local unicode   = unicode   or require("unicode")
local gpu       = component.gpu

-- ============================================================
--  UTILS / COLOR MATH
-- ============================================================

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function unpackColor(c)
  local r = math.floor(c / 65536) % 256
  local g = math.floor(c / 256) % 256
  local b = c % 256
  return r, g, b
end

local function packColor(r, g, b)
  return math.floor(r) * 65536 + math.floor(g) * 256 + math.floor(b)
end

local function lerp(a, b, t) return a + (b - a) * t end

local function lerpColor(c1, c2, t)
  local r1, g1, b1 = unpackColor(c1)
  local r2, g2, b2 = unpackColor(c2)
  return packColor(lerp(r1, r2, t), lerp(g1, g2, t), lerp(b1, b2, t))
end

local function darken(c, factor)
  local r, g, b = unpackColor(c)
  return packColor(r * factor, g * factor, b * factor)
end

-- Bresenham (целочисленный список точек)
local function linePoints(x0, y0, x1, y1)
  x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)
  local pts = {}
  local dx = math.abs(x1 - x0)
  local dy = math.abs(y1 - y0)
  local sx = x0 < x1 and 1 or -1
  local sy = y0 < y1 and 1 or -1
  local err = dx - dy
  while true do
    pts[#pts+1] = {x0, y0}
    if x0 == x1 and y0 == y1 then break end
    local e2 = 2 * err
    if e2 > -dy then err = err - dy; x0 = x0 + sx end
    if e2 <  dx then err = err + dx; y0 = y0 + sy end
  end
  return pts
end

-- ============================================================
--  BUFFER  (с half-block пиксельным слоем)
-- ============================================================
--  Хранение: три плоских массива (ch, fg, bg), индексированные
--  i = (y-1)*w + x. Это в ~6× компактнее, чем таблица-на-ячейку,
--  потому что Lua кладёт целочисленные индексы в array-part.
--
--  Пиксели: символ "▀" = fg верхний пиксель, bg нижний.
--  pixel (px, py)  →  cellX = px, cellY = ceil(py/2), top = (py%2==1)

local Buffer = {}
Buffer.__index = Buffer

local function fillBuf(buf, ch, fg, bg, n)
  for i = 1, n do
    buf.ch[i] = ch
    buf.fg[i] = fg
    buf.bg[i] = bg
  end
end

function Buffer.new()
  local w, h = gpu.getResolution()
  local n = w * h
  local self = setmetatable({
    w = w, h = h, n = n,
    pw = w, ph = h * 2,
    cur  = { ch = {}, fg = {}, bg = {} },
    next = { ch = {}, fg = {}, bg = {} },
  }, Buffer)
  fillBuf(self.cur,  " ", 0xFFFFFF, 0x000000, n)
  fillBuf(self.next, " ", 0xFFFFFF, 0x000000, n)
  return self
end

function Buffer:set(x, y, ch, fg, bg)
  x = x >= 0 and math.floor(x) or math.ceil(x)
  y = y >= 0 and math.floor(y) or math.ceil(y)
  if x < 1 or y < 1 or x > self.w or y > self.h then return end
  local i = (y - 1) * self.w + x
  local nx = self.next
  if ch then nx.ch[i] = ch end
  if fg then nx.fg[i] = fg end
  if bg then nx.bg[i] = bg end
end

function Buffer:fill(x, y, w, h, ch, fg, bg)
  local bw, bh = self.w, self.h
  local nx_ch, nx_fg, nx_bg = self.next.ch, self.next.fg, self.next.bg
  local x0 = math.max(1, math.floor(x))
  local y0 = math.max(1, math.floor(y))
  local x1 = math.min(bw, math.floor(x) + w - 1)
  local y1 = math.min(bh, math.floor(y) + h - 1)
  for yy = y0, y1 do
    local base = (yy - 1) * bw
    for xx = x0, x1 do
      local i = base + xx
      if ch then nx_ch[i] = ch end
      if fg then nx_fg[i] = fg end
      if bg then nx_bg[i] = bg end
    end
  end
end

-- Из ячейки достаём (top, bottom) — цвета двух «пикселей».
local function decodeCellAt(nx, i)
  local ch, fg, bg = nx.ch[i], nx.fg[i], nx.bg[i]
  if ch == "▀" then return fg, bg
  elseif ch == "▄" then return bg, fg
  else return bg, bg end
end

function Buffer:setPixel(px, py, color)
  px, py = math.floor(px), math.floor(py)
  if px < 1 or py < 1 or px > self.pw or py > self.ph then return end
  local cellY = math.ceil(py / 2)
  local isTop = (py % 2 == 1)
  local i = (cellY - 1) * self.w + px
  local nx = self.next
  local top, bot = decodeCellAt(nx, i)
  if isTop then top = color else bot = color end
  if top == bot then
    nx.ch[i] = " "; nx.fg[i] = 0xFFFFFF; nx.bg[i] = top
  else
    nx.ch[i] = "▀"; nx.fg[i] = top; nx.bg[i] = bot
  end
end

function Buffer:clear(bg)
  bg = bg or 0x000000
  fillBuf(self.next, " ", 0xFFFFFF, bg, self.n)
end

-- На GPU выливаем только изменившиеся ячейки, склеивая соседние
-- ячейки с одинаковыми fg/bg в один gpu.set(x,y,"строка").
function Buffer:flush()
  local w, h = self.w, self.h
  local cur, nx = self.cur, self.next
  local cur_ch, cur_fg, cur_bg = cur.ch, cur.fg, cur.bg
  local nx_ch,  nx_fg,  nx_bg  = nx.ch,  nx.fg,  nx.bg
  local lastFg, lastBg

  for y = 1, h do
    local base = (y - 1) * w
    local x = 1
    while x <= w do
      local i = base + x
      local nch, nfg, nbg = nx_ch[i], nx_fg[i], nx_bg[i]
      if nch ~= cur_ch[i] or nfg ~= cur_fg[i] or nbg ~= cur_bg[i] then
        -- начало run-а: копим соседей с теми же fg/bg
        local runStart = x
        local parts = { nch }
        cur_ch[i], cur_fg[i], cur_bg[i] = nch, nfg, nbg
        local xx = x + 1
        while xx <= w do
          local j = base + xx
          local mch, mfg, mbg = nx_ch[j], nx_fg[j], nx_bg[j]
          if mfg ~= nfg or mbg ~= nbg then break end
          if mch == cur_ch[j] and mfg == cur_fg[j] and mbg == cur_bg[j] then
            -- ячейка не изменилась → run обрывать дешевле, чем перерисовывать впустую
            break
          end
          parts[#parts + 1] = mch
          cur_ch[j], cur_fg[j], cur_bg[j] = mch, mfg, mbg
          xx = xx + 1
        end
        if nfg ~= lastFg then gpu.setForeground(nfg); lastFg = nfg end
        if nbg ~= lastBg then gpu.setBackground(nbg); lastBg = nbg end
        gpu.set(runStart, y, table.concat(parts))
        x = xx
      else
        x = x + 1
      end
    end
  end
end

-- ============================================================
--  PRIMITIVES
-- ============================================================

local P = {}

function P.rect(buf, x, y, w, h, bg)
  buf:fill(x, y, w, h, " ", bg, bg)
end

local BORDERS = {
  single  = {h="─", v="│", tl="┌", tr="┐", bl="└", br="┘"},
  double  = {h="═", v="║", tl="╔", tr="╗", bl="╚", br="╝"},
  thick   = {h="━", v="┃", tl="┏", tr="┓", bl="┗", br="┛"},
  rounded = {h="─", v="│", tl="╭", tr="╮", bl="╰", br="╯"},
}

function P.border(buf, x, y, w, h, color, bg, style)
  local s = BORDERS[style or "single"] or BORDERS.single
  for dx = 1, w-2 do
    buf:set(x+dx, y,     s.h, color, bg)
    buf:set(x+dx, y+h-1, s.h, color, bg)
  end
  for dy = 1, h-2 do
    buf:set(x,     y+dy, s.v, color, bg)
    buf:set(x+w-1, y+dy, s.v, color, bg)
  end
  buf:set(x,       y,       s.tl, color, bg)
  buf:set(x+w-1,   y,       s.tr, color, bg)
  buf:set(x,       y+h-1,   s.bl, color, bg)
  buf:set(x+w-1,   y+h-1,   s.br, color, bg)
end

-- Тень под прямоугольником: тёмные ячейки со смещением (1,1)
function P.shadow(buf, x, y, w, h, color)
  color = color or 0x000000
  for dy = 1, h - 1 do
    buf:set(x + w, y + dy, " ", 0xFFFFFF, color)
  end
  for dx = 1, w do
    buf:set(x + dx, y + h, " ", 0xFFFFFF, color)
  end
end

function P.text(buf, x, y, str, fg, bg)
  local col = x
  for i = 1, unicode.len(str) do
    buf:set(col, y, unicode.sub(str, i, i), fg, bg)
    col = col + 1
  end
end

-- Горизонтальный градиент: интерполяция по колонкам
function P.gradientH(buf, x, y, w, h, c1, c2)
  for dx = 0, w-1 do
    local t = (w > 1) and (dx / (w - 1)) or 0
    local color = lerpColor(c1, c2, t)
    for dy = 0, h-1 do
      buf:set(x+dx, y+dy, " ", 0xFFFFFF, color)
    end
  end
end

-- Вертикальный градиент: интерполяция по пиксельным строкам (через ▀)
function P.gradientV(buf, x, y, w, h, c1, c2)
  local rows = h * 2
  for r = 0, rows - 1 do
    local t = (rows > 1) and (r / (rows - 1)) or 0
    local color = lerpColor(c1, c2, t)
    for dx = 0, w-1 do
      buf:setPixel(x + dx, (y - 1) * 2 + 1 + r, color)
    end
  end
end

function P.line(buf, x0, y0, x1, y1, color, bg, ch)
  ch = ch or "█"
  for _, p in ipairs(linePoints(x0, y0, x1, y1)) do
    buf:set(p[1], p[2], ch, color, bg)
  end
end

function P.pixelLine(buf, x0, y0, x1, y1, color)
  for _, p in ipairs(linePoints(x0, y0, x1, y1)) do
    buf:setPixel(p[1], p[2], color)
  end
end

-- Заливной круг в пиксельных координатах
function P.pixelCircleFill(buf, cx, cy, r, color)
  local r2 = r * r
  for dy = -r, r do
    for dx = -r, r do
      if dx*dx + dy*dy <= r2 then
        buf:setPixel(cx + dx, cy + dy, color)
      end
    end
  end
end

-- Контур круга, толщина в пикселях
function P.pixelCircle(buf, cx, cy, r, color, thickness)
  thickness = thickness or 1
  local rOuter2 = r * r
  local rInner  = math.max(0, r - thickness)
  local rInner2 = rInner * rInner
  for dy = -r, r do
    for dx = -r, r do
      local d2 = dx*dx + dy*dy
      if d2 <= rOuter2 and d2 >= rInner2 then
        buf:setPixel(cx + dx, cy + dy, color)
      end
    end
  end
end

-- Дуга. Параметрический проход от a0 к a1 (рад). Положит. угол — против часовой.
function P.pixelArc(buf, cx, cy, r, a0, a1, color, thickness)
  thickness = thickness or 1
  local sweep = a1 - a0
  local steps = math.max(4, math.floor(math.abs(sweep) * r * 1.5))
  for i = 0, steps do
    local t = i / steps
    local a = a0 + sweep * t
    for dr = 0, thickness - 1 do
      local rr = r - dr
      local px = math.floor(cx + rr * math.cos(a) + 0.5)
      local py = math.floor(cy - rr * math.sin(a) + 0.5)
      buf:setPixel(px, py, color)
    end
  end
end

-- Sub-cell горизонтальный прогресс (8 шагов на ячейку)
local FINE = {"▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"}

function P.progressFine(buf, x, y, w, value, fgFill, bg)
  value = clamp(value, 0, 1)
  bg = bg or 0x000000
  fgFill = fgFill or 0x00FF00
  local total = w * 8
  local filled = value * total
  local fullCells = math.floor(filled / 8)
  local partial = math.floor(filled - fullCells * 8)
  for dx = 0, w-1 do
    if dx < fullCells then
      buf:set(x+dx, y, "█", fgFill, bg)
    elseif dx == fullCells and partial > 0 then
      buf:set(x+dx, y, FINE[partial], fgFill, bg)
    else
      buf:set(x+dx, y, " ", fgFill, bg)
    end
  end
end

-- Sparkline через вертикальные блоки 1/8..8/8
local VBARS = {"▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}

function P.sparkline(buf, x, y, w, values, color, bg)
  bg = bg or 0x000000
  if #values == 0 then return end
  local maxV, minV = -math.huge, math.huge
  for _, v in ipairs(values) do
    if v > maxV then maxV = v end
    if v < minV then minV = v end
  end
  if maxV == minV then maxV = minV + 1 end
  for dx = 0, w-1 do
    local idx = math.floor(dx * #values / w) + 1
    local v = values[idx] or minV
    local t = (v - minV) / (maxV - minV)
    local b = clamp(math.ceil(t * 8), 1, 8)
    buf:set(x+dx, y, VBARS[b], color, bg)
  end
end

-- Bar chart через half-block пиксели (плавная высота столбцов)
function P.barChart(buf, x, y, w, h, values, color, bg)
  bg = bg or 0x000000
  P.rect(buf, x, y, w, h, bg)
  if #values == 0 then return end
  local maxV = 0
  for _, v in ipairs(values) do
    if v > maxV then maxV = v end
  end
  if maxV == 0 then return end
  local pixelH = h * 2
  local n = #values
  local barW = math.max(1, math.floor(w / n))
  local gap = (barW > 1) and 1 or 0
  if barW > 1 then barW = barW - gap end
  for i, v in ipairs(values) do
    local barPxH = math.floor(v / maxV * pixelH)
    local bx = x + (i - 1) * (barW + gap)
    if bx + barW - 1 > x + w - 1 then break end
    -- pixel y координаты: дно столбика = y*2 + pixelH - 1 (если y начинается с 1 →
    -- пикс. строки [(y-1)*2+1 .. (y-1)*2+pixelH])
    local pyBottom = (y - 1) * 2 + pixelH
    for px = 0, barW - 1 do
      for ph = 0, barPxH - 1 do
        buf:setPixel(bx + px, pyBottom - ph, color)
      end
    end
  end
end

-- ============================================================
--  ELEMENT TREE
-- ============================================================

local Element = {}
Element.__index = Element

function Element.new(props)
  local self = setmetatable({}, Element)
  for k, v in pairs(props) do self[k] = v end
  self.x = props.x or 1
  self.y = props.y or 1
  self._children = {}
  if props.children then
    for _, c in ipairs(props.children) do self:add(c) end
  end
  return self
end

function Element:add(child)
  self._children[#self._children + 1] = child
  return self
end

function Element:move(x, y) self.x, self.y = x, y; return self end

-- ============================================================
--  LAYOUT (vbox / hbox / grid)
-- ============================================================
--  Контейнер с полем `layout` управляет позицией/размером детей.
--    layout = "vbox" — стекаются вертикально
--    layout = "hbox" — горизонтально
--    layout = "grid" — сетка cols × rows
--  Поля контейнера:
--    padding — число или {t, r, b, l}
--    gap     — отступ между детьми
--    align   — "start"|"center"|"end"|"stretch" (поперёк main-оси)
--    justify — "start"|"center"|"end"|"space-between" (по main-оси)
--  Поля ребёнка:
--    flex     — N, растягивается пропорционально оставшемуся месту
--    absolute — true, игнорируется layout'ом (использует свои x, y, w, h)
-- ============================================================

local function parsePadding(p)
  if not p then return 0, 0, 0, 0 end
  if type(p) == "number" then return p, p, p, p end
  return p.t or 0, p.r or 0, p.b or 0, p.l or 0
end

local function managedChildren(el)
  local out = {}
  for _, c in ipairs(el._children) do
    if not c.absolute then out[#out+1] = c end
  end
  return out
end

local function layoutAxis(el, axis)
  local pt, pr, pb, pl = parsePadding(el.padding)
  local innerW = (el.w or 0) - pl - pr
  local innerH = (el.h or 0) - pt - pb
  local gap = el.gap or 0

  local mainSize, crossSize, mainStart0, crossStart0
  if axis == "v" then
    mainSize, crossSize = innerH, innerW
    mainStart0, crossStart0 = pt + 1, pl + 1
  else
    mainSize, crossSize = innerW, innerH
    mainStart0, crossStart0 = pl + 1, pt + 1
  end

  local managed = managedChildren(el)
  local n = #managed
  if n == 0 then return end

  -- pass 1: суммируем фиксированный размер и flex
  local fixedMain, totalFlex = 0, 0
  for _, c in ipairs(managed) do
    if c.flex then totalFlex = totalFlex + c.flex
    else
      local cm = (axis == "v") and (c.h or 1) or (c.w or 1)
      fixedMain = fixedMain + cm
    end
  end
  local gapsTotal = gap * math.max(0, n - 1)
  local flexSpace = math.max(0, mainSize - fixedMain - gapsTotal)

  -- justify (только если нет flex — иначе flex съест весь свободный размер)
  local justify = el.justify or "start"
  local mainStart, extraGap = mainStart0, 0
  if totalFlex == 0 then
    local used = fixedMain + gapsTotal
    if justify == "center" then
      mainStart = mainStart0 + math.floor((mainSize - used) / 2)
    elseif justify == "end" then
      mainStart = mainStart0 + (mainSize - used)
    elseif justify == "space-between" and n > 1 then
      extraGap = math.floor((mainSize - used) / (n - 1))
    end
  end

  local align = el.align or "stretch"
  local pos = mainStart
  for _, c in ipairs(managed) do
    -- main-axis размер
    local cMain
    if c.flex then
      cMain = math.floor(flexSpace * c.flex / totalFlex)
    else
      cMain = (axis == "v") and (c.h or 1) or (c.w or 1)
    end

    -- cross-axis размер и позиция
    local cCross = (axis == "v") and c.w or c.h
    local crossPos = crossStart0
    if align == "stretch" or not cCross then
      cCross = crossSize
    elseif align == "center" then
      crossPos = crossStart0 + math.floor((crossSize - cCross) / 2)
    elseif align == "end" then
      crossPos = crossStart0 + (crossSize - cCross)
    end

    if axis == "v" then
      c.x, c.y, c.w, c.h = crossPos, pos, cCross, cMain
    else
      c.x, c.y, c.w, c.h = pos, crossPos, cMain, cCross
    end
    pos = pos + cMain + gap + extraGap
  end
end

local function layoutGrid(el)
  local pt, pr, pb, pl = parsePadding(el.padding)
  local innerW = (el.w or 0) - pl - pr
  local innerH = (el.h or 0) - pt - pb
  local gap = el.gap or 0
  local cols = el.cols or 1
  local managed = managedChildren(el)
  local rows = el.rows or math.ceil(#managed / math.max(1, cols))
  if cols < 1 or rows < 1 then return end

  local cellW = math.floor((innerW - gap * (cols - 1)) / cols)
  local cellH = math.floor((innerH - gap * (rows - 1)) / rows)

  for i, c in ipairs(managed) do
    local row = math.floor((i - 1) / cols)
    local col = (i - 1) % cols
    c.x = pl + 1 + col * (cellW + gap)
    c.y = pt + 1 + row * (cellH + gap)
    c.w = c.w or cellW
    c.h = c.h or cellH
  end
end

local function runLayout(el)
  if el.layout == "vbox" then layoutAxis(el, "v")
  elseif el.layout == "hbox" then layoutAxis(el, "h")
  elseif el.layout == "grid" then layoutGrid(el) end
  for _, c in ipairs(el._children) do
    runLayout(c)
  end
end

-- ============================================================
--  RENDERER
-- ============================================================

local Renderer = {}

function Renderer.draw(buf, el, absX, absY)
  absX = (absX or 0) + el.x - 1
  absY = (absY or 0) + el.y - 1
  local t = el.type
  local x, y = absX, absY

  if t == "rect" then
    P.rect(buf, x, y, el.w or 10, el.h or 1, el.bg or 0x000000)
    if el.border then
      P.border(buf, x, y, el.w, el.h, el.border, el.bg, el.borderStyle)
    end

  elseif t == "panel" then
    local w, h = el.w, el.h
    if el.shadow then
      P.shadow(buf, x, y, w, h, el.shadowColor or 0x000000)
    end
    P.rect(buf, x, y, w, h, el.bg or 0x000000)
    if el.border then
      P.border(buf, x, y, w, h, el.border, el.bg, el.borderStyle or "rounded")
    end
    -- Скругление углов через квадрант-блоки (см. button)
    if el.rounded and el.cornerBg and w >= 2 and h >= 2 then
      local pBg = el.bg or 0x000000
      local cBg = el.cornerBg
      buf:set(x,         y,         "▟", pBg, cBg)
      buf:set(x + w - 1, y,         "▙", pBg, cBg)
      buf:set(x,         y + h - 1, "▜", pBg, cBg)
      buf:set(x + w - 1, y + h - 1, "▛", pBg, cBg)
    end
    if el.title then
      local title = " " .. el.title .. " "
      P.text(buf, x + 2, y, title, el.titleFg or el.border or 0xFFFFFF, el.bg or 0x000000)
    end

  elseif t == "text" then
    P.text(buf, x, y, el.text or "", el.fg or 0xFFFFFF, el.bg)

  elseif t == "line" then
    P.line(buf, x, y,
      x + (el.x1 or 0) - el.x, y + (el.y1 or 0) - el.y,
      el.color or el.fg, el.bg, el.ch)

  elseif t == "circle" then
    -- центр задаётся в char-координатах; переводим в pixel
    local px = x
    local py = (y - 1) * 2 + 1
    if el.fill then
      P.pixelCircleFill(buf, px, py, el.r or 4, el.color or 0xFFFFFF)
    else
      P.pixelCircle(buf, px, py, el.r or 4, el.color or 0xFFFFFF, el.thickness or 1)
    end

  elseif t == "arc" then
    P.pixelArc(buf, x, (y - 1) * 2 + 1, el.r or 5,
      el.a0 or 0, el.a1 or math.pi,
      el.color or 0xFFFFFF, el.thickness or 1)

  elseif t == "gauge" then
    -- Полукруговой индикатор (270° sweep, низ открыт). x,y — левый-верхний угол bbox.
    local r = el.r or 6
    local cx = x + r
    local cyPx = (y - 1) * 2 + r + 1
    local startA = math.rad(225)
    local sweep  = math.rad(270)
    -- фон-дуга
    P.pixelArc(buf, cx, cyPx, r, startA - sweep, startA,
      el.bgColor or 0x222233, el.thickness or 2)
    -- value-дуга (от startA против часовой стрелки уменьшаем угол — идём по верху)
    local v = clamp(el.value or 0, 0, 1)
    local valEnd = startA - sweep * v
    P.pixelArc(buf, cx, cyPx, r, valEnd, startA,
      el.color or 0x4ADE80, el.thickness or 2)
    -- центральный лейбл
    if el.label then
      local lx = cx - math.floor(unicode.len(el.label) / 2)
      local ly = math.ceil(cyPx / 2)
      P.text(buf, lx, ly, el.label, el.fg or 0xFFFFFF, el.bg)
    end
    if el.caption then
      local lx = cx - math.floor(unicode.len(el.caption) / 2)
      P.text(buf, lx, math.ceil(cyPx / 2) + 1, el.caption, el.captionFg or 0x888899, el.bg)
    end

  elseif t == "button" then
    if el.shadow then
      P.shadow(buf, x, y, el.w, el.h, el.shadowColor or 0x000000)
    end
    P.rect(buf, x, y, el.w, el.h, el.bg or 0x333333)
    if el.border then
      P.border(buf, x, y, el.w, el.h, el.border, el.bg, el.borderStyle or "rounded")
    end
    -- Скругление кнопки (barrel/lens, через дробные блоки):
    --   h=1   — ▐ слева, ▌ справа.
    --   h=2   — row 1 полный фон + ▟▙ верх; row 2 ▀ chars + ▝▘ концы.
    --   h>=3  — barrel:
    --           row 0:        cBg углы + ▂ (нижняя 1/4 cell) тонкая «губа»
    --           row 1..h-2:   ▐/▌ полу-cell bg по бокам + полный btnBg в центре
    --           row h-1:      cBg углы + 🮂 (верхняя 1/4 cell, U+1FB82) тонкая «крышка»
    --           Идея: дробные ▂/🮂 обходят квадрант-сетку (▗▖▝▘ давали 50% таблетку,
    --           ▟▙▜▛ давали Г-углы). Получается плавная пилюля как у соседа.
    --           🮂 из Symbols for Legacy Computing — проверено что рендерится в OC unifont.
    if el.rounded and el.cornerBg and el.w >= 2 then
      local btnBg = el.bg or 0x333333
      local cBg = el.cornerBg
      if el.h == 1 then
        buf:set(x,             y, "▐", btnBg, cBg)
        buf:set(x + el.w - 1,  y, "▌", btnBg, cBg)
      elseif el.h == 2 then
        for i = 0, el.w - 1 do
          buf:set(x + i, y + 1, "▀", btnBg, cBg)
        end
        buf:set(x,             y,     "▟", btnBg, cBg)
        buf:set(x + el.w - 1,  y,     "▙", btnBg, cBg)
        buf:set(x,             y + 1, "▝", btnBg, cBg)
        buf:set(x + el.w - 1,  y + 1, "▘", btnBg, cBg)
      else
        -- Пустые углы (затираем btnBg от P.rect → cBg).
        buf:set(x,             y,             " ", cBg, cBg)
        buf:set(x + el.w - 1,  y,             " ", cBg, cBg)
        buf:set(x,             y + el.h - 1, " ", cBg, cBg)
        buf:set(x + el.w - 1,  y + el.h - 1, " ", cBg, cBg)
        -- Тонкая губа сверху и крышка снизу — только в средних колонках.
        for i = 1, el.w - 2 do
          buf:set(x + i, y,             "▂", btnBg, cBg)
          buf:set(x + i, y + el.h - 1, "🮂", btnBg, cBg)
        end
        -- Полу-cell бока для всех средних строк (h=3 → одна строка y+1).
        for j = 1, el.h - 2 do
          buf:set(x,             y + j, "▐", btnBg, cBg)
          buf:set(x + el.w - 1,  y + j, "▌", btnBg, cBg)
        end
      end
    end
    local lbl = el.label or ""
    local lx = x + math.floor((el.w - unicode.len(lbl)) / 2)
    local ly = y + math.floor((el.h - 1) / 2)
    P.text(buf, lx, ly, lbl, el.fg or 0xFFFFFF, el.bg)

  elseif t == "progress" then
    P.progressFine(buf, x, y, el.w or 20, el.value or 0,
      el.fgFill or 0x00FF00, el.bg or 0x000000)

  elseif t == "gradient" then
    if (el.direction or "h") == "v" then
      P.gradientV(buf, x, y, el.w, el.h, el.from or 0x000000, el.to or 0xFFFFFF)
    else
      P.gradientH(buf, x, y, el.w, el.h, el.from or 0x000000, el.to or 0xFFFFFF)
    end

  elseif t == "sparkline" then
    P.sparkline(buf, x, y, el.w, el.values or {}, el.color or 0x00FF00, el.bg)

  elseif t == "barchart" then
    P.barChart(buf, x, y, el.w, el.h, el.values or {}, el.color or 0x00FF00, el.bg)

  elseif t == "slider" then
    local w = el.w or 20
    local val = clamp(el.value or 0, 0, 1)
    for dx = 0, w-1 do
      buf:set(x + dx, y, "─", el.trackColor or 0x444466, el.bg)
    end
    local tx = x + math.floor(val * (w - 1))
    buf:set(tx, y, "●", el.color or 0x7C6FCD, el.bg)

  elseif t == "badge" then
    local label = " " .. (el.label or "") .. " "
    P.text(buf, x, y, label, el.fg or 0xFFFFFF, el.bg or 0x7C6FCD)

  elseif t == "pixelGrid" then
    local cells = el.cells or {}
    local rows = #cells
    for r = 1, rows do
      local row = cells[r]
      for c = 1, #row do
        if row[c] then
          buf:setPixel(x + c - 1, (y - 1) * 2 + r, row[c])
        end
      end
    end
  end

  for _, child in ipairs(el._children) do
    Renderer.draw(buf, child, absX, absY)
  end
end

-- ============================================================
--  EVENT LOOP
-- ============================================================

local EventLoop = {}

function EventLoop.collectButtons(el, absX, absY, result)
  absX = (absX or 0) + el.x - 1
  absY = (absY or 0) + el.y - 1
  result = result or {}
  if el.type == "button" and el.onClick then
    result[#result+1] = {x=absX, y=absY, w=el.w, h=el.h, onClick=el.onClick}
  end
  for _, c in ipairs(el._children) do
    EventLoop.collectButtons(c, absX, absY, result)
  end
  return result
end

function EventLoop.hitTest(buttons, tx, ty)
  for _, b in ipairs(buttons) do
    if tx >= b.x and tx < b.x + b.w and ty >= b.y and ty < b.y + b.h then
      return b
    end
  end
end

-- ============================================================
--  PUBLIC API
-- ============================================================

local GUI = {}

GUI.el = setmetatable({}, {
  __index = function(_, typeName)
    return function(props)
      props = props or {}
      props.type = typeName
      -- vbox/hbox/grid авто-включают соответствующий layout
      if typeName == "vbox" or typeName == "hbox" or typeName == "grid" then
        props.layout = props.layout or typeName
      end
      return Element.new(props)
    end
  end
})

GUI.lerpColor = lerpColor
GUI.darken    = darken
GUI.clamp     = clamp

-- Низкоуровневые помощники для тех, кто строит свой event-loop
-- (например dashboard, которому надо ловить modem_message в том же цикле).
GUI.collectButtons = function(root) return EventLoop.collectButtons(root, 1, 1) end
GUI.hitTest        = EventLoop.hitTest

-- Возвращает экран к нормальному состоянию и печатает ошибку со стек-трейсом
local function dumpError(err)
  local w, h = gpu.getResolution()
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  gpu.fill(1, 1, w, h, " ")
  gpu.setForeground(0xFF5555)
  gpu.set(1, 1, "LiteGUI error:")
  gpu.setForeground(0xFFFFFF)
  -- разбиваем по строкам и печатаем
  local y = 3
  for line in tostring(err):gmatch("[^\n]+") do
    if y > h then break end
    -- обрезаем длинные строки
    if #line > w then line = line:sub(1, w) end
    gpu.set(1, y, line)
    y = y + 1
  end
end

function GUI.render(root)
  local buf = Buffer.new()
  local ok, err = xpcall(function()
    runLayout(root)
    buf:clear(root.bg or 0x000000)
    Renderer.draw(buf, root, 1, 1)
    buf:flush()
  end, debug.traceback)
  if not ok then dumpError(err); error(err, 0) end
  return buf
end

function GUI.run(root, onFrame)
  local buf = Buffer.new()
  local running = true
  local hadError = false

  local function redrawUnsafe()
    if onFrame then onFrame(root) end
    runLayout(root)
    buf:clear(root.bg or 0x000000)
    Renderer.draw(buf, root, 1, 1)
    buf:flush()
  end

  local function redraw()
    local ok, err = xpcall(redrawUnsafe, debug.traceback)
    if not ok then
      dumpError(err)
      running = false
      hadError = true
    end
  end

  redraw()

  while running do
    local ev = {event.pull(0.1)}
    local name = ev[1]
    if name == "touch" then
      local tx, ty = ev[3], ev[4]
      local buttons = EventLoop.collectButtons(root, 1, 1)
      local hit = EventLoop.hitTest(buttons, tx, ty)
      if hit then
        local ok, err = xpcall(hit.onClick, debug.traceback)
        if not ok then
          dumpError(err); running = false; hadError = true
        else
          redraw()
        end
      end
    elseif name == "key_down" then
      local char = ev[3]
      if char == 113 or char == 27 then running = false end
    elseif name == nil then
      redraw()
    end
  end

  -- При ошибке оставляем трейс на экране; иначе чистим
  if not hadError then
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    gpu.fill(1, 1, buf.w, buf.h, " ")
  end
end

return GUI
