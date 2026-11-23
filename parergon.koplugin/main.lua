--[[--
Parergon — trasforma le annotazioni di un libro in modifiche permanenti
di una copia dell'EPUB, visibili in qualunque applicazione di lettura.

Copyright (C) 2026 Antonio Vigilante. Licenza AGPL-3.0 o successiva (vedi LICENSE).

FASE 4: crea la copia «Titolo (annotato).epub» con le evidenziazioni, le
sottolineature e le note del lettore tra parentesi quadre. L'originale e le sue
annotazioni non vengono toccati.

Interfaccia in inglese, con traduzione italiana (locales/it.po) attivabile dal menu
o automatica quando KOReader è in italiano.

Compatibilità: KOReader 2024.07 o successivo (serve il modulo ReaderAnnotation).
Moduli più recenti (ffi/archiver dalla 2025.08, ffi.loadlib dalla 2024.09) vengono
usati solo se presenti.

Copyright (C) 2026 — parergon.koplugin
Licenza: GNU AGPL v3 o successiva (vedi LICENSE).
]]

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InputDialog = require("ui/widget/inputdialog")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local _ = require("parergon/i18n")
local analisi = require("parergon/analisi")
local copia = require("parergon/copia")
local data = require("parergon/data")
local deflate = require("parergon/deflate")
local epub = require("parergon/epub")
local note = require("parergon/note")
local pacchetto = require("parergon/pacchetto")
local stile = require("parergon/stile")
local testo = require("parergon/testo")
local xpointer = require("parergon/xpointer")
local zip = require("parergon/zip")

-- Chiavi delle impostazioni globali.
local IMPOSTAZIONE_LINGUA = "parergon_language"   -- "auto", "en", "it"
local IMPOSTAZIONE_STILE = "parergon_style"       -- { forma, per_colore, colori }
local IMPOSTAZIONE_OPZIONI = "parergon_options"   -- finestra di consolidamento
local IMPOSTAZIONE_NOME = "parergon_reader_name"  -- nome per la nota di lettura

local Parergon = WidgetContainer:extend{
    name = "parergon",
    is_doc_only = true,
}

function Parergon:init()
    _.configura{
        modo = G_reader_settings:readSetting(IMPOSTAZIONE_LINGUA) or "auto",
        lingua_koreader = function() return G_reader_settings:readSetting("language") end,
    }
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

--[[--
Azione del Dispatcher: permette di associare il plugin a un gesto, a un tasto,
al menu rapido (Quick menu) o a un profilo. Visibile solo nei documenti
a scorrimento (sezione "rolling"), cioè quelli gestiti da crengine.
]]
function Parergon:onDispatcherRegisterActions()
    local ok, Dispatcher = pcall(require, "dispatcher")
    if not ok or type(Dispatcher) ~= "table" or not Dispatcher.registerAction then return end
    Dispatcher:registerAction("parergon_annotations", {
        category = "none",
        event = "ParergonAnnotations",
        title = _("Parergon: write annotations into the book"),
        rolling = true,
    })
end

--- Evento inviato dal Dispatcher (gesti, menu rapido).
function Parergon:onParergonAnnotations()
    if not self:isEpub() then
        UIManager:show(InfoMessage:new{ text = _("Parergon works only with EPUB books.") })
        return true
    end
    self:creaCopia()
    return true
end

--- Il libro aperto è un EPUB gestito da crengine?
function Parergon:isEpub()
    local file = self.ui.document and self.ui.document.file
    return self.ui.rolling ~= nil and type(file) == "string" and file:lower():match("%.epub$") ~= nil
end

-- ---------------------------------------------------------------------------
-- Impostazioni
-- ---------------------------------------------------------------------------

function Parergon:impostazioniStile()
    local imp = G_reader_settings:readSetting(IMPOSTAZIONE_STILE) or {}
    imp.forma = imp.forma or "koreader"
    imp.per_colore = imp.per_colore or {}
    imp.colori = imp.colori or "keep"
    imp.richiamo = imp.richiamo or "linea"
    return imp
end

function Parergon:salvaStile(imp)
    G_reader_settings:saveSetting(IMPOSTAZIONE_STILE, imp)
end

