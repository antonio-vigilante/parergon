--[[--
Scrittura di un archivio ZIP (EPUB) in Lua puro.

Scelte:
  - le voci NON modificate si copiano così come sono nell'archivio d'origine
    (dati compressi, CRC, metodo): nessuna decompressione, nessuna ricompressione,
    e i font offuscati restano byte per byte identici;
  - le voci nuove o modificate si comprimono con una funzione esterna di deflate
    (su KOReader: zlib via FFI); se non è disponibile si salvano non compresse,
    che è comunque un EPUB valido;
  - nessun "extra field" nelle intestazioni (richiesto da OCF per il mimetype),
    nessun data descriptor, nomi UTF-8 segnalati con il bit 11.

Il file viene scritto in modo sequenziale e chiuso alla fine: chi lo usa scrive
su un percorso temporaneo e lo rinomina solo dopo la verifica.

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local crc32 = require("parergon/crc32")

local M = {}

local function le16(n)
    return string.char(n % 256, math.floor(n / 256) % 256)
end

local function le32(n)
    return string.char(n % 256, math.floor(n / 256) % 256,
                       math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

--- Data e ora nel formato MS-DOS usato dagli ZIP.
local function dataDos(t)
    local d = os.date("*t", t or os.time())
    local ora = d.hour * 2048 + d.min * 32 + math.floor(d.sec / 2)
    local data = (math.max(d.year, 1980) - 1980) * 512 + d.month * 32 + d.day
    return ora, data
end

local Scrittore = {}
Scrittore.__index = Scrittore

--[[--
Crea uno scrittore.
@param percorso file da creare (viene sovrascritto)
@param opzioni { comprimi = function(dati) → deflate grezzo oppure nil }
@return scrittore oppure nil, errore
]]
function M.nuovo(percorso, opzioni)
    local f, err = io.open(percorso, "wb")
    if not f then return nil, err end
    local o = setmetatable({
        f = f, percorso = percorso, voci = {}, nomi = {}, pos = 0,
        comprimi = opzioni and opzioni.comprimi,
    }, Scrittore)
    o.ora, o.data = dataDos()
    return o
end

function Scrittore:_scrivi(s)
    local ok, err = self.f:write(s)
    if not ok then error("scrittura non riuscita: " .. tostring(err)) end
    self.pos = self.pos + #s
end

--- Scrive intestazione locale e dati, registrando la voce per la directory centrale.
function Scrittore:_voce(v, dati)
    if self.nomi[v.nome] then error("voce duplicata nell'archivio: " .. v.nome) end
    self.nomi[v.nome] = true
    v.offset = self.pos
    -- bit 11 (UTF-8) se il nome contiene byte non ASCII; mai il bit 3 (data descriptor)
    local flag = v.flag or 0
    flag = flag - (math.floor(flag / 8) % 2) * 8
    if v.nome:find("[\128-\255]") and math.floor(flag / 2048) % 2 == 0 then flag = flag + 2048 end
    v.flag = flag
    self:_scrivi("PK\3\4" .. le16(v.versione or 20) .. le16(flag) .. le16(v.metodo)
        .. le16(v.ora) .. le16(v.data) .. le32(v.crc) .. le32(v.csize) .. le32(v.usize)
        .. le16(#v.nome) .. le16(0) .. v.nome)
    self:_scrivi(dati)
    self.voci[#self.voci + 1] = v
end

--[[--
Aggiunge una voce a partire dal contenuto in chiaro.
@param nome percorso interno
@param dati contenuto
@param comprimere false per salvarla non compressa (mimetype, immagini)
]]
function Scrittore:aggiungi(nome, dati, comprimere)
    local crc = crc32.calcola(dati)
    local metodo, contenuto = 0, dati
    if comprimere ~= false and self.comprimi and #dati > 0 then
        local def = self.comprimi(dati)
        if def and #def < #dati then metodo, contenuto = 8, def end
    end
    self:_voce({
        nome = nome, metodo = metodo, crc = crc, csize = #contenuto, usize = #dati,
        ora = self.ora, data = self.data,
    }, contenuto)
end

--[[--
Copia una voce senza toccarne i dati compressi.
@param voce voce letta da zip.apri (nome, metodo, crc, csize, usize, ora, data, flag)
@param grezzi dati grezzi letti con zip.datiGrezzi
]]
function Scrittore:copia(voce, grezzi)
    if #grezzi ~= voce.csize then error("dati grezzi di lunghezza inattesa: " .. voce.nome) end
    self:_voce({
        nome = voce.nome, metodo = voce.metodo, crc = voce.crc,
        csize = voce.csize, usize = voce.usize, ora = voce.ora, data = voce.data,
        flag = voce.flag, versione = voce.metodo == 8 and 20 or 10,
    }, grezzi)
end

--- Scrive la directory centrale e chiude il file.
function Scrittore:chiudi()
    local inizio = self.pos
    for _, v in ipairs(self.voci) do
        self:_scrivi("PK\1\2" .. le16(20) .. le16(v.versione or 20) .. le16(v.flag) .. le16(v.metodo)
            .. le16(v.ora) .. le16(v.data) .. le32(v.crc) .. le32(v.csize) .. le32(v.usize)
            .. le16(#v.nome) .. le16(0) .. le16(0) .. le16(0) .. le16(0)
            .. le32(v.nome:sub(-1) == "/" and 16 or 0) .. le32(v.offset) .. v.nome)
    end
    local dim = self.pos - inizio
    self:_scrivi("PK\5\6" .. le16(0) .. le16(0) .. le16(#self.voci) .. le16(#self.voci)
        .. le32(dim) .. le32(inizio) .. le16(0))
    self.f:close()
    self.f = nil
    return true
end

--- Chiude e cancella il file in caso di errore.
function Scrittore:annulla()
    if self.f then self.f:close() self.f = nil end
    os.remove(self.percorso)
end

return M
