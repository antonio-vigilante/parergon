--[[--
Corrispondenza fra un'annotazione (XPointer + testo) e un intervallo di byte nell'XHTML sorgente.

Strategia:
  1. dal percorso dell'XPointer si individua il blocco (paragrafo) nel file;
  2. si confronta il testo dell'annotazione con il testo del blocco, dopo aver
     normalizzato entrambi (spazi, entità, trattini morbidi);
  3. se il testo compare più volte, si sceglie l'occorrenza più vicina alla
     posizione indicata dall'XPointer (o dal testo che precede, fornito da crengine);
  4. se il percorso non porta a nulla, si cerca nell'intero file, accettando
     solo una corrispondenza unica;
  5. in ogni altro caso l'annotazione viene saltata con un motivo.

Il risultato contiene i "segmenti": uno per ogni nodo di testo attraversato.
Avvolgere ciascun segmento separatamente mantiene l'XHTML ben formato anche
quando il passo contiene elementi in linea (corsivi, grassetti, link...).

Modulo in Lua puro, testabile fuori dal dispositivo.

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local testo = require("parergon/testo")
local xpointer = require("parergon/xpointer")
local xmltok = require("parergon/xmltok")
local _ = require("parergon/i18n")

local M = {}

-- Elementi il cui contenuto non è testo leggibile.
local NON_TESTO = { script = true, style = true, head = true, title = true }

-- Distanza massima (in caratteri) tra la posizione attesa e l'occorrenza scelta,
-- quando il testo compare più volte nel paragrafo.
M.TOLLERANZA = 12

--- Raccoglie i nodi di testo discendenti di `nodo`, in ordine di documento.
local function raccogliTesti(nodo, out)
    for __, f in ipairs(nodo.figli) do
        if f.tipo == "testo" then
            out[#out + 1] = { s = f.s, e = f.e, nodo = f }
        elseif f.tipo == "el" and not NON_TESTO[f.nome] then
            if f.nome == "br" then
                -- <br/> diventa un a capo nel testo di crengine: nel confronto vale uno spazio
                out[#out + 1] = { s = f.s, e = f.e, nodo = f, spazio = true }
            end
            raccogliTesti(f, out)
        end
    end
    return out
end
M.raccogliTesti = raccogliTesti

--- Testo normalizzato (con mappa) di un nodo.
function M.testoNodo(src, nodo)
    return testo.normalizzaFrammenti(src, raccogliTesti(nodo, {}))
end

--- Trova l'elemento <body> del documento.
function M.body(doc)
    return xmltok.trova(doc.radice, "body")
end

--- Figlio elemento numero `indice` (1-based) con nome `nome`.
local function figlioElemento(nodo, nome, indice)
    local c = 0
    for __, f in ipairs(nodo.figli) do
        if f.tipo == "el" and f.nome == nome then
            c = c + 1
            if c == indice then return f end
        end
    end
end

--- Segue i passi `passi[1..fino]` partendo da `nodo`.
function M.segui(nodo, passi, fino)
    for k = 1, fino or #passi do
        nodo = figlioElemento(nodo, passi[k].nome, passi[k].indice)
        if not nodo then return nil, k end
    end
    return nodo
end

--- Restituisce true se il nodo di testo è fatto solo di spazi.
local function soloSpazi(src, t)
    return src:sub(t.s, t.e):match("^[ \t\r\n]*$") ~= nil
end

--[[--
Nodo di testo numero k di un elemento, contato come fa crengine: il primo figlio
di soli spazi di un elemento viene scartato da crengine (lvtinydom.cpp,
ldomElementWriter::onText), quindi non conta.
]]
local function testoK(src, el, k)
    local c, primo = 0, true
    for __, f in ipairs(el.figli) do
        if f.tipo == "testo" then
            if not (primo and soloSpazi(src, f)) then
                c = c + 1
                if c == k then return f end
            end
        end
        primo = false
    end
end

--- Posizione attesa (indice di carattere nel blocco) ricavata dall'XPointer.
local function posizioneDaXPointer(src, blocco, norm, xp, iBlocco)
    -- i passi fino a iBlocco ci hanno portato al blocco: seguiamo i successivi
    local el = blocco
    for k = iBlocco + 1, #xp.passi do
        el = figlioElemento(el, xp.passi[k].nome, xp.passi[k].indice)
        if not el then return nil end
    end
    if not xp.testo then
        -- XPointer su un elemento: usiamo il suo primo carattere di testo
        for __, f in ipairs(raccogliTesti(el, {})) do
            if norm.inizioNodo[f.nodo] then return norm.inizioNodo[f.nodo] end
        end
        return nil
    end
    local t = testoK(src, el, xp.testo)
    if not t then return nil end
    local inizio = norm.inizioNodo[t]
    if not inizio then return nil end
    return inizio + (xp.offset or 0)
end

--- Segmenti (uno per nodo di testo) che coprono i caratteri da..a del testo normalizzato.
local function segmenti(norm, da, a)
    local seg, ultimo = {}, nil
    for k = da, a do
        local nodo = norm.nodo[k]
        if nodo.tipo ~= "testo" then
            -- spazio sintetico di un <br/>: non si avvolge, il tag resta fuori
            ultimo = nil
        elseif nodo ~= ultimo then
            seg[#seg + 1] = { s = norm.cs[k], e = norm.ce[k], nodo = nodo }
            ultimo = nodo
        else
            seg[#seg].e = norm.ce[k]
        end
    end
    return seg
end

--- Contesto leggibile attorno al passo trovato (per il rapporto).
local function contesto(norm, da, a)
    local function sotto(i, j)
        local t = {}
        local n = 0
        local s = norm.testo
        -- ricostruisce i caratteri da i a j usando byte2car inverso
        for b = 1, #s do
            local k = norm.byte2car[b]
            if k then
                n = k
                if k >= i and k <= j then
                    t[#t + 1] = s:sub(b, b + testo.lunghezzaUtf8(s:byte(b)) - 1)
                end
            end
        end
        return table.concat(t), n
    end
    local prima = sotto(math.max(1, da - 30), da - 1)
    local passo = sotto(da, a)
    local dopo = sotto(a + 1, math.min(norm.n, a + 30))
    return prima, passo, dopo
end

--- Sceglie fra più occorrenze quella più vicina a `attesa`.
local function scegli(occ, attesa)
    if #occ == 1 then return occ[1], "unica" end
    if not attesa then return nil, "ambiguo" end
    local migliore, d1, d2 = nil, math.huge, math.huge
    for __, o in ipairs(occ) do
        local d = math.abs(o.da - attesa)
        if d < d1 then migliore, d2, d1 = o, d1, d
        elseif d < d2 then d2 = d end
    end
    if d1 <= M.TOLLERANZA and d2 > d1 then
        return migliore, "scelta per posizione"
    end
    return nil, "ambiguo"
end

--- Posizione attesa dell'inizio del passo (indice di carattere dall'inizio di `blocco`).
local function posizioneAttesa(src, blocco, norm, x0, b0, opzioni)
    if opzioni.prefisso then
        -- lunghezza del testo che precede la selezione, normalizzato come il blocco
        local pref = testo.normalizza(opzioni.prefisso, false):gsub("^ +", "")
        local attesa = testo.lunghezza(pref) + 1
        -- il blocco può iniziare con uno spazio compresso
        if norm.testo:sub(1, 1) == " " then attesa = attesa + 1 end
        return attesa
    end
    return posizioneDaXPointer(src, blocco, norm, x0, b0)
end

--- Blocco più vicino che contiene il nodo (il nodo stesso, se è un blocco).
local function bloccoDi(nodo)
    while nodo and not (nodo.tipo == "el" and xpointer.BLOCCHI[nodo.nome]) do nodo = nodo.padre end
    return nodo
end

--- true se l'elemento ha blocchi fra i figli diretti (un contenitore, non un paragrafo).
local function contieneBlocchi(el)
    for __, f in ipairs(el.figli) do
        if f.tipo == "el" and xpointer.BLOCCHI[f.nome] then return true end
    end
    return false
end

--[[--
Passo che attraversa più paragrafi dello stesso file. Si prende il testo che va dal
paragrafo di pos0 a quello di pos1, compresi i blocchi in mezzo (titoli inclusi),
con uno spazio fra un blocco e l'altro: crengine separa i blocchi con un a capo
(getRangeText), che la normalizzazione rende uno spazio. Gli spazi fra un blocco e
l'altro non si avvolgono: uno <span> fra </p> e <p>, o fra due <li>, non sarebbe valido.
Il passo deve cominciare nel primo paragrafo e finire nell'ultimo. Se compare più volte,
si sceglie come nel caso di un solo paragrafo. Non si cerca nel resto del file.
]]
function M.trovaMulti(src, body, ann, ago, x0, x1, b0, b1, opzioni, successo)
    local primo = M.segui(body, x0.passi, b0)
    local ultimo = M.segui(body, x1.passi, b1)
    if not primo or not ultimo then
        return { ok = false, codice = "paragrafi",
            motivo = _("spans more than one paragraph, and the paragraphs were not found"), multi = true }
    end
    if ultimo.s < primo.s then
        return { ok = false, codice = "paragrafi",
            motivo = _("spans more than one paragraph, in an unexpected order"), multi = true }
    end
    -- i frammenti di testo da primo a ultimo, con un separatore a ogni cambio di blocco
    local frammenti, blocco_prec = {}, nil
    local fineA, inizioB -- indici dei frammenti: ultimo del primo blocco, primo dell'ultimo
    for __, f in ipairs(raccogliTesti(body, {})) do
        if f.s >= primo.s and f.e <= ultimo.e then
            local padre = f.nodo.padre
            local tra_blocchi = f.nodo.tipo == "testo" and soloSpazi(src, f.nodo)
                and padre and padre.tipo == "el" and contieneBlocchi(padre)
            if not tra_blocchi then
                local b = bloccoDi(f.nodo.tipo == "testo" and padre or f.nodo)
                if blocco_prec and b ~= blocco_prec then
                    frammenti[#frammenti + 1] = { s = f.s, e = f.s, nodo = { tipo = "separatore" }, spazio = true }
                end
                blocco_prec = b
                frammenti[#frammenti + 1] = f
                local in_primo = f.s >= primo.s and f.e <= primo.e
                local in_ultimo = f.s >= ultimo.s and f.e <= ultimo.e
                if in_primo then fineA = #frammenti end
                if in_ultimo and not inizioB then inizioB = #frammenti end
            end
        end
    end
    if not fineA or not inizioB then
        return { ok = false, codice = "assente", motivo = _("text not found in the paragraph") }
    end
    local norm = testo.normalizzaFrammenti(src, frammenti)
    -- confini in caratteri: il passo comincia entro il primo blocco e finisce nell'ultimo
    local car_inizioB = norm.inizioNodo[frammenti[inizioB].nodo]
    local car_fineA = (frammenti[fineA + 1] and norm.inizioNodo[frammenti[fineA + 1].nodo] or norm.n + 1) - 1
    local occ = {}
    for __, o in ipairs(testo.trovaOccorrenze(norm, ago)) do
        if o.da <= car_fineA and o.a >= car_inizioB then occ[#occ + 1] = o end
    end
    if #occ == 0 then
        if ann.text_edited then
            return { ok = false, codice = "modificato", motivo = _("the highlighted text was edited in KOReader") }
        end
        return { ok = false, codice = "assente", motivo = _("text not found in the paragraphs") }
    end
    local scelta, come = scegli(occ, posizioneAttesa(src, primo, norm, x0, b0, opzioni))
    if not scelta then
        return { ok = false, codice = "ambiguo",
            motivo = _.trf("the text appears %d times in the paragraphs and the position is uncertain", #occ) }
    end
    local r = successo(ultimo, norm, scelta, come == "unica" and _("path, text confirmed across paragraphs")
        or _("path, text confirmed across paragraphs and chosen by position"), false)
    r.multi = true
    r.percorso = xpointer.percorso(x0.passi, b0) .. " → " .. xpointer.percorso(x1.passi, b1)
    return r
end

--[[--
Cerca la corrispondenza di un'annotazione in un file XHTML già analizzato.

@param doc     risultato di xmltok.analizza
@param ann     tabella { pos0 = xp, pos1 = xp, text = testo sottolineato, text_edited = bool }
@param opzioni { prefisso = testo che precede pos0 nel blocco, se calcolato da crengine }
@return tabella risultato: in caso di successo
          { ok = true, segmenti, inizio, fine, blocco, metodo, riga, percorso,
            prima, passo, dopo }
        altrimenti { ok = false, codice (fisso, per test e riepiloghi), motivo (tradotto) }
]]
function M.trova(doc, ann, opzioni)
    opzioni = opzioni or {}
    local src = doc.src
    local x0, err0 = xpointer.analizza(ann.pos0)
    local x1, err1 = xpointer.analizza(ann.pos1)
    if not x0 or not x1 then
        return { ok = false, codice = "indirizzo", motivo = _.trf("invalid position (%s)", err0 or err1) }
    end
    if x0.frammento ~= x1.frammento then
        return { ok = false, codice = "capitoli", motivo = _("spans more than one chapter (different files)"), multi = true }
    end
    local b0, b1 = xpointer.indiceBlocco(x0.passi), xpointer.indiceBlocco(x1.passi)

    local ago = testo.normalizza(ann.text)
    if ago == "" then
        return { ok = false, codice = "vuoto", motivo = _("the highlighted text is empty") }
    end

    local body = M.body(doc)
    if not body then return { ok = false, codice = "body", motivo = _("the file has no <body>") } end

    local function successo(blocco, norm, occ, metodo, ricerca)
        local prima, passo, dopo = contesto(norm, occ.da, occ.a)
        local seg = segmenti(norm, occ.da, occ.a)
        return {
            ok = true, segmenti = seg, blocco = blocco, metodo = metodo, ricerca = ricerca == true,
            inizio = seg[1].s, fine = seg[#seg].e,
            riga = xmltok.riga(src, seg[1].s),
            percorso = xpointer.percorso(x0.passi, b0),
            prima = prima, passo = passo, dopo = dopo,
        }
    end

    if xpointer.percorso(x0.passi, b0) ~= xpointer.percorso(x1.passi, b1) then
        return M.trovaMulti(src, body, ann, ago, x0, x1, b0, b1, opzioni, successo)
    end

    -- 1. percorso
    local blocco = M.segui(body, x0.passi, b0)
    if blocco then
        local norm = M.testoNodo(src, blocco)
        local occ = testo.trovaOccorrenze(norm, ago)
        if #occ > 0 then
            local attesa = posizioneAttesa(src, blocco, norm, x0, b0, opzioni)
            local scelta, come = scegli(occ, attesa)
            if scelta then
                local metodo = come == "unica" and _("path, text confirmed")
                                                or _("path, text confirmed and chosen by position")
                return successo(blocco, norm, scelta, metodo, false)
            end
            return { ok = false, codice = "ambiguo", motivo = _.trf("the text appears %d times in the paragraph and the position is uncertain", #occ) }
        end
    end

    -- 2. ricerca nell'intero file (solo se la corrispondenza è unica)
    local blocchi = xmltok.tutti(body, function(el)
        if not xpointer.BLOCCHI[el.nome] then return false end
        -- solo i blocchi "foglia": senza altri blocchi dentro
        for __, f in ipairs(el.figli) do
            if f.tipo == "el" and xpointer.BLOCCHI[f.nome] then return false end
        end
        return true
    end)
    local trovati = {}
    for __, b in ipairs(blocchi) do
        local norm = M.testoNodo(src, b)
        for __, o in ipairs(testo.trovaOccorrenze(norm, ago)) do
            trovati[#trovati + 1] = { blocco = b, norm = norm, occ = o }
        end
    end
    if #trovati == 1 then
        local t = trovati[1]
        return successo(t.blocco, t.norm, t.occ,
            blocco and _("search in the file (text not in the indicated paragraph)")
                    or _("search in the file (path not found)"), true)
    end
    if #trovati > 1 then
        return { ok = false, codice = "ambiguo", motivo = _.trf("unreliable path, and the text appears %d times in the chapter", #trovati) }
    end
    if ann.text_edited then
        return { ok = false, codice = "modificato", motivo = _("the highlighted text was edited in KOReader") }
    end
    return { ok = false, codice = "assente", motivo = blocco and _("text not found in the paragraph") or _("path not found and text missing") }
end

return M
