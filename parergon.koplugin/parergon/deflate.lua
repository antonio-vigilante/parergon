--[[--
Compressione deflate per le voci modificate dello ZIP, tramite la zlib inclusa
in KOReader (FFI).

zlib espone solo compress2(), che produce il formato "zlib": 2 byte di
intestazione + dati deflate + 4 byte di checksum Adler-32. Negli ZIP servono i
dati deflate "grezzi": si tolgono intestazione e checksum (è la stessa tecnica
del vecchio ffi/zipwriter di KOReader).

Caricamento della libreria compatibile con tutte le versioni supportate:
  - ffi.loadlib("z", 1) esiste da KOReader 2024.09;
  - prima si usava ffi.load con il percorso della libreria inclusa.
Se la zlib non si trova, M.funzione() restituisce nil e la copia viene scritta
senza compressione: più grande, ma valida.

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local M = {}

local function caricaZlib()
    local ok, ffi = pcall(require, "ffi")
    if not ok then return nil end
    -- dichiarazioni: quelle di KOReader se ci sono, altrimenti le nostre
    if not pcall(require, "ffi/zlib_h") then
        pcall(ffi.cdef, [[
            unsigned long compressBound(unsigned long);
            int compress2(unsigned char *, unsigned long *, const unsigned char *, unsigned long, int);
        ]])
    end
    local lib
    if ffi.loadlib then
        local okl, l = pcall(ffi.loadlib, "z", 1)
        if okl then lib = l end
    end
    if not lib then
        for __, nome in ipairs({ "libs/libz.so.1", "libs/libz.1.dylib", "libz.so.1", "z" }) do
            local okl, l = pcall(ffi.load, nome)
            if okl then lib = l break end
        end
    end
    if not lib then return nil end
    -- verifica che le funzioni esistano davvero
    if not pcall(function() return lib.compress2 end) then return nil end
    return ffi, lib
end

local cache

--- Restituisce una funzione dati → deflate grezzo, oppure nil se zlib non è disponibile.
function M.funzione()
    if cache ~= nil then return cache or nil end
    local ffi, lib = caricaZlib()
    if not ffi then cache = false return nil end
    cache = function(dati)
        local n = lib.compressBound(#dati)
        local buf = ffi.new("uint8_t[?]", n)
        local lun = ffi.new("unsigned long[1]", n)
        if lib.compress2(buf, lun, dati, #dati, 6) ~= 0 then return nil end
        local tot = tonumber(lun[0])
        if tot < 6 then return nil end
        return ffi.string(buf + 2, tot - 6) -- senza intestazione zlib (2) e Adler-32 (4)
    end
    return cache
end

return M
