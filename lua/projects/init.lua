local settings = require("projects.settings")

local M = {}

--[constants]
local SELECTION_NAMESPACE = vim.api.nvim_create_namespace("nvim.projects.selection")
local TITLE_NAMESPACE = vim.api.nvim_create_namespace("nvim.projects.title")

local TITLE = " projects.nvim "

local DISPLAY_NAME = "[projects.nvim]"
local CACHE_NAME = "nvim.projects.cache"

--ui layout
local LEFT_BORDER = 2
local SECTION_SPACING = 2
local NUM_SECTIONS = 2

--[setup]
vim.api.nvim_set_hl(0, "nvim.projects.title", {
    fg = "black",
    bg = "#44D62C",
})

--[state]
local uiBuf --ui buffer
local pData --project data
local lastWindow

--[util]
local function getSelectionIndex()
    local cursorPos = vim.api.nvim_win_get_cursor(0)
    local entryNum = cursorPos[1] - 1
    return entryNum
end

local function getSelectionData()
    return pData[getSelectionIndex()]
end

local function getMaxEntryNum()
    return settings.ACTIVE.uiHeight - 2
end

--[main]
local function populateBuffer() --populate the buffer with the current data
    local innerWidth = settings.ACTIVE.uiWidth - 2 * LEFT_BORDER - (NUM_SECTIONS - 1) * SECTION_SPACING
    local sectionSize = math.floor(innerWidth / NUM_SECTIONS)

    local bufferLineArray = {}

    --title
    local titleWhitespace = settings.ACTIVE.uiWidth - #TITLE
    table.insert(bufferLineArray, string.rep(" ", titleWhitespace / 2) .. TITLE)

    if #pData ~= 0 then
        local iterations = math.min(#pData, getMaxEntryNum())
        for i = 1, iterations do
            local entry = pData[i]
            --section 1
            local sec1 = string.sub(entry.name, 1, sectionSize) --cutting string to size
            sec1 = sec1 .. string.rep(" ", sectionSize - #sec1) --filling section

            --section 2
            local sec2 = string.sub(entry.path, 1, sectionSize)

            local line = string.rep(" ", LEFT_BORDER) .. sec1 .. string.rep(" ", SECTION_SPACING) .. sec2
            table.insert(bufferLineArray, line)
        end
    else
        table.insert(bufferLineArray, string.rep(" ", settings.ACTIVE.uiWidth))
    end

    --bottom line for looping to work
    table.insert(bufferLineArray, string.rep(" ", settings.ACTIVE.uiWidth))

    vim.bo[uiBuf].modifiable = true
    vim.api.nvim_buf_set_lines(uiBuf, 0, -1, false, bufferLineArray)
    vim.bo[uiBuf].modifiable = false

    --title highlighting
    vim.api.nvim_buf_clear_namespace(uiBuf, TITLE_NAMESPACE, 0, -1)
    local titleStart = math.floor((settings.ACTIVE.uiWidth - #TITLE) / 2)
    vim.api.nvim_buf_set_extmark(uiBuf, TITLE_NAMESPACE, 0, titleStart, {
        end_col = titleStart + #TITLE,
        hl_group = "nvim.projects.title",
        strict = false,
    })
end

local function loadData()
    local data = {}
    local ok, fLines = pcall(vim.fn.readfile, vim.fn.stdpath("cache") .. "/" .. CACHE_NAME)
    if ok == true then
	data = vim.fn.json_decode(fLines)
    end
    pData = data
end

local function saveData()
    local encoded = vim.fn.json_encode(pData)
    print(encoded)
    local ok, e = pcall(vim.fn.writefile, { encoded }, vim.fn.stdpath("cache") .. "/" .. CACHE_NAME, "b")
    print(ok, e)
end

local function createBuffer()
    local buf = vim.api.nvim_create_buf(false, true) --TODO make unlisted for release

    vim.bo[buf].bufhidden = "hide" --TODO change for release

    --closing the window
    local function closeWindow()
        vim.api.nvim_win_close(lastWindow, true)
    end
    vim.keymap.set("n", "q", closeWindow, {
        buffer = buf,
    })
    vim.keymap.set("n", "<esc>", closeWindow, {
        buffer = buf,
    })

    --unsetting keys
    vim.keymap.set("n", "<leader>p", "", {
        buffer = buf,
    })

    --selecting entry & remapping enter key
    local function selectEntry(openExplorer)
        local entry = getSelectionData()
        local path = vim.fs.normalize(entry.path)
        if vim.fn.isdirectory(path) == 1 then
            vim.api.nvim_set_current_dir(path)
            vim.api.nvim_win_close(lastWindow, true)
            --try open telescope-file-explorer
            if openExplorer then
                local ok = pcall(require, "telescope._extensions.file_browser")
                if ok then
                    require("telescope").extensions.file_browser.file_browser({
                        initial_mode = "normal",
                        hide_parent_dir = true,
                    })
                end
            end
        else
            vim.notify(
                '[projects.nvim] "' .. entry.path .. "\" doesn't seem to be a real directory.",
                vim.log.levels.WARN
            )
        end
    end
    vim.keymap.set("n", "<cr>", function()
        selectEntry(false)
    end, {
        buffer = buf,
    })
    vim.keymap.set("n", "p", function()
        selectEntry(false)
    end, {
        buffer = buf,
    })
    vim.keymap.set("n", "P", function()
        selectEntry(true)
    end, {
        buffer = buf,
    })

    --adding entry
    local function add(dataIndex)
        local name = vim.fn.input("Project Name: ")
        if name == "" then
            return
        end

        local path = vim.fn.input("Path: ")
        if path == "" then
            return
        end

        table.insert(pData, dataIndex, { name = name, path = path })

	saveData()

        populateBuffer()
    end
    local function add_above()
        add(getSelectionIndex())
    end
    local function add_below()
        add(getSelectionIndex() + 1)
    end
    vim.keymap.set("n", "i", add_above, {
        buffer = buf,
    })
    vim.keymap.set("n", "o", add_below, {
        buffer = buf,
    })
    vim.keymap.set("n", "O", add_above, {
        buffer = buf,
    })

    --deleting entry
    local function delete()
        local entry = getSelectionData()

        local answer = vim.fn.input(DISPLAY_NAME .. ' Delete entry "' .. entry.name .. '"? (y/n): ')
        if answer == "y" or answer == "Y" then
            table.remove(pData, getSelectionIndex())
            populateBuffer()
        end
    end
    vim.keymap.set("n", "d", delete, {
        buffer = buf,
    })

    --highlighting current line and limiting movement
    vim.api.nvim_create_autocmd("CursorMoved", {
        buffer = buf,
        callback = function()
            --looping cursor around buffer
            vim.api.nvim_buf_clear_namespace(buf, SELECTION_NAMESPACE, 0, -1)
            local initialPos = vim.api.nvim_win_get_cursor(0)
            if #pData > 0 then
                if initialPos[1] == 1 then
                    vim.fn.cursor(#pData + 1, initialPos[2] + 1)
                elseif initialPos[1] == #pData + 2 then
                    vim.fn.cursor(2, initialPos[2] + 1)
                end
            else
                vim.fn.cursor(2, initialPos[2] + 1)
            end
            --marking current line
            vim.api.nvim_buf_add_highlight(
                buf,
                SELECTION_NAMESPACE,
                "Visual",
                vim.api.nvim_win_get_cursor(0)[1] - 1,
                2,
                settings.ACTIVE.uiWidth - 2
            )
        end,
    })

    --closing window when exiting buffer
    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = buf,
        callback = function()
            vim.api.nvim_win_close(lastWindow, true)
        end,
    })

    uiBuf = buf
end

M.setup = function(opts)
    settings.set(opts)

    createBuffer()
    loadData()
    populateBuffer()
end

M.spawnDialogue = function()
    --setting hl to line 1
    vim.api.nvim_buf_clear_namespace(uiBuf, SELECTION_NAMESPACE, 0, -1)
    vim.api.nvim_buf_add_highlight(uiBuf, SELECTION_NAMESPACE, "Visual", 1, 2, settings.ACTIVE.uiWidth - 2) --pre selecting first line

    local width = settings.ACTIVE.uiWidth
    local height = settings.ACTIVE.uiHeight

    lastWindow = vim.api.nvim_open_win(uiBuf, true, {
        relative = "editor",
        width = width,
        height = height,
        col = vim.o.columns / 2 - width / 2,
        row = vim.o.lines / 2 - height / 2,
        style = "minimal",
    })

    vim.fn.cursor(2, 3) --first character first entry
end

return M
