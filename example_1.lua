-- ============================================================
--  example_1.lua — showcase для litegui
--  Q или Escape — выход
-- ============================================================

local GUI = require("litegui")
local el  = GUI.el

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

local screen = el.rect { x=1, y=1, w=80, h=25, bg=C.bg }

-- ── HEADER: вертикальный градиент полосы ───────────────────
screen:add(el.gradient { x=1, y=1, w=80, h=3, direction="v",
                         from=0x2E2E55, to=C.panel })
screen:add(el.text { x=3,  y=2, text="▎ LiteGUI", fg=C.accent })
screen:add(el.text { x=14, y=2, text="· half-block render demo", fg=C.dim })
screen:add(el.text { x=63, y=2, text="press Q to exit", fg=C.dim })

-- ── PANEL 1: SYSTEM (прогресс-бары + sparkline) ────────────
local p1 = el.panel { x=1, y=4, w=27, h=10, bg=C.panel, border=C.border,
                      title="system", titleFg=C.accent,
                      shadow=true, shadowColor=C.shadow }
p1:add(el.text     { x=2,  y=2, text="CPU",  fg=C.dim   })
p1:add(el.text     { x=22, y=2, text="34%",  fg=C.green })
p1:add(el.progress { x=2,  y=3, w=24, value=0.34, fgFill=C.green,  bg=C.panel })

p1:add(el.text     { x=2,  y=4, text="RAM",  fg=C.dim    })
p1:add(el.text     { x=22, y=4, text="71%",  fg=C.yellow })
p1:add(el.progress { x=2,  y=5, w=24, value=0.71, fgFill=C.yellow, bg=C.panel })

p1:add(el.text     { x=2,  y=6, text="DISK", fg=C.dim })
p1:add(el.text     { x=22, y=6, text="92%",  fg=C.red })
p1:add(el.progress { x=2,  y=7, w=24, value=0.92, fgFill=C.red,    bg=C.panel })

-- мини-история загрузки
local spark = {}
for i = 1, 24 do
  spark[i] = math.sin(i * 0.45) * 0.4 + 0.5 + math.random() * 0.2
end
p1:add(el.sparkline { x=2, y=9, w=24, values=spark, color=C.accent, bg=C.panel })
screen:add(p1)

-- ── PANEL 2: GAUGE (круговой индикатор) ────────────────────
local p2 = el.panel { x=29, y=4, w=25, h=10, bg=C.panel, border=C.border,
                      title="power", titleFg=C.accent,
                      shadow=true, shadowColor=C.shadow }
p2:add(el.gauge {
  x=7, y=2, r=6, value=0.72,
  color=C.green, bgColor=C.gaugeBg, thickness=2,
  label="72%", caption="kW load",
  fg=C.white, captionFg=C.dim, bg=C.panel,
})
screen:add(p2)

-- ── PANEL 3: ACTIONS (badges + кнопки с тенями) ────────────
local p3 = el.panel { x=55, y=4, w=25, h=10, bg=C.panel, border=C.border,
                      title="actions", titleFg=C.accent,
                      shadow=true, shadowColor=C.shadow }
p3:add(el.badge { x=2,  y=2, label="LIVE", bg=C.green,  fg=0x000000 })
p3:add(el.badge { x=9,  y=2, label="v0.2", bg=C.panel2, fg=C.dim   })
p3:add(el.badge { x=16, y=2, label="OK",   bg=C.blue,   fg=0x000000 })

p3:add(el.button { x=2, y=4, w=22, h=2,
  bg=C.accent, border=C.accent, borderStyle="rounded",
  label="reboot", fg=0xFFFFFF,
  shadow=true, shadowColor=C.shadow,
  onClick = function() end })

p3:add(el.button { x=2, y=7, w=22, h=2,
  bg=C.panel2, border=C.red, borderStyle="rounded",
  label="shutdown", fg=C.red,
  shadow=true, shadowColor=C.shadow,
  onClick = function() end })
screen:add(p3)

-- ── PANEL 4: TRAFFIC (bar chart с плавными столбцами) ─────
local p4 = el.panel { x=1, y=15, w=42, h=9, bg=C.panel, border=C.border,
                      title="traffic", titleFg=C.accent,
                      shadow=true, shadowColor=C.shadow }
local bars = {}
for i = 1, 18 do
  bars[i] = math.sin(i * 0.55) * 0.35 + 0.5 + math.random() * 0.25
end
p4:add(el.barchart { x=2, y=2, w=38, h=5, values=bars,
                     color=C.blue, bg=C.panel })
p4:add(el.text { x=2,  y=8, text="now",  fg=C.dim })
p4:add(el.text { x=35, y=8, text="-18m", fg=C.dim })
screen:add(p4)

-- ── PANEL 5: RENDER (filled circles + слайдеры) ───────────
local p5 = el.panel { x=45, y=15, w=35, h=9, bg=C.panel, border=C.border,
                      title="render", titleFg=C.accent,
                      shadow=true, shadowColor=C.shadow }
-- три перекрывающихся заливных круга — реальная пиксельная графика
p5:add(el.circle { x=8,  y=4, r=5, color=C.pink,   fill=true })
p5:add(el.circle { x=14, y=4, r=5, color=C.cyan,   fill=true })
p5:add(el.circle { x=11, y=5, r=5, color=C.yellow, fill=true })

-- слайдеры справа
p5:add(el.text   { x=22, y=2, text="hue",  fg=C.dim })
p5:add(el.slider { x=22, y=3, w=11, value=0.62,
                   color=C.accent, trackColor=C.border, bg=C.panel })
p5:add(el.text   { x=22, y=5, text="sat",  fg=C.dim })
p5:add(el.slider { x=22, y=6, w=11, value=0.84,
                   color=C.cyan,   trackColor=C.border, bg=C.panel })
p5:add(el.text   { x=22, y=7, text="r=5", fg=C.dim })
screen:add(p5)

-- ── FOOTER ────────────────────────────────────────────────
screen:add(el.gradient { x=1, y=25, w=80, h=1, direction="h",
                         from=C.panel, to=C.panel2 })
screen:add(el.text { x=2,  y=25, text="litegui v0.2 · half-block graphics", fg=C.dim })
screen:add(el.text { x=56, y=25, text="80×25 · OpenComputers",              fg=C.dim })

-- ============================================================
GUI.run(screen)
