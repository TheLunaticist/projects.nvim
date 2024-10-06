local M = {}

local DEFAULT_SETTINGS = {
    uiWidth = 80,
    uiHeight = 20,
}

function M.set(opts)
    M.ACTIVE = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULT_SETTINGS), opts)
    if M.ACTIVE.uiWidth < 80 then
    	vim.notify("[projects.nvim] uiWidth is too small (min >=80)", vim.log.levels.ERROR)
    elseif M.ACTIVE.uiHeight < 20 then
    	vim.notify("[projects.nvim] uiHeight is too small (min >=20)", vim.log.levels.ERROR)
    end
end

return M