--- Nome leggibile di una forma.
local function nomeForma(codice)
    if codice == "koreader" then return _("As in KOReader") end
    if codice == "highlight" then return _("Highlight (background)") end
    if codice == "solid" then return _("Solid underline") end
    if codice == "dashed" then return _("Dashed underline") end
    if codice == "wavy" then return _("Wavy underline") end
    return codice
end

--- Nome leggibile di un colore di KOReader.
local function nomeColore(c)
    local nomi = {
        red = _("Red"), orange = _("Orange"), yellow = _("Yellow"), green = _("Green"),
        olive = _("Olive"), cyan = _("Cyan"), blue = _("Blue"), purple = _("Purple"), gray = _("Gray"),
    }
    return nomi[c] or c
end

--- Voci radio per scegliere una forma; `prima` è la voce "nessuna scelta" (o nil).
function Parergon:vociForma(leggi, scrivi, prima)
    local voci = {}
    local codici = { prima }
    for __, f in ipairs(stile.FORME) do codici[#codici + 1] = f end
    for __, codice in ipairs(codici) do
        voci[#voci + 1] = {
            text_func = function()
                if codice == "generale" then return _("Use the general setting") end
                return nomeForma(codice)
            end,
            checked_func = function() return leggi() == codice end,
            radio = true,
            callback = function() scrivi(codice) end,
        }
    end
    return voci
end

function Parergon:menuForma()
    return self:vociForma(
        function() return self:impostazioniStile().forma end,
        function(c) local imp = self:impostazioniStile() imp.forma = c self:salvaStile(imp) end,
        "koreader")
end

function Parergon:menuPerColore()
    local voci = {}
    for __, colore in ipairs(stile.ORDINE_COLORI) do
        voci[#voci + 1] = {
            text_func = function()
                local scelta = self:impostazioniStile().per_colore[colore]
                return nomeColore(colore) .. ": " .. (scelta and nomeForma(scelta) or _("general setting"))
            end,
            sub_item_table_func = function()
                return self:vociForma(
                    function() return self:impostazioniStile().per_colore[colore] or "generale" end,
                    function(c)
                        local imp = self:impostazioniStile()
                        imp.per_colore[colore] = c ~= "generale" and c or nil
                        self:salvaStile(imp)
                    end,
                    "generale")
            end,
        }
    end
    return voci
end

function Parergon:menuColori()
    local function voce(codice, testo_func)
        return {
            text_func = testo_func,
            checked_func = function() return self:impostazioniStile().colori == codice end,
            radio = true,
            callback = function() local imp = self:impostazioniStile() imp.colori = codice self:salvaStile(imp) end,
        }
    end
    return {
        voce("keep", function() return _("Keep KOReader colors") end),
        voce("gray", function() return _("Uniform gray (black and white screens)") end),
    }
end

--- Forma del richiamo [n] delle note a comparsa: in apice oppure sulla riga.
function Parergon:menuRichiamo()
    local function voce(codice, testo_func)
        return {
            text_func = testo_func,
            checked_func = function() return self:impostazioniStile().richiamo == codice end,
            radio = true,
            callback = function() local imp = self:impostazioniStile() imp.richiamo = codice self:salvaStile(imp) end,
        }
    end
    return {
        voce("linea", function() return _("On the line, larger [1]") end),
        voce("apice", function() return _("Superscript [1]") end),
    }
end

--- Sottomenu per scegliere la lingua del plugin.
function Parergon:menuLingua()
    local voci = {
        {
            text_func = function() return _("Automatic (same as KOReader)") end,
            checked_func = function() return _.modo == "auto" end,
            radio = true,
            callback = function() self:impostaLingua("auto") end,
        },
    }
    for __, l in ipairs(_.DISPONIBILI) do
        voci[#voci + 1] = {
            text = l[2], -- il nome di ogni lingua è scritto nella lingua stessa
            checked_func = function() return _.modo == l[1] end,
            radio = true,
            callback = function() self:impostaLingua(l[1]) end,
        }
    end
    return voci
end

function Parergon:impostaLingua(modo)
    G_reader_settings:saveSetting(IMPOSTAZIONE_LINGUA, modo)
    _.configura{ modo = modo }
end

function Parergon:addToMainMenu(menu_items)
    menu_items.parergon = {
        text = "Parergon",
        -- Prima pagina della scheda Strumenti, accanto a "Esporta evidenziazioni",
        -- invece che nascosta in "Altri strumenti".
        sorting_hint = "tools",
        sub_item_table = {
            {
                text_func = function() return _("Create consolidated copy…") end,
                enabled_func = function() return self:isEpub() end,
                callback = function() self:creaCopia() end,
            },
            {
                text_func = function() return _("Analyze annotations (changes nothing)") end,
                enabled_func = function() return self:isEpub() end,
                callback = function() self:avviaAnalisi() end,
                separator = true,
            },
            {
                text_func = function()
                    return _.trf("Highlight style: %s", nomeForma(self:impostazioniStile().forma))
                end,
                sub_item_table_func = function() return self:menuForma() end,
            },
            {
                text_func = function() return _("Style by color") end,
                sub_item_table_func = function() return self:menuPerColore() end,
            },
            {
                text_func = function() return _("Colors") end,
                sub_item_table_func = function() return self:menuColori() end,
            },
            {
                text_func = function() return _("Pop-up note reference") end,
                sub_item_table_func = function() return self:menuRichiamo() end,
                separator = true,
            },
            {
                text_func = function() return _("Language") end,
                sub_item_table_func = function() return self:menuLingua() end,
            },
        },
    }
end

-- ---------------------------------------------------------------------------
-- Lettura dell'EPUB originale (solo lettura)
-- ---------------------------------------------------------------------------

--[[--
Crea un lettore del contenuto dell'EPUB:
  - le voci non compresse si leggono direttamente dal file (zip.lua);
  - per quelle compresse si usa ffi/archiver (KOReader >= 2025.08) se disponibile,
    altrimenti crengine (document:getDocumentFileContent), presente in tutte le versioni.
]]
function Parergon:creaLettore(percorso)
    local arch, err = zip.apri(percorso)
    if not arch then return nil, err end
    local doc = self.ui.document
    local archiver_ok, Archiver = pcall(require, "ffi/archiver")
    local reader
    local lettore = { arch = arch }
    function lettore.leggi(nome)
        local v = arch.perNome[nome]
        if not v then return nil, _.trf("entry not found: %s", nome) end
        if v.metodo == 0 then return zip.datiGrezzi(arch, v) end
        if archiver_ok and type(Archiver) == "table" and Archiver.Reader then
            if reader == nil then
                reader = Archiver.Reader:new()
                if reader:open(percorso) then
                    for __ in reader:iterate() do end -- indicizza le voci
                else
                    reader = false
                end
            end
            if reader then
                local c = reader:extractToMemory(nome)
                if c then return c end
            end
        end
        local c = doc:getDocumentFileContent(nome)
        if c then return c end
        return nil, _.trf("cannot decompress %s", nome)
    end
    function lettore.chiudi()
        if reader then reader:close() end
    end
    return lettore
end

--- Testo da inizio blocco a pos0, calcolato da crengine (serve a disambiguare).
function Parergon:prefissoDaCrengine(x0, ann)
    local b = xpointer.indiceBlocco(x0.passi)
    local xp = "/body/DocFragment[" .. x0.frammento .. "]/body"
    for k = 1, b do
        xp = xp .. "/" .. x0.passi[k].nome .. "[" .. x0.passi[k].indice .. "]"
    end
    local doc = self.ui.document
    local ok, valido = pcall(doc.isXPointerInDocument, doc, xp)
    if not ok or not valido then return nil end
    local ok2, t = pcall(doc.getTextFromXPointers, doc, xp, ann.pos0)
    -- Che il carattere in pos0 sia incluso o no sposta la posizione di un solo
    -- carattere: rientra nella tolleranza di corrisp.TOLLERANZA.
    if ok2 and type(t) == "string" then return t end
end

--- Annotazioni del libro aperto, oppure nil se la versione di KOReader non è supportata.
function Parergon:annotazioni()
    local annotation = self.ui.annotation
    if not annotation or type(annotation.annotations) ~= "table" then return nil end
    -- Un'evidenziazione può avere il testo vuoto nel sidecar (visto su un libro reale: una
    -- selezione che comincia su un link in un titolo, con una nota). Il testo si chiede a
    -- crengine con le due posizioni, su una COPIA della voce: le annotazioni di KOReader
    -- non si toccano.
    local doc = self.ui.document
    local lista = {}
    for i, a in ipairs(annotation.annotations) do
        lista[i] = a
        if a.pos0 and a.pos1 and (type(a.text) ~= "string" or not a.text:match("%S"))
                and doc and doc.getTextFromXPointers then
            local ok, t = pcall(doc.getTextFromXPointers, doc, a.pos0, a.pos1)
            if ok and type(t) == "string" and t:match("%S") then
                local c = {}
                for k, v in pairs(a) do c[k] = v end
                c.text = t
                lista[i] = c
            end
        end
    end
    return lista
