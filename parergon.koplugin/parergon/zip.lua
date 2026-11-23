--[[--
Lettura della struttura di un archivio ZIP (EPUB) in Lua puro.

Legge la directory centrale e i dati grezzi (compressi) di ogni voce, senza
decomprimere. La decompressione, quando serve, è affidata a una funzione esterna
(su KOReader: ffi/archiver se presente, altrimenti crengine). Così il modulo
funziona con tutte le versioni di KOReader e si può testare sul PC.

Il file viene aperto solo in lettura ("rb"): l'originale non viene mai modificato.

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local _ = require("parergon/i18n")

local M = {}

local function u16(s, i)
    local a, b = s:byte(i, i + 1)
    return a + b * 256
end

local function u32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end
M.u16, M.u32 = u16, u32

--[[--
Apre un archivio e ne legge la directory centrale.
@return oggetto { percorso, voci = { {nome, metodo, crc, csize, usize, offset, flag,
                  ora, data, est_locale} }, perNome = {nome → voce} }
        oppure nil e messaggio
]]
function M.apri(percorso)
    local f, err = io.open(percorso, "rb")
    if not f then return nil, _.trf("cannot open the file: %s", tostring(err)) end
    local dim = f:seek("end")
    -- l'End Of Central Directory sta negli ultimi 22 byte + commento (max 65535)
    local coda = math.min(dim, 22 + 65535)
    f:seek("set", dim - coda)
    local buf = f:read(coda)
    local eocd
    for i = #buf - 21, 1, -1 do
        if buf:byte(i) == 0x50 and buf:sub(i, i + 3) == "PK\5\6" then eocd = i break end
    end
    if not eocd then f:close() return nil, _("not a valid ZIP archive") end
    local nvoci = u16(buf, eocd + 10)
    local cd_dim = u32(buf, eocd + 12)
    local cd_off = u32(buf, eocd + 16)
    if nvoci == 0xFFFF or cd_off == 0xFFFFFFFF then
        f:close() return nil, _("ZIP64 archives are not supported")
    end
    f:seek("set", cd_off)
    local cd = f:read(cd_dim)
    if not cd or #cd ~= cd_dim then f:close() return nil, _("the ZIP central directory cannot be read") end

    local voci, perNome, p = {}, {}, 1
    for __ = 1, nvoci do
        if cd:sub(p, p + 3) ~= "PK\1\2" then f:close() return nil, _("the ZIP central directory is damaged") end
        local ln, le, lc = u16(cd, p + 28), u16(cd, p + 30), u16(cd, p + 32)
        local v = {
            flag = u16(cd, p + 8), metodo = u16(cd, p + 10),
            ora = u16(cd, p + 12), data = u16(cd, p + 14),
            crc = u32(cd, p + 16), csize = u32(cd, p + 20), usize = u32(cd, p + 24),
            offset = u32(cd, p + 42),
            nome = cd:sub(p + 46, p + 45 + ln),
        }
        voci[#voci + 1] = v
        perNome[v.nome] = v
        p = p + 46 + ln + le + lc
    end
    f:close()
    return { percorso = percorso, voci = voci, perNome = perNome, dimensione = dim }
end

--- Legge i dati grezzi (così come sono nell'archivio, eventualmente compressi) di una voce.
function M.datiGrezzi(arch, voce)
    local f, err = io.open(arch.percorso, "rb")
    if not f then return nil, err end
    f:seek("set", voce.offset)
    local h = f:read(30)
    if not h or h:sub(1, 4) ~= "PK\3\4" then f:close() return nil, _("invalid ZIP local header") end
    local ln, le = u16(h, 27), u16(h, 29)
    voce.est_locale = le
    f:seek("set", voce.offset + 30 + ln + le)
    local dati = f:read(voce.csize)
    f:close()
    if voce.csize > 0 and (not dati or #dati ~= voce.csize) then return nil, _("truncated data") end
    return dati or ""
end

--- Contenuto di una voce non compressa (metodo 0). Per le altre restituisce nil.
function M.leggiNonCompresso(arch, nome)
    local v = arch.perNome[nome]
    if not v then return nil, _.trf("entry not found: %s", nome) end
    if v.metodo ~= 0 then return nil, _("compressed entry") end
    return M.datiGrezzi(arch, v)
end

return M
