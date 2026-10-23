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

-- Ruby：去掉 indentkeys 里会「每次输入就重排当前行」的部分触发符（. 和 :）。
-- 这两个符号让你在写方法链 / hash / 续行对齐时，敲一下当前行就被拉回
-- 基础缩进（常见症状：整行突然往前一个 tab）。保留块级触发（end/else/
-- when/({[/oO 等），正常换行、收尾自动缩进不受影响。
vim.api.nvim_create_autocmd("FileType", {
  pattern = "ruby",
  group = vim.api.nvim_create_augroup("RubyIndentKeys", { clear = true }),
  callback = function()
    -- 按逗号切段后剔除独立的 "." 和 ":"，其余（含 "=in " 等多字符触发）原样保留
    local keep = vim.tbl_filter(function(k)
      return k ~= "." and k ~= ":"
    end, vim.split(vim.bo.indentkeys, ",", { plain = true }))
    vim.bo.indentkeys = table.concat(keep, ",")
  end,
})