end

local MESSAGGIO_VERSIONE = function()
    return _("This KOReader version is not supported: version 2024.07 or later is required.")
end

--- Scrive un rapporto in DataStorage, utile per segnalare problemi.
local function salvaRapporto(contenuto)
    local percorso = DataStorage:getDataDir() .. "/parergon-report.txt"
    local f = io.open(percorso, "w")
    if not f then return nil end
    f:write(contenuto)
    f:close()
    return percorso
end

-- ---------------------------------------------------------------------------
-- Analisi (non modifica nulla)
-- ---------------------------------------------------------------------------

function Parergon:analizza()
    local annotazioni = self:annotazioni()
    if not annotazioni then return MESSAGGIO_VERSIONE() end
    local lettore, err = self:creaLettore(self.ui.document.file)
    if not lettore then return _.trf("Cannot read the EPUB: %s", tostring(err)) end
    local dom = self.ui.doc_settings:readSetting("cre_dom_version")
    local ris, aerr = analisi.analizza{
        lettore = lettore,
        annotazioni = annotazioni,
        versione_dom = dom,
        prefisso = function(x0, ann) return self:prefissoDaCrengine(x0, ann) end,
    }
    lettore.chiudi()
    if not ris then return _.trf("Invalid EPUB: %s", tostring(aerr)) end
    return analisi.rapporto(ris, dom)
