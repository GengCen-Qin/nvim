-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
--
--
vim.opt.guifont = "Maple Mono NF CN:h16"
vim.opt.wrap = true -- 允许长行自动换行
-- 关闭 linebreak：它只在单词边界(空格/标点)折行，遇到超长 URL/base64/连续
-- 字符串这种无空格内容时整行不折、横向滚动，看起来像 wrap 失效。关掉后
-- 长连续内容也会硬折行；配合 breakindent 折行后仍缩进对齐。
vim.opt.linebreak = false
vim.opt.breakindent = true -- 换行后保持缩进，看起来更整齐

-- 光标离窗口上下/左右边缘的留白（滚动到尽头时保留的余量行/列数）
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8

-- 关闭 nvim 内置 sqlcomplete 的默认按键映射（<Left>/<Right> 会绑到
-- sqlcomplete#DrillIntoTable 等函数；这东西被 LazyVim 以 g:loaded_sql_completion=true
-- 屏蔽后函数不存在，一按左右就报 E117。这里直接用官方开关去掉整套默认映射，
-- 数据库补全交给 vim-dadbod-completion/blink）。
vim.g.omni_sql_no_default_maps = true

-- 数据库连接（vim-dadbod / vim-dadbod-ui）
-- 格式: postgresql://user:password@host:port/database
-- 密码中的特殊字符需百分号编码（+ -> %2B, * -> %2A）
--
-- 真实连接放在 ~/.config/nvim/db_connections.lua（已被 .gitignore 忽略，不进仓库）。
-- 从 db_connections.lua.example 复制一份并填入自己的连接即可。
-- 文件不存在时 vim.g.dbs 为空，dadbod 相关功能会提示未配置。
local ok, dbs = pcall(dofile, vim.fn.stdpath("config") .. "/db_connections.lua")
vim.g.dbs = (ok and type(dbs) == "table") and dbs or {}
