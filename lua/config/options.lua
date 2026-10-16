-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
--
--
vim.opt.guifont = "Maple Mono NF CN:h16"
vim.opt.wrap = true -- 允许长行自动换行
vim.opt.linebreak = true -- 在单词边界处换行，而不是切断单词
vim.opt.breakindent = true -- 换行后保持缩进，看起来更整齐

-- 光标离窗口上下/左右边缘的留白（滚动到尽头时保留的余量行/列数）
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8

-- 数据库连接（vim-dadbod / vim-dadbod-ui）
-- 格式: postgresql://user:password@host:port/database
-- 密码中的特殊字符需百分号编码（+ -> %2B, * -> %2A）
--
-- 真实连接放在 ~/.config/nvim/db_connections.lua（已被 .gitignore 忽略，不进仓库）。
-- 从 db_connections.lua.example 复制一份并填入自己的连接即可。
-- 文件不存在时 vim.g.dbs 为空，dadbod 相关功能会提示未配置。
local ok, dbs = pcall(dofile, vim.fn.stdpath("config") .. "/db_connections.lua")
vim.g.dbs = (ok and type(dbs) == "table") and dbs or {}
