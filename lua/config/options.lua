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
-- 续行再额外缩进 2 位(在 breakindent 对齐基础上)，方便识别同一逻辑行
vim.opt.breakindentopt = "shift:2"
-- 续行行首加一个标记 ↳，一眼看出是折行下来的
vim.opt.showbreak = "↳ "

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

-- 设置初始缩放因子
vim.g.neovide_scale_factor = 1.0

-- 定义缩放函数
local change_scale_factor = function(delta)
  vim.g.neovide_scale_factor = vim.g.neovide_scale_factor * delta
end

-- 快捷键：Ctrl+= 放大，Ctrl+- 缩小
vim.keymap.set("n", "<C-=>", function()
  change_scale_factor(1.25)
end)
vim.keymap.set("n", "<C-->", function()
  change_scale_factor(1 / 1.25)
end)
-- 重置快捷键
vim.keymap.set("n", "<C-[>", function()
  vim.g.neovide_scale_factor = 1.0
end)
