--[[--
Indice personale: struttura per temi, pagina XHTML e rami della TOC.

Organizzazione:
  - per TEMI (#tema nelle note, anche annidati #genitore/figlio, come la patch
    utente "Indice tematico"); un'annotazione con più temi compare sotto ciascuno;
  - le annotazioni senza tema vanno in fondo, sotto "Altre annotazioni";
  - se nessuna annotazione ha un tema, le voci si raggruppano per capitolo.

Titolo di una voce: la riga "# Titolo" della nota → la prima riga del commento →
le prime parole del passo.

Nella TOC compaiono i gruppi di primo livello (temi o capitoli), che portano
alla sezione corrispondente della pagina; a richiesta (opzione sottotemi_toc) anche
i sotto-temi diretti, un livello sotto. Mai le singole voci né i livelli più profondi:
con molte annotazioni la TOC sarebbe ingestibile, e molte applicazioni gestiscono
male i livelli profondi.

Modulo in Lua puro, testabile fuori dal dispositivo.

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local note = require("parergon/note")
local testo = require("parergon/testo")
local _ = require("parergon/i18n")

local M = {}

--- Prime `n` parole di un testo, con "…" se tagliato.
local function primeParole(s, n)
    local parole = {}
    for p in s:gmatch("%S+") do
        parole[#parole + 1] = p
        if #parole > n then break end
    end
    if #parole > n then
        parole[n + 1] = nil
        return table.concat(parole, " ") .. "…"
    end
    return table.concat(parole, " ")
end

--[[--
Nome di un tema (o di un sotto-tema) come compare nell'indice e nella TOC: trattini e
trattini bassi diventano spazi («arte-greca» → «arte greca»). Il nome scritto nella nota
non cambia. Se resterebbe vuoto (per esempio «#-»), si mostra com'è.
]]
function M.nomeVisibile(parte)
    local s = parte:gsub("[-_]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return parte end
    return s
end

--- Titolo della voce: "# Titolo", poi prima riga del commento, poi inizio del passo.
function M.titolo(ann, analisi_nota)
    local n = analisi_nota or note.analizza(ann)
    if n.titolo then return n.titolo end
    if n.corpo ~= "" then
        local riga = n.corpo:match("^([^\n]+)")
        local t, tronco = testo.primiCaratteri(riga, 60)
        return t .. (tronco and "…" or "")
    end
    return primeParole(testo.normalizza(ann.text), 8)
end

--[[--
Costruisce i gruppi dell'indice.
@param voci lista di { id, file, ann } nell'ordine del libro
@param opz { criterio = "tutte" | "con_tema" | "con_nota", ordine = "alfabetico" | "posizione" }
@return { gruppi = { {nome, figli = {...}, voci = {...}} }, per_capitolo = bool, n = numero di voci }
]]
function M.costruisci(voci, opz)
    opz = opz or {}
    local criterio = opz.criterio or "tutte"
    local scelte = {}
    for i, v in ipairs(voci) do
        local n = note.analizza(v.ann)
        local ok = criterio == "tutte"
            or (criterio == "con_tema" and #n.temi > 0)
            or (criterio == "con_nota" and not n.vuota)
        if ok then
            v.nota, v.posizione = n, i
            v.titolo = M.titolo(v.ann, n)
            scelte[#scelte + 1] = v
        end
    end

    local con_temi = false
    for __, v in ipairs(scelte) do if #v.nota.temi > 0 then con_temi = true break end end

    local radice = { figli = {}, perNome = {}, voci = {} }
    local function nodo(percorso)
        local corrente = radice
        local completo = ""
        for parte in percorso:gmatch("[^/]+") do
            completo = completo == "" and parte or (completo .. "/" .. parte)
            -- i nodi si distinguono per la forma visualizzata: #arte-greca e #arte_greca
            -- finiscono sotto lo stesso titolo «arte greca»
            local nome = M.nomeVisibile(parte)
            local f = corrente.perNome[nome]
            if not f then
                f = { nome = nome, completo = completo, figli = {}, perNome = {}, voci = {}, prima = math.huge }
                corrente.perNome[nome] = f
                corrente.figli[#corrente.figli + 1] = f
            end
            corrente = f
        end
        return corrente
    end

    local altre = {}
    if con_temi then
        for __, v in ipairs(scelte) do
            if #v.nota.temi == 0 then
                altre[#altre + 1] = v
            else
                for __, t in ipairs(v.nota.temi) do
                    local nd = nodo(t)
                    nd.voci[#nd.voci + 1] = v
                    -- posizione della prima comparsa, propagata ai genitori
                    local percorso = ""
                    for parte in t:gmatch("[^/]+") do
                        percorso = percorso == "" and parte or (percorso .. "/" .. parte)
                        local x = nodo(percorso)
                        if v.posizione < x.prima then x.prima = v.posizione end
                    end
                end
            end
        end
        local function ordina(lista)
            if opz.ordine == "posizione" then
                table.sort(lista, function(a, b) return a.prima < b.prima end)
            else
                table.sort(lista, function(a, b) return a.nome:lower() < b.nome:lower() end)
            end
            for __, x in ipairs(lista) do ordina(x.figli) end
        end
        ordina(radice.figli)
        if #altre > 0 then
            radice.figli[#radice.figli + 1] = { nome = _("Other annotations"), figli = {}, voci = altre, altre = true }
        end
    else
        -- nessun tema: raggruppa per capitolo, nell'ordine del libro
        local perCap = {}
        for __, v in ipairs(scelte) do
            local cap = v.ann.chapter and v.ann.chapter ~= "" and v.ann.chapter or _("Untitled chapter")
            local g = perCap[cap]
            if not g then
                g = { nome = cap, figli = {}, voci = {} }
                perCap[cap] = g
                radice.figli[#radice.figli + 1] = g
            end
            g.voci[#g.voci + 1] = v
        end
    end
    return { gruppi = radice.figli, per_capitolo = not con_temi, n = #scelte }
end

--- Numero di voci di un gruppo, compresi i sotto-gruppi (un'annotazione conta una volta per gruppo).
local function totale(g)
    local visti, n = {}, 0
    local function conta(x)
        for __, v in ipairs(x.voci) do if not visti[v] then visti[v] = true n = n + 1 end end
        for __, f in ipairs(x.figli) do conta(f) end
    end
    conta(g)
    return n
end
M.totale = totale

--[[--
Pagina XHTML dell'indice.
@param struttura risultato di M.costruisci
@param p { titolo, lingua, css, nome_pagina (percorso interno), relativo = function(da, a),
           sottotemi_toc = bool (anche i sotto-temi diretti nella TOC), epub2 = bool }
@return xhtml, gruppi_toc = { {titolo, href, figli = { {titolo, href} }} } (frammenti relativi alla pagina)
]]
function M.pagina(struttura, p)
    local e = testo.escapeXml
    local righe = testo.inizioPagina{ titolo = p.titolo, css = p.css, lingua = p.lingua,
        epub2 = p.epub2, ns_epub = true }
    -- in EPUB 2 (XHTML 1.1) <section> non esiste
    local sezione = p.epub2 and "div" or "section"
    righe[#righe + 1] = "  <" .. sezione .. ' class="parergon-index">'
    righe[#righe + 1] = '    <h1 class="parergon-index-title">' .. e(p.titolo) .. "</h1>"
    local toc, k = {}, 0
    local function voce(v)
        local href = p.relativo(p.nome_pagina, v.file) .. "#" .. v.id
        righe[#righe + 1] = '    <div class="parergon-index-entry">'
        righe[#righe + 1] = '      <p class="parergon-index-head"><a href="' .. e(href) .. '">' .. e(v.titolo) .. "</a></p>"
        local passo, tronco = testo.primiCaratteri(testo.normalizza(v.ann.text), 200)
        local riga = "«" .. e(passo) .. (tronco and "…" or "") .. "»"
        if v.ann.chapter and v.ann.chapter ~= "" then riga = riga .. " — " .. e(v.ann.chapter) end
        righe[#righe + 1] = '      <p class="parergon-index-passage">' .. riga .. "</p>"
        local corpo = note.xhtml(v.nota.corpo, true)
        -- il commento compare se aggiunge qualcosa al titolo
        if corpo and not (v.nota.titolo == nil and not v.nota.corpo:find("\n") and #testo.normalizza(v.nota.corpo) <= 60) then
            righe[#righe + 1] = '      <p class="parergon-index-note">' .. corpo .. "</p>"
        end
        righe[#righe + 1] = "    </div>"
    end
    local function gruppo(g, livello, padre_toc)
        k = k + 1
        local id = "parergon-g-" .. k
        local h = "h" .. math.min(livello + 1, 6)
        righe[#righe + 1] = "    <" .. h .. ' class="parergon-index-group" id="' .. id .. '">'
            .. e(g.nome) .. ' <span class="parergon-index-count">(' .. totale(g) .. ")</span></" .. h .. ">"
        local voce_toc
        if livello == 1 then
            voce_toc = { titolo = g.nome, href = "#" .. id, figli = {} }
            toc[#toc + 1] = voce_toc
        elseif livello == 2 and p.sottotemi_toc and padre_toc then
            voce_toc = { titolo = g.nome, href = "#" .. id, figli = {} }
            padre_toc.figli[#padre_toc.figli + 1] = voce_toc
        end
        for __, v in ipairs(g.voci) do voce(v) end
        for __, f in ipairs(g.figli) do gruppo(f, livello + 1, voce_toc) end
    end
    for __, g in ipairs(struttura.gruppi) do gruppo(g, 1) end
    righe[#righe + 1] = "  </" .. sezione .. ">"
    righe[#righe + 1] = "</body>"
    righe[#righe + 1] = "</html>"
    righe[#righe + 1] = ""
    return table.concat(righe, "\n"), toc
end

return M