end

function Parergon:avviaAnalisi()
    local attesa = InfoMessage:new{ text = _("Analyzing annotations…") }
    UIManager:show(attesa)
    UIManager:forceRePaint()
    local ok, rapporto = pcall(self.analizza, self)
    UIManager:close(attesa)
    if not ok then
        logger.err("parergon: errore durante l'analisi:", rapporto)
        rapporto = _("Unexpected error during the analysis:") .. "\n" .. tostring(rapporto)
    end
    local percorso = salvaRapporto(rapporto)
    if percorso then rapporto = rapporto .. "\n\n" .. _.trf("Report saved to: %s", percorso) end
    UIManager:show(TextViewer:new{
        title = _("Parergon — annotation analysis"),
        text = rapporto,
    })
end

-- ---------------------------------------------------------------------------
-- Copia consolidata
-- ---------------------------------------------------------------------------

local function esiste(percorso)
    local f = io.open(percorso, "rb")
    if f then f:close() return true end
    return false
end

local function nomeFile(percorso)
    return percorso:match("([^/\\]+)$") or percorso
end

--- Il libro aperto è già una copia prodotta da Parergon? (marcatore nell'OPF)
function Parergon:eCopiaParergon()
    local ok, risultato = pcall(function()
        local lettore = self:creaLettore(self.ui.document.file)
        if not lettore then return false end
        local libro = epub.leggi(lettore)
        lettore.chiudi()
        return libro and pacchetto.marcatore(libro) ~= nil
    end)
    return ok and risultato == true
end

--[[--
Annotazioni fatte direttamente su una copia già esistente (nel suo sidecar).
Andrebbero perse o fuori posto sostituendo la copia: lo diciamo prima.
]]
local function annotazioniProprie(percorso)
    local ok, n = pcall(function()
        local DocSettings = require("docsettings")
        if not DocSettings:hasSidecarFile(percorso) then return 0 end
        local a = DocSettings:open(percorso):readSetting("annotations")
        return type(a) == "table" and #a or 0
    end)
    return ok and n or 0
end

--- Primo passo: conferma, con il nome della copia e il numero di sottolineature.
function Parergon:creaCopia()
    local annotazioni = self:annotazioni()
    if not annotazioni then
        UIManager:show(InfoMessage:new{ text = MESSAGGIO_VERSIONE() })
        return
    end
    local n = #analisi.sottolineature(annotazioni)
    if n == 0 then
        UIManager:show(InfoMessage:new{ text = _("This book has no highlights to write into the text.") })
        return
    end
    if self:eCopiaParergon() then
        UIManager:show(ConfirmBox:new{
            text = _("This book is already an annotated copy made by Parergon.\n\nTo update it, annotate the original book and create the copy again from the original: the new copy will replace this one."),
            ok_text = _("Continue anyway"),
            ok_callback = function() self:confermaCopia(n) end,
        })
        return
    end
    self:confermaCopia(n)
end

--- Opzioni della finestra di consolidamento, ricordate fra un uso e l'altro.
function Parergon:opzioniCopia()
    local o = G_reader_settings:readSetting(IMPOSTAZIONE_OPZIONI) or {}
    if o.evidenziazioni == nil then o.evidenziazioni = true end
    if o.note == nil then o.note = true end
    o.filtro = o.filtro or "tutte"
    o.note_modo = o.note_modo or "testo"
    if o.corsivo == nil then o.corsivo = true end
    if o.indice == nil then o.indice = true end
    o.indice_criterio = o.indice_criterio or "tutte"
    o.indice_ordine = o.indice_ordine or "alfabetico"
    if o.indice_toc_sottotemi == nil then o.indice_toc_sottotemi = false end
    if o.lettore == nil then o.lettore = false end
    o.frase_lettore = nil -- la frase si compone ogni volta (contiene la data)
    return o
end

--[[--
Nota di lettura: chiede il nome la prima volta (poi lo ricorda), propone la frase
con mese e anno correnti e la lascia modificare per intero prima della scrittura.
@param alla_fine function(frase)
]]
function Parergon:chiediFraseLettore(alla_fine)
    local nome = G_reader_settings:readSetting(IMPOSTAZIONE_NOME)
    if not nome or nome == "" then
        local dialogo
        dialogo = InputDialog:new{
            title = _("Your name, for the reading note"),
            input = "",
            buttons = {{
                { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialogo) end },
                { text = _("OK"), is_enter_default = true, callback = function()
                    local n = dialogo:getInputText():match("^%s*(.-)%s*$")
                    UIManager:close(dialogo)
                    if n ~= "" then
                        G_reader_settings:saveSetting(IMPOSTAZIONE_NOME, n)
                        self:chiediFraseLettore(alla_fine)
                    end
                end },
            }},
        }
        UIManager:show(dialogo)
        dialogo:onShowKeyboard()
        return
    end
    local proposta = _.trf("Read and annotated by %s %s", nome, data.meseAnno(_.lingua()))
    local dialogo
    dialogo = InputDialog:new{
        title = _("Reading note on the title page"),
        input = proposta,
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialogo) end },
            { text = _("Change name"), callback = function()
                UIManager:close(dialogo)
                G_reader_settings:saveSetting(IMPOSTAZIONE_NOME, "")
                self:chiediFraseLettore(alla_fine)
            end },
            { text = _("OK"), is_enter_default = true, callback = function()
                local frase = dialogo:getInputText()
                UIManager:close(dialogo)
                if frase:match("%S") then alla_fine(frase) end
            end },
        }},
    }
    UIManager:show(dialogo)
    dialogo:onShowKeyboard()
