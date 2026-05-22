-- ============================================================
--  example_1.lua — showcase для litegui
--  Q или Escape — выход
--  Дизайн под 160×50 (тир 3 GPU + тир 3 screen)
-- ============================================================

local GUI = require("litegui")
local el  = GUI.el

local gpu = require("component").gpu
local computer = require("computer")
gpu.setResolution(160, 50)

-- ── Палитра (tailwind-esque, dark) ─────────────────────────
local C = {
  bg       = 0x0F0F1A,
  panel    = 0x1A1A2E,
  panel2   = 0x252540,
  border   = 0x3D3D5C,
  shadow   = 0x05050A,
  accent   = 0xA78BFA,  -- violet
  blue     = 0x60A5FA,
  green    = 0x4ADE80,
  yellow   = 0xFBBF24,
  red      = 0xF87171,
  pink     = 0xF472B6,
  cyan     = 0x22D3EE,
  white    = 0xF8FAFC,
  dim      = 0x64748B,
  gaugeBg  = 0x2A2A44,
}

local screen = el.rect { x=1, y=1, w=160, h=50, bg=C.bg }

-- ── HEADER: градиентная полоса ─────────────────────────────
screen:add(el.gradient { x=1, y=1, w=160, h=3, direction="v",
                         from=0x2E2E55, to=C.panel })
screen:add(el.text { x=4,  y=2, text="▎ LiteGUI",                 fg=C.accent })
screen:add(el.text { x=15, y=2, text="· half-block render demo",  fg=C.dim    })
screen:add(el.text { x=137, y=2, text="press Q to exit",          fg=C.dim    })

-- ────────────────────────────────────────────────────────────
-- TOP ROW (y=5-22, h=18) — 3 панели
-- ────────────────────────────────────────────────────────────

-- ── PANEL 1: SYSTEM ────────────────────────────────────────
local p1 = el.panel { x=1, y=5, w=52, h=18, bg=C.panel, border=C.border,
                      title="system", titleFg=C.accent,
                      shadow=true, shadowColor=C.shadow }
local function metric(panel, y, label, value, pct, color)
  panel:add(el.text     { x=2,  y=y,   text=label, fg=C.dim })
  panel:add(el.text     { x=44, y=y,   text=value, fg=color })
  panel:add(el.progress { x=2,  y=y+1, w=48, value=pct, fgFill=color, bg=C.panel })
end
metric(p1,  2, "CPU",  "34%",      0.34, C.green)
metric(p1,  5, "RAM",  "71%",      0.71, C.yellow)
metric(p1,  8, "DISK", "92%",      0.92, C.red)
metric(p1, 11, "NET",  "12 Mb/s",  0.58, C.cyan)

-- мини-история
local spark = {}
for i = 1, 48 do
  spark[i] = math.sin(i * 0.32) * 0.4 + 0.5 + math.random() * 0.2
end
p1:add(el.text     { x=2,  y=14, text="60s history", fg=C.dim })
p1:add(el.sparkline{ x=2,  y=15, w=48, values=spark, color=C.accent, bg=C.panel })
p1:add(el.text     { x=2,  y=17, text="all systems nominal", fg=C.green })
screen:add(p1)

-- ── PANEL 2: POWER (большой gauge) ─────────────────────────
local p2 = el.panel { x=54, y=5, w=52, h=18, bg=C.panel, border=C.border,
                      title="power", titleFg=C.accent,
                      shadow=true, shadowColor=C.shadow }
p2:add(el.gauge {
  x=15, y=2, r=11, value=0.72, thickness=3,
  color=C.green, bgColor=C.gaugeBg,
  label="72%", caption="kW load",
  fg=C.white, captionFg=C.dim, bg=C.panel,
})
-- доп. метрики под gauge
p2:add(el.text { x=4,  y=15, text="VOLT",  fg=C.dim   })
p2:add(el.text { x=4,  y=16, text="240 V", fg=C.white })
p2:add(el.text { x=22, y=15, text="CURR",  fg=C.dim   })
p2:add(el.text { x=22, y=16, text="3.0 A", fg=C.white })
p2:add(el.text { x=40, y=15, text="FREQ",  fg=C.dim   })
p2:add(el.text { x=40, y=16, text="60 Hz", fg=C.white })
screen:add(p2)

-- ── PANEL 3: ACTIONS ───────────────────────────────────────
local p3 = el.panel { x=107, y=5, w=54, h=18, bg=C.panel, border=C.border,
                      title="actions", titleFg=C.accent,
                      shadow=true, shadowColor=C.shadow }
p3:add(el.badge { x=2,  y=2, label="LIVE",   bg=C.green,  fg=0x000000 })
p3:add(el.badge { x=10, y=2, label="v0.2",   bg=C.panel2, fg=C.dim })
p3:add(el.badge { x=17, y=2, label="OK",     bg=C.blue,   fg=0x000000 })
p3:add(el.badge { x=23, y=2, label="STABLE", bg=C.accent, fg=0x000000 })

