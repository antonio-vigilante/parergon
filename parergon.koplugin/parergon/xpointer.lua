--[[--
Analisi degli XPointer di crengine.

Forma: /body/DocFragment[N]/body/div[2]/p[5]/text()[2].17
  - DocFragment[N]: N-esimo elemento dello spine "valido" (vedi epub.lua)
  - i passi successivi ricalcano l'XHTML sorgente (a partire dal suo <body>)
  - text()[k].OFFSET: k-esimo nodo di testo, offset in caratteri
  - oppure elemento.OFFSET: indice di un figlio (posizione fra i nodi)

Varianti gestite (verificate in crengine lvtinydom.cpp, toStringV1/toStringV2):
  - "[1]" omesso quando l'elemento è l'unico con quel nome (DOM < 20260812)
  - "[1]" sempre presente (DOM >= 20260812)
  - nodi di impaginazione (autoBoxing, floatBox, ...) presenti nei percorsi
    non normalizzati (DOM < 20200223): vengono saltati.

Modulo in Lua puro, testabile fuori dal dispositivo.

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local M = {}

-- Elementi interni che crengine inserisce e che non esistono nel sorgente.
M.NODI_IMPAGINAZIONE = {
    autoboxing = true, floatbox = true, inlinebox = true, tabularbox = true,
    rubybox = true, mathbox = true, pseudoelem = true,
}

-- Elementi considerati "a blocco" per stabilire se una sottolineatura sta in un solo paragrafo.
M.BLOCCHI = {
    p = true, div = true, li = true, dd = true, dt = true, blockquote = true,
    h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true,
    td = true, th = true, caption = true, figcaption = true, pre = true,
    section = true, article = true, aside = true, header = true, footer = true,
    body = true, address = true, figure = true, center = true, ul = true, ol = true,
    dl = true, table = true, tr = true, hr = true, nav = true, main = true, details = true,
    summary = true, legend = true, fieldset = true,
}

--[[--
@return tabella { frammento = N, passi = { {nome=, indice=}, ... },
                  testo = k o nil, offset = n o nil, grezzo = xp }
        oppure nil e messaggio
I passi iniziano dal <body> del file (escluso), cioè sono relativi al body.
]]
function M.analizza(xp)
    if type(xp) ~= "string" then return nil, "indirizzo non testuale" end
    local corpo, offset = xp:match("^(.-)%.(%d+)$")
    if not corpo then corpo = xp end
    offset = offset and tonumber(offset)

    local parti = {}
    for p in corpo:gmatch("[^/]+") do parti[#parti + 1] = p end
    if parti[1] ~= "body" then return nil, "non inizia con /body" end
    local n = parti[2] and parti[2]:match("^DocFragment%[(%d+)%]$")
    if not n then
        if parti[2] == "DocFragment" then n = "1" -- unico DocFragment, indice omesso
        else return nil, "manca DocFragment" end
    end

    local r = { frammento = tonumber(n), passi = {}, offset = offset, grezzo = xp }
    local i = 3
    -- il <body> del file (può mancare in documenti particolari)
    if parti[i] and parti[i]:match("^body") then i = i + 1 end
    for k = i, #parti do
        local p = parti[k]
        local idx = p:match("^text%(%)%[(%d+)%]$")
        if idx or p == "text()" then
            if k ~= #parti then return nil, "text() non finale" end
            r.testo = tonumber(idx or "1")
        else
            local nome, ind = p:match("^([%w_:%.%-]+)%[(%d+)%]$")
            if not nome then nome = p:match("^([%w_:%.%-]+)$") ind = "1" end
            if not nome then return nil, "passo non riconosciuto: " .. p end
            nome = (nome:match(":([^:]+)$") or nome):lower()
            if not M.NODI_IMPAGINAZIONE[nome] then
                r.passi[#r.passi + 1] = { nome = nome, indice = tonumber(ind) }
            end
        end
    end
    return r
end

--- Indice dell'ultimo passo a blocco (0 se non ce ne sono: il blocco è il body).
function M.indiceBlocco(passi)
    local b = 0
    for k, p in ipairs(passi) do
        if M.BLOCCHI[p.nome] then b = k end
    end
    return b
end

--- Rappresentazione testuale di una lista di passi (per confronti e per il rapporto).
function M.percorso(passi, fino)
    local t = {}
    for k = 1, (fino or #passi) do
        t[#t + 1] = passi[k].nome .. "[" .. passi[k].indice .. "]"
    end
    return "/body/" .. table.concat(t, "/")
end

return M
