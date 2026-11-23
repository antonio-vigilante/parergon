--[[--
Riscrittura chirurgica dell'XHTML: inserisce testo in posizioni di byte precise
e lascia identico ogni altro byte del file.

Ogni modifica è una lista di "inserimenti" { pos, testo, peso }:
  pos   — il testo va inserito PRIMA del byte `pos` (pos = #src + 1 per la fine)
  peso  — ordine fra inserimenti nella stessa posizione: prima le chiusure
          (peso basso), poi le aperture, così due evidenziazioni adiacenti
          producono "</span><span ...>" e mai tag incrociati.

Modulo in Lua puro, testabile fuori dal dispositivo.

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local xmltok = require("parergon/xmltok")
local testo = require("parergon/testo")
local _ = require("parergon/i18n")

local M = {}

local PESO_CHIUSURA, PESO_APERTURA = 1, 2

--- Applica gli inserimenti a `src` e restituisce il nuovo testo.
function M.applica(src, inserimenti)
    table.sort(inserimenti, function(a, b)
        if a.pos ~= b.pos then return a.pos < b.pos end
        if a.peso ~= b.peso then return a.peso < b.peso end
        return (a.ordine or 0) < (b.ordine or 0)
    end)
    local pezzi, ultimo = {}, 1
    for __, ins in ipairs(inserimenti) do
        if ins.pos < ultimo then error("inserimenti sovrapposti alla posizione " .. ins.pos) end
        pezzi[#pezzi + 1] = src:sub(ultimo, ins.pos - 1)
        pezzi[#pezzi + 1] = ins.testo
        -- con `fino` l'inserimento sostituisce i byte pos..fino invece di aggiungere
        ultimo = ins.fino and (ins.fino + 1) or ins.pos
    end
    pezzi[#pezzi + 1] = src:sub(ultimo)
    return table.concat(pezzi)
end

--[[--
Inserimenti per avvolgere i segmenti di un'evidenziazione.
@param segmenti lista di { s, e } (byte inclusi), da corrisp.trova
@param classe classe CSS
@param id id da mettere sul primo segmento (facoltativo, servirà all'indice)
@param ordine numero progressivo (stabilizza l'ordinamento)
]]
function M.avvolgi(segmenti, classe, id, ordine)
    local ins = {}
    for k, s in ipairs(segmenti) do
        local apertura = '<span class="' .. classe .. '"'
        if k == 1 and id then apertura = apertura .. ' id="' .. id .. '"' end
        apertura = apertura .. ">"
        ins[#ins + 1] = { pos = s.s, testo = apertura, peso = PESO_APERTURA, ordine = ordine }
        ins[#ins + 1] = { pos = s.e + 1, testo = "</span>", peso = PESO_CHIUSURA, ordine = -ordine }
    end
    return ins
end

-- Elementi da cui la nota deve uscire: dentro un link diventerebbe parte del link,
-- dentro un esponente sarebbe minuscola e rialzata.
local DA_SCAVALCARE = { a = true, sup = true, sub = true, rt = true, ruby = true }

M.PESO_NOTA = 1.5 -- dopo la chiusura dell'evidenziazione, prima di un'apertura adiacente

--[[--
Posizione in cui inserire la nota: subito dopo l'ultimo carattere del passo,
oppure dopo il più esterno degli elementi in DA_SCAVALCARE che lo contengono.
Gli altri elementi in linea (corsivo, grassetto, span generici) non si scavalcano:
nei libri convertiti uno <span> avvolge spesso l'intero paragrafo, e la nota
finirebbe in fondo invece che accanto al passo.
@param esito risultato di corrisp.trova (segmenti, blocco)
@return posizione in byte (l'inserimento va prima di questo byte)
]]
function M.puntoNota(esito)
    local ultimo = esito.segmenti[#esito.segmenti]
    local pos = ultimo.e + 1
    local nodo = ultimo.nodo and ultimo.nodo.padre
    while nodo and nodo ~= esito.blocco and nodo.tipo == "el" do
        if DA_SCAVALCARE[nodo.nome] then pos = nodo.e + 1 end
        nodo = nodo.padre
    end
    return pos
end

--- Inserimento della nota (XHTML già pronto, vedi note.xhtml).
function M.nota(esito, xhtml, ordine)
    return {
        pos = M.puntoNota(esito),
        testo = ' <span class="parergon-note">' .. xhtml .. "</span>",
        peso = M.PESO_NOTA, ordine = ordine,
    }
end

--[[--
Richiamo [n] di una nota a comparsa: link EPUB 3 alla voce della pagina delle note.
KOReader riconosce epub:type="noteref" / role="doc-noteref" e mostra la nota in
una finestrella (cre.cpp, isLinkToFootnote: "Trust ... noteref").
@param numero numero della nota
@param href percorso relativo + "#id" della voce nella pagina delle note
@param id id del richiamo (destinazione del link di ritorno)
@param epub2 se vero, senza epub:type e role, che XHTML 1.1 non ammette. KOReader
       riconosce comunque il link come nota (cre.cpp, isLinkToFootnote): il testo è
       un numero, la destinazione ha un id e viene dopo nel libro.
]]
function M.richiamo(esito, numero, href, id, ordine, epub2)
    return {
        pos = M.puntoNota(esito),
        testo = '<a class="parergon-noteref" id="' .. id .. '" href="' .. testo.escapeXml(href) .. '"'
            .. (epub2 and "" or ' epub:type="noteref" role="doc-noteref"') .. ">[" .. numero .. "]</a>",
        peso = M.PESO_NOTA, ordine = ordine,
    }
end

--[[--
Dichiarazione del prefisso epub: sull'elemento <html>, se manca (XHTML EPUB 2).
Senza, l'attributo epub:type renderebbe il file XML non ben formato.
@return inserimento oppure nil se non serve
]]
function M.dichiaraEpub(doc)
    local html = xmltok.trova(doc.radice, "html")
    if not html or (html.interno or ""):find("xmlns:epub", 1, true) then return nil end
    -- subito dopo il nome del tag: "<html" + " xmlns:epub=..."
    return { pos = html.s + 1 + #html.qnome, testo = ' xmlns:epub="http://www.idpf.org/2007/ops"', peso = 2, ordine = 0 }
end

--[[--
Inserimento del collegamento al foglio di stile prima di </head>.
@param doc documento analizzato (xmltok.analizza)
@param href percorso relativo del CSS
@return inserimento, oppure nil e motivo
]]
function M.collegaCss(doc, href)
    local head = xmltok.trova(doc.radice, "head")
    local link = '<link rel="stylesheet" type="text/css" href="' .. testo.escapeXml(href) .. '"/>'
    if head and head.tok_chiude then
        -- subito prima di </head>; se </head> sta su una riga propria, il link
        -- prende una riga nuova con lo stesso rientro
        local inizio = head.ie + 1
        local rientro = doc.src:sub(1, inizio - 1):match("\n([ \t]*)$")
        local t = rientro and (link .. "\n" .. rientro) or link
        return { pos = inizio, testo = t, peso = PESO_APERTURA, ordine = 0 }
    end
    local html = xmltok.trova(doc.radice, "html")
    if html then
        return { pos = html.is, testo = "<head>" .. link .. "</head>", peso = PESO_APERTURA, ordine = 0 }
    end
    return nil, _("the file has no <head> or <html> element")
end

--[[--
Filtra le corrispondenze sovrapposte nello stesso file.
@param voci lista di { esito = risultato di corrisp.trova, ... }
@return accettate, scartate (ogni scartata riceve codice e motivo)
Le voci vengono considerate nell'ordine del testo. A parità di inizio vince la più lunga,
poi la prima: nei sidecar reali lo stesso passo può comparire molte volte, con la stessa
data e fini via via più avanti (KOReader 2026, «La scuola inclusiva ha fallito», 18 copie),
e tenere la più corta lascerebbe sottolineata solo una parte del passo.
Una voce tutta dentro una già accettata è "contenuta"; una che la supera è "sovrapposta".
]]
function M.senzaSovrapposizioni(voci)
    table.sort(voci, function(a, b)
        if a.esito.inizio ~= b.esito.inizio then return a.esito.inizio < b.esito.inizio end
        if a.esito.fine ~= b.esito.fine then return a.esito.fine > b.esito.fine end
        return (a.ordine or 0) < (b.ordine or 0)
    end)
    local accettate, scartate, fine = {}, {}, 0
    for __, v in ipairs(voci) do
        if v.esito.inizio <= fine then
            if v.esito.fine <= fine then
                v.codice = "contenuta"
                v.motivo = _("lies inside another highlight")
                v.contenitore = accettate[#accettate] -- quella che la contiene
            else
                v.codice = "sovrapposta"
                v.motivo = _("overlaps another highlight")
            end
            scartate[#scartate + 1] = v
        else
            accettate[#accettate + 1] = v
            fine = v.esito.fine
        end
    end
    return accettate, scartate
end

--[[--
Verifica che la riscrittura non abbia peggiorato la struttura del file.
@return true, oppure false e messaggio
]]
function M.verifica(prima, dopo)
    local d0 = xmltok.analizza(prima)
    local d1, err = xmltok.analizza(dopo)
    if not d1 then return false, err end
    if d1.anomalie > (d0 and d0.anomalie or 0) then
        return false, d1.messaggi[1] or _("unbalanced tags")
    end
    return true
end

return M