end

--[[--
Finestra di consolidamento: che cosa scrivere nella copia e quali annotazioni usare.
Sobria per l'e-ink: ogni scelta chiude e riapre la finestra (un solo aggiornamento
dello schermo, nessuna animazione).
]]
function Parergon:confermaCopia(n)
    local destinazione = copia.percorsoCopia(self.ui.document.file, _("annotated"))
    local o = self:opzioniCopia()
    local con_nota = 0
    for __, el in ipairs(analisi.sottolineature(self:annotazioni())) do
        if not note.analizza(el.ann).vuota then con_nota = con_nota + 1 end
    end
    local finestra
    local function riapri(modifica)
        UIManager:close(finestra)
        modifica(o)
        G_reader_settings:saveSetting(IMPOSTAZIONE_OPZIONI, o)
        self:confermaCopia(n)
    end
    local function casella(attiva, etichetta) return (attiva and "☑ " or "☐ ") .. etichetta end
    local function scelta(attiva, etichetta) return (attiva and "◉ " or "○ ") .. etichetta end
    local nessuna = not o.evidenziazioni and not o.note and not o.indice and not o.lettore
    local pulsanti = {
        {{ text = casella(o.evidenziazioni, _("Highlights in the text")),
           callback = function() riapri(function(x) x.evidenziazioni = not x.evidenziazioni end) end }},
        {{ text = casella(o.note, _("Reader's notes")),
           callback = function() riapri(function(x) x.note = not x.note end) end }},
    }
    if o.note then
        -- come mostrare le note: nel testo [tra parentesi quadre] oppure a comparsa con un richiamo [1]
        pulsanti[#pulsanti + 1] = {
            { text = scelta(o.note_modo == "testo", _("In the text, in brackets")),
              callback = function() riapri(function(x) x.note_modo = "testo" end) end },
            { text = scelta(o.note_modo == "comparsa", _("Pop-up, with a reference [1]")),
              callback = function() riapri(function(x) x.note_modo = "comparsa" end) end },
        }
        if o.note_modo == "testo" then
            pulsanti[#pulsanti + 1] = {{ text = casella(o.corsivo, _("Notes in italics")),
                callback = function() riapri(function(x) x.corsivo = not x.corsivo end) end }}
        end
    end
    -- indice personale: quali voci e in che ordine i temi
    pulsanti[#pulsanti + 1] = {{ text = casella(o.indice, _("Personal index")),
        callback = function() riapri(function(x) x.indice = not x.indice end) end }}
    if o.indice then
        pulsanti[#pulsanti + 1] = {
            { text = scelta(o.indice_criterio == "tutte", _("All")),
              callback = function() riapri(function(x) x.indice_criterio = "tutte" end) end },
            { text = scelta(o.indice_criterio == "con_tema", _("With a #theme")),
              callback = function() riapri(function(x) x.indice_criterio = "con_tema" end) end },
            { text = scelta(o.indice_criterio == "con_nota", _("With a note")),
              callback = function() riapri(function(x) x.indice_criterio = "con_nota" end) end },
        }
        pulsanti[#pulsanti + 1] = {
            { text = scelta(o.indice_ordine == "alfabetico", _("Themes A–Z")),
              callback = function() riapri(function(x) x.indice_ordine = "alfabetico" end) end },
            { text = scelta(o.indice_ordine == "posizione", _("Themes in book order")),
              callback = function() riapri(function(x) x.indice_ordine = "posizione" end) end },
        }
        pulsanti[#pulsanti + 1] = {{ text = casella(o.indice_toc_sottotemi, _("Sub-themes in the table of contents")),
            callback = function() riapri(function(x) x.indice_toc_sottotemi = not x.indice_toc_sottotemi end) end }}
    end
    pulsanti[#pulsanti + 1] = {{ text = casella(o.lettore, _("Reading note on the title page")),
        callback = function() riapri(function(x) x.lettore = not x.lettore end) end }}
    pulsanti[#pulsanti + 1] = {
        { text = scelta(o.filtro == "tutte", _("All annotations")),
          callback = function() riapri(function(x) x.filtro = "tutte" end) end },
        { text = scelta(o.filtro == "con_nota", _("Only with a note")),
          callback = function() riapri(function(x) x.filtro = "con_nota" end) end },
    }
    pulsanti[#pulsanti + 1] = {
        { text = _("Cancel"), callback = function() UIManager:close(finestra) end },
        { text = _("Create"), enabled = not nessuna,
          callback = function()
              UIManager:close(finestra)
              if o.lettore then
                  self:chiediFraseLettore(function(frase)
                      o.frase_lettore = frase
                      self:verificaDestinazione(destinazione, o)
                  end)
              else
                  self:verificaDestinazione(destinazione, o)
              end
          end },
    }
    -- la finestra si crea dopo aver preparato tutte le righe: ButtonDialog le legge in init
    finestra = ButtonDialog:new{
        title = _.trf("Parergon will create a new book:\n%s\n\nHighlights in this book: %d (with a note: %d).\nThe original book and its annotations will not be modified.",
            nomeFile(destinazione), n, con_nota),
        buttons = pulsanti,
    }
    UIManager:show(finestra)
