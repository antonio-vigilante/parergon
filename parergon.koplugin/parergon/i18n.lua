--[[--
Traduzioni dell'interfaccia di Parergon.

Il testo di base è in inglese. Le traduzioni stanno in file .po standard
(`locales/<lingua>.po`), modificabili con qualunque strumento di traduzione
(Poedit, Weblate...). KOReader traduce solo le proprie frasi: per quelle dei
plugin esterni serve un catalogo proprio, come fanno anche altri plugin.

Lingua:
  "auto" — segue la lingua dell'interfaccia di KOReader (impostazione predefinita)
  "en", "it", ... — forza una lingua

Modulo in Lua puro: la lingua di KOReader viene fornita da main.lua
tramite M.configura, così il modulo si può testare fuori dal dispositivo.

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local M = {
    modo = "auto",            -- "auto" oppure il codice di una lingua
    catalogo = {},            -- msgid → msgstr della lingua caricata
    caricata = nil,           -- codice della lingua caricata
}

-- Funzione che restituisce la lingua di KOReader (per esempio "it_IT"). Impostata da main.lua.
local linguaKOReader = function() return nil end

--- Cartella del plugin, ricavata dalla posizione di questo file (…/parergon.koplugin/).
local function cartellaPlugin()
    local info = debug.getinfo(1, "S")
    local sorgente = info and info.source or ""
    if sorgente:sub(1, 1) == "@" then sorgente = sorgente:sub(2) end
    sorgente = sorgente:gsub("\\", "/")
    return sorgente:match("^(.*/)parergon/i18n%.lua$") or "./"
end
local CARTELLA = cartellaPlugin()

local function togliEscape(s)
    return (s:gsub("\\(.)", { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["\\"] = "\\" }))
end

--- Legge un file .po e restituisce la tabella msgid → msgstr (voci vuote escluse).
function M.leggiPo(percorso)
    local f = io.open(percorso, "r")
    if not f then return nil end
    local catalogo, voce, campo = {}, {}, nil
    local function chiudi()
        if voce.msgid and voce.msgid ~= "" and voce.msgstr and voce.msgstr ~= "" then
            catalogo[voce.msgid] = voce.msgstr
        end
        voce, campo = {}, nil
    end
    for riga in f:lines() do
        riga = riga:gsub("\r$", "")
        if riga:match("^%s*$") then
            chiudi()
        elseif not riga:match("^#") then
            local chiave, valore = riga:match('^%s*(msgid)%s+"(.*)"%s*$')
            if not chiave then chiave, valore = riga:match('^%s*(msgstr)%s+"(.*)"%s*$') end
            if chiave then
                if chiave == "msgid" and voce.msgstr then chiudi() end
                campo = chiave
                voce[campo] = togliEscape(valore)
            else
                valore = riga:match('^%s*"(.*)"%s*$')
                if campo and valore then voce[campo] = voce[campo] .. togliEscape(valore) end
            end
        end
    end
    chiudi()
    f:close()
    return catalogo
end

--- Codice della lingua effettiva ("en", "it", ...).
function M.lingua()
    local l = M.modo
    if l == "auto" then
        l = linguaKOReader()
        if type(l) ~= "string" or l == "" or l == "C" then return "en" end
    end
    return (l:gsub("[%._@].*$", ""):lower())
end

--- Carica il catalogo della lingua effettiva, se è cambiata.
local function aggiorna()
    local l = M.lingua()
    if l == M.caricata then return end
    M.caricata = l
    M.catalogo = (l ~= "en" and M.leggiPo(CARTELLA .. "locales/" .. l .. ".po")) or {}
end

--[[--
Configura il modulo.
@param opzioni { modo = "auto"/"en"/"it"..., lingua_koreader = function() ... end,
                 cartella = percorso del plugin (solo per i test) }
]]
function M.configura(opzioni)
    if opzioni.modo then M.modo = opzioni.modo end
    if opzioni.lingua_koreader then linguaKOReader = opzioni.lingua_koreader end
    if opzioni.cartella then CARTELLA = opzioni.cartella end
    M.caricata = nil
end

--- Lingue disponibili: inglese più quelle con un file in locales/ (elenco fisso, senza lfs).
M.DISPONIBILI = { { "en", "English" }, { "it", "Italiano" } }

--- Traduce una frase. Se manca la traduzione restituisce l'originale inglese.
function M.tr(msgid)
    aggiorna()
    return M.catalogo[msgid] or msgid
end

--- Traduce e formatta: M.trf("%d annotations", n).
function M.trf(msgid, ...)
    return string.format(M.tr(msgid), ...)
end

setmetatable(M, { __call = function(_, msgid) return M.tr(msgid) end })

return M
