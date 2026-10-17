-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- 遇到残留 swap 文件时自动选择 "(E)dit anyway"，不再弹 E325 提示
vim.api.nvim_create_autocmd("SwapExists", {
  pattern = "*",
  group = vim.api.nvim_create_augroup("AlwaysEditSwap", {}),
  callback = function()
    vim.v.swapchoice = "e"
  end,
})

-- I18n 可见化：把 I18n.t('key') 的译文内联渲染在代码后面（默认 en），
-- 光标落到那行时恢复原样。实现见 lua/i18n-preview.lua。
require("i18n-preview").setup()

-- 窗口右上角悬浮显示当前文件名（<leader>uN 开关）。实现见 lua/float-filename.lua。
require("float-filename").setup()