end

--- Se la copia esiste già, chiede se sostituirla (avvisando delle annotazioni proprie).
function Parergon:verificaDestinazione(destinazione, o)
    if not esiste(destinazione) then
        self:eseguiCopia(destinazione, o)
        return
    end
    local testo_conf = _.trf("A consolidated copy already exists:\n\n%s\n\nReplace it?", nomeFile(destinazione))
    local proprie = annotazioniProprie(destinazione)
    if proprie > 0 then
        testo_conf = testo_conf .. "\n\n" .. _.trf("Warning: the existing copy has %d annotations made directly on it. They are not part of the original and will not be kept in the new copy.", proprie)
    end
    UIManager:show(ConfirmBox:new{
        text = testo_conf,
        ok_text = _("Replace"),
        ok_callback = function() self:eseguiCopia(destinazione, o) end,
    })
end

--- Rapporto dettagliato: ogni annotazione saltata, con il passo e il motivo.
local function dettagli(rapporto)
    local righe = { copia.riepilogo(rapporto), "", _.trf("Copy: %s", rapporto.destinazione) }
    if #rapporto.saltate > 0 then
        righe[#righe + 1] = ""
        righe[#righe + 1] = _("Skipped highlights:")
        for i, s in ipairs(rapporto.saltate) do
            local passo, tronco = testo.primiCaratteri(testo.normalizza(s.ann.text), 60)
            righe[#righe + 1] = string.format("%d. «%s%s»%s", i, passo, tronco and "…" or "",
                s.ann.chapter and (" — " .. s.ann.chapter) or "")
            righe[#righe + 1] = "   " .. s.motivo
        end
    end
    return table.concat(righe, "\n")
end

--- Secondo passo: crea la copia e mostra il riepilogo.
function Parergon:eseguiCopia(destinazione, opzioni)
    local attesa = InfoMessage:new{ text = _("Creating the consolidated copy…") }
    UIManager:show(attesa)
    UIManager:forceRePaint()
    local ok, rapporto, err = pcall(function()
        local lettore, lerr = self:creaLettore(self.ui.document.file)
        if not lettore then return nil, lerr end
        local r, e = copia.crea{
            originale = self.ui.document.file,
            lettore = lettore,
            annotazioni = self:annotazioni(),
            versione_dom = self.ui.doc_settings:readSetting("cre_dom_version"),
            prefisso = function(x0, ann) return self:prefissoDaCrengine(x0, ann) end,
            imp = self:impostazioniStile(),
            destinazione = destinazione,
            comprimi = deflate.funzione(),
            suffisso = " (" .. _("annotated") .. ")",
            opzioni = opzioni or self:opzioniCopia(),
        }
        lettore.chiudi()
        return r, e
    end)
    UIManager:close(attesa)
    if not ok or not rapporto then
        local msg = ok and err or rapporto
        logger.err("parergon: copia non riuscita:", msg)
        UIManager:show(InfoMessage:new{ text = _.trf("The consolidated copy was not created:\n%s", tostring(msg)) })
        return
    end
    local testo_dettagli = dettagli(rapporto)
    salvaRapporto(testo_dettagli)
    UIManager:show(ConfirmBox:new{
        text = copia.riepilogo(rapporto) .. "\n\n" .. _("Open the consolidated copy now?"),
        ok_text = _("Open"),
        cancel_text = _("Close"),
        ok_callback = function() self.ui:switchDocument(destinazione) end,
        other_buttons = {{{
            text = _("Details"),
            callback = function()
                UIManager:show(TextViewer:new{ title = _("Parergon — consolidated copy"), text = testo_dettagli })
            end,
        }}},
    })
end

return Parergon
