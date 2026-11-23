--[[--
CRC-32 (polinomio 0xEDB88320, quello degli archivi ZIP) in Lua puro.

Usa il modulo `bit` di LuaJIT, presente in KOReader su tutte le piattaforme.
Restituisce numeri non negativi (0 .. 2^32-1).

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local bit = require("bit")
local band, bxor, rshift, bnot = bit.band, bit.bxor, bit.rshift, bit.bnot

local TABELLA = {}
for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
        if band(c, 1) == 1 then
            c = bxor(rshift(c, 1), 0xEDB88320)
        else
            c = rshift(c, 1)
        end
    end
    TABELLA[i] = c
end

local M = {}

--- CRC-32 di una stringa; `crc` permette di continuare un calcolo precedente.
function M.calcola(s, crc)
    crc = bnot(crc or 0)
    local byte = string.byte
    for i = 1, #s do
        crc = bxor(rshift(crc, 8), TABELLA[band(bxor(crc, byte(s, i)), 0xFF)])
    end
    crc = bnot(crc)
    if crc < 0 then crc = crc + 4294967296 end
    return crc
end

return M