p3:add(el.button { x=2, y=5, w=50, h=2,
  bg=C.accent, border=C.accent, borderStyle="rounded",
  label="reboot system", fg=0xFFFFFF,
  shadow=true, shadowColor=C.shadow,
  onClick = function() computer.shutdown(true) end })

p3:add(el.button { x=2, y=8, w=50, h=2,
  bg=C.panel2, border=C.blue, borderStyle="rounded",
  label="run diagnostics", fg=C.blue,
  shadow=true, shadowColor=C.shadow,
  onClick = function() end })

p3:add(el.button { x=2, y=11, w=50, h=2,
  bg=C.panel2, border=C.yellow, borderStyle="rounded",
  label="check updates", fg=C.yellow,
  shadow=true, shadowColor=C.shadow,
  onClick = function() end })

p3:add(el.button { x=2, y=14, w=50, h=2,
  bg=C.panel2, border=C.red, borderStyle="rounded",
  label="shutdown", fg=C.red,
  shadow=true, shadowColor=C.shadow,
  onClick = function() computer.shutdown(false) end })

p3:add(el.text { x=2, y=17, text="last action: 3m ago", fg=C.dim })
screen:add(p3)

-- ────────────────────────────────────────────────────────────
-- BOTTOM ROW (y=24-46, h=23) — 2 широкие панели
-- ────────────────────────────────────────────────────────────

-- ── PANEL 4: TRAFFIC ───────────────────────────────────────
local p4 = el.panel { x=1, y=24, w=79, h=23, bg=C.panel, border=C.border,
                      title="traffic", titleFg=C.accent,
                      shadow=true, shadowColor=C.shadow }
local bars = {}
for i = 1, 36 do
  bars[i] = math.sin(i * 0.35) * 0.35 + 0.5 + math.random() * 0.25
end
p4:add(el.barchart { x=2, y=2, w=75, h=17, values=bars,
                     color=C.blue, bg=C.panel })
p4:add(el.text  { x=2,  y=20, text="now",                       fg=C.dim   })
p4:add(el.text  { x=35, y=20, text="last 36 min · 1 min/bar",   fg=C.dim   })
p4:add(el.text  { x=72, y=20, text="-36m",                      fg=C.dim   })
p4:add(el.badge { x=2,  y=21, label="↑ 12% vs yesterday",       bg=C.green, fg=0x000000 })
screen:add(p4)

-- ── PANEL 5: RENDER (большие круги + сайдбар) ──────────────
local p5 = el.panel { x=81, y=24, w=80, h=23, bg=C.panel, border=C.border,
                      title="render",  titleFg=C.accent,
                      shadow=true, shadowColor=C.shadow }

-- три больших заливных круга — теперь реально круглые
p5:add(el.circle { x=18, y=8,  r=11, color=C.pink,   fill=true })
p5:add(el.circle { x=30, y=8,  r=11, color=C.cyan,   fill=true })
p5:add(el.circle { x=24, y=12, r=11, color=C.yellow, fill=true })

-- контурный круг для разнообразия
p5:add(el.circle { x=44, y=8, r=8, color=C.accent, thickness=2 })

-- сайдбар справа
p5:add(el.text   { x=55, y=2,  text="parameters", fg=C.accent })

p5:add(el.text   { x=55, y=4,  text="hue", fg=C.dim })
p5:add(el.slider { x=55, y=5,  w=22, value=0.62, color=C.accent, trackColor=C.border, bg=C.panel })

p5:add(el.text   { x=55, y=7,  text="saturation", fg=C.dim })
p5:add(el.slider { x=55, y=8,  w=22, value=0.84, color=C.cyan,   trackColor=C.border, bg=C.panel })

p5:add(el.text   { x=55, y=10, text="radius", fg=C.dim })
p5:add(el.slider { x=55, y=11, w=22, value=0.50, color=C.green,  trackColor=C.border, bg=C.panel })

p5:add(el.text   { x=55, y=13, text="opacity", fg=C.dim })
p5:add(el.slider { x=55, y=14, w=22, value=0.75, color=C.yellow, trackColor=C.border, bg=C.panel })

-- легенда внизу
p5:add(el.text  { x=2,  y=20, text="filled circles в pixel space (half-block)", fg=C.dim })
p5:add(el.badge { x=2,  y=21, label="r=11", bg=C.panel2, fg=C.dim })
p5:add(el.badge { x=9,  y=21, label="160x100 px", bg=C.panel2, fg=C.dim })
screen:add(p5)

-- ── FOOTER ────────────────────────────────────────────────
screen:add(el.gradient { x=1, y=48, w=160, h=3, direction="v",
                         from=C.panel, to=C.panel2 })
screen:add(el.text { x=4,   y=49, text="litegui v0.2 · half-block graphics", fg=C.dim })
screen:add(el.text { x=120, y=49, text="160x50 · OpenComputers",             fg=C.dim })

-- ============================================================
GUI.run(screen)
