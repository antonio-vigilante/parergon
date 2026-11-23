--[[--
Tokenizzatore XML/XHTML con posizioni in byte, e costruzione di un albero leggero.

Perché non un parser completo: vogliamo modificare il file sorgente in modo
chirurgico, inserendo testo in punti precisi e lasciando identico ogni altro byte.
Servono quindi le posizioni esatte di tag e testi, che i parser disponibili in
KOReader (luxl, htmlparser) non forniscono.

Modulo in Lua puro, testabile fuori dal dispositivo.

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local M = {}

-- Elementi HTML vuoti: se scritti senza "/>" (HTML e non XHTML) non aspettano chiusura.
local VUOTI = {
    area = true, base = true, br = true, col = true, embed = true, hr = true, img = true,
    input = true, link = true, meta = true, param = true, source = true, track = true, wbr = true,
}

--- Nome locale minuscolo (senza prefisso di namespace).
local function nomeLocale(qnome)
    local locale = qnome:match(":([^:]+)$") or qnome
    return locale:lower()
end
M.nomeLocale = nomeLocale

--- Analizza gli attributi dell'interno di un tag di apertura.
function M.attributi(interno)
    local attr = {}
    for nome, _, valore in interno:gmatch("([%w_:%.%-]+)%s*=%s*([\"'])(.-)%2") do
        attr[nome] = valore
        local locale = nome:match(":(.+)$")
        if locale and attr[locale] == nil then attr[locale] = valore end -- es. epub:type → anche "type"
    end
    return attr
end

--[[--
Suddivide `src` in token. Ogni token ha:
  t    — "apre", "chiude", "vuoto", "testo", "commento", "cdata", "pi", "doctype"
  s, e — primo e ultimo byte (inclusi)
  nome — nome locale minuscolo (per i tag)
  qnome — nome completo come scritto (per i tag)
  interno — testo fra il nome e la fine del tag (per i tag di apertura/vuoti)
@return lista di token, oppure nil e messaggio d'errore
]]
function M.tokenizza(src)
    local tok, n = {}, #src
    local pos = 1
    while pos <= n do
        local lt = src:find("<", pos, true)
        if not lt then
            tok[#tok + 1] = { t = "testo", s = pos, e = n }
            break
        end
        if lt > pos then
            tok[#tok + 1] = { t = "testo", s = pos, e = lt - 1 }
        end
        local c2 = src:sub(lt + 1, lt + 1)
        if src:sub(lt, lt + 3) == "<!--" then
            local _, fine = src:find("-->", lt + 4, true)
            if not fine then return nil, "commento non chiuso al byte " .. lt end
            tok[#tok + 1] = { t = "commento", s = lt, e = fine }
            pos = fine + 1
        elseif src:sub(lt, lt + 8) == "<![CDATA[" then
            local _, fine = src:find("]]>", lt + 9, true)
            if not fine then return nil, "CDATA non chiuso al byte " .. lt end
            tok[#tok + 1] = { t = "cdata", s = lt, e = fine }
            pos = fine + 1
        elseif c2 == "?" then
            local _, fine = src:find("?>", lt + 2, true)
            if not fine then return nil, "istruzione non chiusa al byte " .. lt end
            tok[#tok + 1] = { t = "pi", s = lt, e = fine }
            pos = fine + 1
        elseif c2 == "!" then
            -- DOCTYPE, eventualmente con sottoinsieme interno [ ... ]
            local i, profondita, virgolette = lt + 2, 0, nil
            while i <= n do
                local c = src:sub(i, i)
                if virgolette then
                    if c == virgolette then virgolette = nil end
                elseif c == '"' or c == "'" then virgolette = c
                elseif c == "[" then profondita = profondita + 1
                elseif c == "]" then profondita = profondita - 1
                elseif c == ">" and profondita <= 0 then break
                end
                i = i + 1
            end
            if i > n then return nil, "dichiarazione non chiusa al byte " .. lt end
            tok[#tok + 1] = { t = "doctype", s = lt, e = i }
            pos = i + 1
        elseif c2 == "/" then
            local fine = src:find(">", lt + 2, true)
            if not fine then return nil, "tag di chiusura non terminato al byte " .. lt end
            local qnome = src:match("^%s*([%w_:%.%-]+)", lt + 2)
            if not qnome then return nil, "tag di chiusura senza nome al byte " .. lt end
            tok[#tok + 1] = { t = "chiude", s = lt, e = fine, qnome = qnome, nome = nomeLocale(qnome) }
            pos = fine + 1
        else
            local qnome = src:match("^([%w_:%.%-]+)", lt + 1)
            if not qnome then
                -- "<" isolato (HTML scorretto): lo consideriamo testo
                tok[#tok + 1] = { t = "testo", s = lt, e = lt }
                pos = lt + 1
            else
                -- cerca il ">" finale rispettando le virgolette degli attributi
                local i, virgolette = lt + 1 + #qnome, nil
                while i <= n do
                    local c = src:sub(i, i)
                    if virgolette then
                        if c == virgolette then virgolette = nil end
                    elseif c == '"' or c == "'" then virgolette = c
                    elseif c == ">" then break
                    end
                    i = i + 1
                end
                if i > n then return nil, "tag <" .. qnome .. "> non terminato al byte " .. lt end
                local autochiuso = src:sub(i - 1, i - 1) == "/"
                local interno = src:sub(lt + 1 + #qnome, autochiuso and i - 2 or i - 1)
                local nome = nomeLocale(qnome)
                tok[#tok + 1] = {
                    t = (autochiuso or VUOTI[nome]) and "vuoto" or "apre",
                    s = lt, e = i, qnome = qnome, nome = nome, interno = interno,
                }
                pos = i + 1
            end
        end
    end
    return tok
end

--[[--
Costruisce l'albero degli elementi e dei nodi di testo.

Nodo elemento: { tipo = "el", nome, qnome, attr (lazy via M.attr), tok_apre, tok_chiude,
                 s (inizio tag apertura), e (fine tag chiusura), is (inizio contenuto),
                 ie (fine contenuto), figli = {}, padre }
Nodo testo:    { tipo = "testo", s, e, padre }

@return radice, numero di anomalie (tag non bilanciati), lista dei messaggi
]]
function M.albero(src, tok)
    local radice = { tipo = "radice", figli = {}, s = 1, e = #src }
    local pila = { radice }
    local anomalie, messaggi = 0, {}
    for i, t in ipairs(tok) do
        local cima = pila[#pila]
        if t.t == "apre" or t.t == "vuoto" then
            local el = {
                tipo = "el", nome = t.nome, qnome = t.qnome, interno = t.interno,
                tok_apre = i, s = t.s, is = t.e + 1, figli = {}, padre = cima,
            }
            cima.figli[#cima.figli + 1] = el
            if t.t == "apre" then
                pila[#pila + 1] = el
            else
                el.e, el.ie, el.vuoto = t.e, t.e, true
            end
        elseif t.t == "chiude" then
            if cima.tipo == "el" and cima.qnome == t.qnome then
                cima.tok_chiude, cima.ie, cima.e = i, t.s - 1, t.e
                pila[#pila] = nil
            elseif VUOTI[t.nome] then -- luacheck: ignore 542
                -- "<br></br>" è XML valido: la chiusura di un elemento vuoto si ignora
            else
                -- chiusura inattesa: cerchiamo un antenato con lo stesso nome
                anomalie = anomalie + 1
                local trovato
                for k = #pila, 2, -1 do
                    if pila[k].qnome == t.qnome then trovato = k break end
                end
                if trovato then
                    for k = #pila, trovato, -1 do
                        local el = pila[k]
                        el.ie, el.e = t.s - 1, t.e
                        if k == trovato then el.tok_chiude = i end
                        pila[k] = nil
                    end
                    messaggi[#messaggi + 1] = "chiusura </" .. t.qnome .. "> fuori posto al byte " .. t.s
                else
                    messaggi[#messaggi + 1] = "chiusura </" .. t.qnome .. "> senza apertura al byte " .. t.s
                end
            end
        elseif t.t == "testo" then
            cima.figli[#cima.figli + 1] = { tipo = "testo", s = t.s, e = t.e, padre = cima }
        end
        -- commenti, CDATA, PI e DOCTYPE non entrano nell'albero
    end
    if #pila > 1 then
        anomalie = anomalie + (#pila - 1)
        for k = #pila, 2, -1 do
            messaggi[#messaggi + 1] = "elemento <" .. pila[k].qnome .. "> non chiuso"
            pila[k].ie, pila[k].e = #src, #src
        end
    end
    return radice, anomalie, messaggi
end

--- Attributi di un nodo elemento (analizzati alla prima richiesta).
function M.attr(el)
    if not el.attr then el.attr = M.attributi(el.interno or "") end
    return el.attr
end

--- Analizza un sorgente e restituisce l'albero; nil e messaggio se il file è illeggibile.
function M.analizza(src)
    local tok, err = M.tokenizza(src)
    if not tok then return nil, err end
    local radice, anomalie, messaggi = M.albero(src, tok)
    return { radice = radice, token = tok, anomalie = anomalie, messaggi = messaggi, src = src }
end

--- Verifica che un documento sia ben formato quanto a bilanciamento dei tag.
function M.bilanciato(src)
    local doc, err = M.analizza(src)
    if not doc then return false, err end
    if doc.anomalie > 0 then return false, doc.messaggi[1] end
    return true
end

--- Primo discendente (in ordine di documento) con il nome locale dato.
function M.trova(nodo, nome)
    for _, f in ipairs(nodo.figli or {}) do
        if f.tipo == "el" then
            if f.nome == nome then return f end
            local r = M.trova(f, nome)
            if r then return r end
        end
    end
end

--- Tutti i discendenti che soddisfano un predicato.
function M.tutti(nodo, pred, out)
    out = out or {}
    for _, f in ipairs(nodo.figli or {}) do
        if f.tipo == "el" then
            if pred(f) then out[#out + 1] = f end
            M.tutti(f, pred, out)
        end
    end
    return out
end

--- Numero di riga (1-based) del byte `pos` nel sorgente.
function M.riga(src, pos)
    local _, n = src:sub(1, pos):gsub("\n", "")
    return n + 1
end

return M
