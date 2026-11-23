--[[
Simulazione minima di KOReader per caricare main.lua fuori dal dispositivo.

Sostituisce i moduli dell'interfaccia (UIManager, InfoMessage, ConfirmBox,
TextViewer...) con finti oggetti che registrano cosa viene mostrato, e fornisce
un documento finto basato sull'EPUB di prova. Verifica che main.lua si carichi,
registri menu e azione, esegua l'analisi e crei la copia consolidata.
Non sostituisce la prova sul dispositivo.

Uso: luajit test/simula_koreader.lua
]]

package.path = "parergon.koplugin/?.lua;test/?.lua;" .. package.path

-- impostazioni globali di KOReader (finte)
local impostazioni = { language = "en_US" }
G_reader_settings = { -- luacheck: ignore
    readSetting = function(_, k) return impostazioni[k] end,
    saveSetting = function(_, k, v) impostazioni[k] = v end,
}

local mostrati = {}
local function modulo(nome, valore) package.loaded[nome] = valore end

local Widget = {}
function Widget:extend(o) o = o or {} setmetatable(o, { __index = self }) return o end
function Widget:new(o) o = o or {} setmetatable(o, { __index = self }) if o.init then o:init() end return o end

modulo("gettext", function(s) return s end)
modulo("logger", { err = print, warn = print, info = function() end, dbg = function() end })
modulo("datastorage", { getDataDir = function() return "test/uscita" end })
modulo("ui/widget/container/widgetcontainer", Widget)
local azioni = {}
modulo("dispatcher", { registerAction = function(_, nome, v) azioni[nome] = v end })
modulo("ui/widget/infomessage", Widget:extend{ tipo = "InfoMessage" })
modulo("ui/widget/confirmbox", Widget:extend{ tipo = "ConfirmBox" })
modulo("ui/widget/buttondialog", Widget:extend{ tipo = "ButtonDialog" })
modulo("ui/widget/inputdialog", Widget:extend{
    tipo = "InputDialog",
    getInputText = function(self) return self.input end,
    onShowKeyboard = function() end,
})
modulo("ui/widget/textviewer", Widget:extend{ tipo = "TextViewer" })
modulo("ui/uimanager", {
    show = function(_, w) mostrati[#mostrati + 1] = w end,
    close = function() end,
    forceRePaint = function() end,
})
-- sidecar finti: la copia esistente ha 3 annotazioni proprie
modulo("docsettings", {
    hasSidecarFile = function(_, p) return p:find("(annotated)", 1, true) ~= nil end,
    open = function() return { readSetting = function(_, k) if k == "annotations" then return { {}, {}, {} } end end } end,
})
-- ffi/archiver non esiste fuori da KOReader: il plugin deve funzionare lo stesso
package.preload["ffi/archiver"] = function() error("modulo non disponibile") end

os.execute(package.config:sub(1, 1) == "\\" and 'mkdir "test\\uscita" 2>nul' or "mkdir -p test/uscita")
-- l'originale viene copiato in test/uscita, così la copia consolidata nasce lì
local function copiaFile(da, a)
    local f = assert(io.open(da, "rb")) local s = f:read("*a") f:close()
    f = assert(io.open(a, "wb")) f:write(s) f:close()
end
local libro = "test/uscita/Simulazione.epub"
copiaFile("test/libro-prova-store.epub", libro)

local prove = require("annotazioni_prova")
local menu_items = {}
local aperto
local ui = {
    rolling = {},
    annotation = { annotations = prove },
    doc_settings = { readSetting = function(_, k) if k == "cre_dom_version" then return 20260812 end end },
    menu = { registerToMainMenu = function(_, plugin) plugin:addToMainMenu(menu_items) end },
    switchDocument = function(_, f) aperto = f end,
    document = {
        file = libro,
        getDocumentFileContent = function() return nil end,
        isXPointerInDocument = function() return true end,
        -- crengine non c'è: simuliamo l'assenza del prefisso
        getTextFromXPointers = function() return nil end,
    },
}

--- Voce del menu Parergon il cui testo (in inglese) inizia con `inizio`.
local function voce(inizio)
    for __, v in ipairs(menu_items.parergon.sub_item_table) do
        local t = v.text_func and v.text_func() or v.text
        if t:sub(1, #inizio) == inizio then return v end
    end
    error("voce di menu assente: " .. inizio)
end

local Parergon = dofile("parergon.koplugin/main.lua")
local plugin = Parergon:new{ ui = ui }
assert(menu_items.parergon, "voce di menu non registrata")
assert(menu_items.parergon.sorting_hint == "tools", "la voce deve stare nella scheda Strumenti")
assert(azioni.parergon_annotations and azioni.parergon_annotations.rolling, "azione del Dispatcher non registrata")
assert(voce("Create consolidated copy").enabled_func(), "la creazione deve essere attiva per un EPUB")
print("menu Strumenti e azione del Dispatcher: ok")

-- analisi
mostrati = {}
voce("Analyze annotations").callback()
local viewer = mostrati[#mostrati]
assert(viewer and viewer.tipo == "TextViewer", "il rapporto non è stato mostrato")
assert(viewer.text:find("Certain matches: 14", 1, true), "rapporto inatteso:\n" .. viewer.text)
print("analisi: ok")

-- impostazioni di stile dal menu
local forme = voce("Highlight style").sub_item_table_func()
forme[3].callback() -- "Solid underline"
assert(impostazioni.parergon_style.forma == "solid", "forma generale non salvata")
assert(voce("Highlight style").text_func() == "Highlight style: Solid underline", "testo della voce non aggiornato")
forme[1].callback() -- di nuovo "As in KOReader"
local perColore = voce("Style by color").sub_item_table_func()
assert(#perColore == 9, "nove colori nel menu")
perColore[9].sub_item_table_func()[5].callback() -- Grigio → zigzag
assert(impostazioni.parergon_style.per_colore.gray == "wavy", "mappatura per colore non salvata")
assert(perColore[9].text_func() == "Gray: Wavy underline", "testo della mappatura")
perColore[9].sub_item_table_func()[1].callback() -- Grigio → impostazione generale
assert(impostazioni.parergon_style.per_colore.gray == nil, "mappatura non rimossa")
print("impostazioni di stile: ok")

--- Pulsante di una finestra ButtonDialog il cui testo contiene `parte`.
local function pulsante(finestra, parte)
    for __, riga in ipairs(finestra.buttons) do
        for __, b in ipairs(riga) do
            if b.text:find(parte, 1, true) then return b end
        end
    end
    error("pulsante assente: " .. parte)
end

-- finestra di consolidamento: opzioni → creazione → riepilogo → apertura
mostrati = {}
voce("Create consolidated copy").callback()
local finestra = mostrati[#mostrati]
assert(finestra.tipo == "ButtonDialog" and finestra.title:find("Simulazione (annotated).epub", 1, true),
    "finestra di consolidamento inattesa")
assert(finestra.title:find("Highlights in this book: 18 (with a note: 2)", 1, true), "conteggi inattesi:\n" .. finestra.title)
assert(pulsante(finestra, "Highlights in the text").text:sub(1, 3) == "☑", "evidenziazioni attive per default")
-- disattiva e riattiva le note: la finestra si riapre con la casella aggiornata
pulsante(finestra, "Reader's notes").callback()
finestra = mostrati[#mostrati]
assert(pulsante(finestra, "Reader's notes").text:sub(1, 3) == "☐", "le note devono risultare disattivate")
assert(impostazioni.parergon_options.note == false, "scelta non ricordata")
pulsante(finestra, "Reader's notes").callback()
finestra = mostrati[#mostrati]
-- note a comparsa: la riga del corsivo sparisce, la scelta è ricordata
pulsante(finestra, "Pop-up, with a reference").callback()
finestra = mostrati[#mostrati]
assert(impostazioni.parergon_options.note_modo == "comparsa", "modo delle note non ricordato")
assert(not pcall(pulsante, finestra, "Notes in italics"), "il corsivo non vale per le note a comparsa")
pulsante(finestra, "In the text, in brackets").callback()
finestra = mostrati[#mostrati]
assert(pulsante(finestra, "Notes in italics").text:sub(1, 3) == "☑", "corsivo attivo per default")
-- senza evidenziazioni, note, indice e nota di lettura "Create" è disattivato
pulsante(finestra, "Highlights in the text").callback()
pulsante(mostrati[#mostrati], "Reader's notes").callback()
pulsante(mostrati[#mostrati], "Personal index").callback()
assert(pulsante(mostrati[#mostrati], "Create").enabled == false, "Create deve essere disattivato senza contenuti")
pulsante(mostrati[#mostrati], "Highlights in the text").callback()
pulsante(mostrati[#mostrati], "Reader's notes").callback()
pulsante(mostrati[#mostrati], "Personal index").callback()
finestra = mostrati[#mostrati]
os.remove("test/uscita/Simulazione (annotated).epub")
pulsante(finestra, "Create").callback()
local fine = mostrati[#mostrati]
assert(fine.tipo == "ConfirmBox", "riepilogo non mostrato: " .. tostring(fine.text))
assert(fine.text:find("Highlights written into the copy: 14", 1, true), "riepilogo inatteso:\n" .. fine.text)
assert(fine.text:find("Notes written into the text: 2", 1, true), "note nel riepilogo:\n" .. fine.text)
fine.ok_callback()
assert(aperto == "test/uscita/Simulazione (annotated).epub", "la copia non viene aperta")
print("finestra di consolidamento, copia creata e aperta: ok")
local r = os.execute('python test/verifica_epub.py "test/uscita/Simulazione (annotated).epub"')
assert(r == 0 or r == true, "la copia creata dall'interfaccia non supera la verifica")

-- seconda creazione: deve chiedere se sostituire
mostrati = {}
voce("Create consolidated copy").callback()
pulsante(mostrati[#mostrati], "Create").callback()
assert(mostrati[#mostrati].text:find("already exists", 1, true), "manca la richiesta di sostituzione")
assert(mostrati[#mostrati].text:find("has 3 annotations made directly on it", 1, true),
    "manca l'avviso sulle annotazioni proprie della copia")
print("richiesta di sostituzione con avviso: ok")

-- nota di lettura: nome chiesto la prima volta, frase proposta e modificabile
mostrati = {}
voce("Create consolidated copy").callback()
pulsante(mostrati[#mostrati], "Reading note on the title page").callback()
finestra = mostrati[#mostrati]
assert(pulsante(finestra, "Reading note on the title page").text:sub(1, 3) == "☑", "nota di lettura attivata")
assert(pulsante(finestra, "Personal index").text:sub(1, 3) == "☑", "indice personale attivo per default")
os.remove("test/uscita/Simulazione (annotated).epub")
pulsante(finestra, "Create").callback()
local chiedi = mostrati[#mostrati]
assert(chiedi.tipo == "InputDialog" and chiedi.title:find("Your name", 1, true), "manca la richiesta del nome")
chiedi.input = "Maria Rossi"
chiedi.buttons[1][2].callback()
assert(impostazioni.parergon_reader_name == "Maria Rossi", "nome non ricordato")
local frase = mostrati[#mostrati]
assert(frase.tipo == "InputDialog" and frase.input:find("^Read and annotated by Maria Rossi in %a+ %d%d%d%d$"),
    "frase proposta inattesa: " .. tostring(frase.input))
frase.input = "Letto e annotato da Maria Rossi, in treno."
frase.buttons[1][3].callback()
local fine2 = mostrati[#mostrati]
assert(fine2.tipo == "ConfirmBox" and fine2.text:find("Reading note: added to the title page", 1, true),
    "riepilogo senza nota di lettura:\n" .. tostring(fine2.text))
assert(fine2.text:find("Personal index: 14 entries", 1, true),
    "riepilogo senza indice:\n" .. fine2.text)
local r2 = os.execute('python test/verifica_epub.py "test/uscita/Simulazione (annotated).epub"')
assert(r2 == 0 or r2 == true, "la copia con indice e nota di lettura non supera la verifica")
-- la seconda volta il nome non viene più chiesto
mostrati = {}
voce("Create consolidated copy").callback()
pulsante(mostrati[#mostrati], "Create").callback()
assert(mostrati[#mostrati].title == "Reading note on the title page", "il nome non deve essere richiesto di nuovo")
-- spegne la nota di lettura per i passi successivi
mostrati = {}
voce("Create consolidated copy").callback()
pulsante(mostrati[#mostrati], "Reading note on the title page").callback()
print("indice personale e nota di lettura dall'interfaccia: ok")

-- aprire la copia e chiedere di consolidarla: avviso
ui.document.file = "test/uscita/Simulazione (annotated).epub"
mostrati = {}
voce("Create consolidated copy").callback()
assert(mostrati[#mostrati].text:find("already an annotated copy", 1, true), "manca l'avviso sulla copia")
print("avviso su copia già annotata: ok")
ui.document.file = libro

-- versione di KOReader senza ReaderAnnotation
mostrati = {}
ui.annotation = nil
plugin:avviaAnalisi()
assert(mostrati[#mostrati].text:find("2024.07", 1, true), "messaggio di versione non supportata assente")
print("versione non supportata: messaggio corretto")

-- passaggio all'italiano dal menu Lingua
ui.annotation = { annotations = prove }
local lingue = voce("Language").sub_item_table_func()
assert(lingue[3].text == "Italiano", "la terza voce del menu Lingua deve essere Italiano")
lingue[3].callback()
assert(impostazioni.parergon_language == "it", "la lingua scelta deve essere salvata")
assert(menu_items.parergon.sub_item_table[2].text_func() == "Analizza le annotazioni (non modifica nulla)",
    "il menu deve passare all'italiano")
mostrati = {}
plugin:avviaAnalisi()
assert(mostrati[#mostrati].text:find("Corrispondenze certe: 14", 1, true), "rapporto non tradotto")
mostrati = {}
plugin:creaCopia()
assert(mostrati[#mostrati].title:find("Simulazione (annotato).epub", 1, true), "nome della copia non tradotto")
print("lingua italiana dal menu: ok")
os.remove("test/uscita/parergon-report.txt")

-- evidenziazione con il testo vuoto nel sidecar (visto su un libro reale): il testo
-- si chiede a crengine, su una copia della voce
do
    local C1x = "/body/DocFragment[3]/body/section[1]/"
    local vuota = { drawer = "lighten", text = "", note = "Nota da non perdere",
        pos0 = C1x .. "p[1]/text()[1].48", pos1 = C1x .. "p[1]/text()[1].68" }
    ui.annotation = { annotations = { vuota } }
    local prima = ui.document.getTextFromXPointers
    ui.document.getTextFromXPointers = function(_, p0, p1)
        if p0 == vuota.pos0 and p1 == vuota.pos1 then return "per una selva oscura" end
    end
    local lista = plugin:annotazioni()
    assert(lista[1].text == "per una selva oscura", "il testo vuoto deve essere chiesto a crengine")
    assert(vuota.text == "", "l'annotazione di KOReader non deve cambiare")
    assert(lista[1].note == "Nota da non perdere", "la copia conserva la nota")
    ui.document.getTextFromXPointers = prima
    ui.annotation = { annotations = prove }
    print("testo vuoto recuperato da crengine: ok")
end
