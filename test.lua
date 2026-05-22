-- Мини-тест: каждый шаг печатает чекпоинт.
-- Где упадёт — там и проблема.

local GUI = require("litegui")
print("[1] litegui loaded")

local el = GUI.el
local s = el.rect { x=1, y=1, w=80, h=25, bg=0xFF0000 }
print("[2] root rect built")

s:add(el.text { x=2, y=2, text="HELLO LITEGUI", fg=0x00FF00 })
print("[3] text child added")

GUI.render(s)
print("[4] rendered (red bg + green text должны быть на экране)")

os.sleep(3)
print("[5] done")
