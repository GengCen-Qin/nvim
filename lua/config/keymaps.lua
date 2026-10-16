-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
--
--
local keymap = vim.keymap.set

-- 1. Ctrl + w: 关闭当前 Buffer (窗口)
-- 注意：在 Vim 中 <C-w> 默认是窗口操作前缀，这里我们将其映射为关闭当前 buffer
keymap("n", "<C-w>", "<cmd>bdelete<CR>", { desc = "Close current buffer" })

-- 2. Ctrl + c: 复制 (系统剪贴板)
-- 使用 "+y 复制到系统剪贴板，这样你可以粘贴到浏览器或其他软件
keymap("v", "<C-c>", '"+y', { desc = "Copy to system clipboard" })
keymap("n", "<C-c>", '"+yy', { desc = "Copy line to system clipboard" })

-- 3. Ctrl + v: 粘贴 (系统剪贴板)
-- 使用 "+p 从系统剪贴板粘贴
keymap("n", "<C-v>", '"+p', { desc = "Paste from system clipboard" })
keymap("i", "<C-v>", "<C-r>+", { desc = "Paste from system clipboard in insert mode" })

-- 4. Ctrl + s: 保存
keymap("n", "<C-s>", "<cmd>w<CR>", { desc = "Save file" })
keymap("i", "<C-s>", "<cmd>w<CR>", { desc = "Save file" })

-- 5. Ctrl + Alt + Left: 往回跳转 (Jump Back)
-- 对应 Sublime Text 的 "Jump Back"
keymap("n", "<C-M-Left>", "<C-o>", { desc = "Jump back" })

-- 6. Ctrl + Alt + Right: 往后跳转 (Jump Forward)
-- 对应 Sublime Text 的 "Jump Forward"
keymap("n", "<C-M-Right>", "<C-i>", { desc = "Jump forward" })

-- 7. Ctrl + d: 选中当前词并跳转到下一个同名匹配 (对应 Sublime Text 的 "Add Selection")
-- * = 搜索当前词的下一个匹配，gn = 把该匹配选中为 visual。重复按 <C-d> 会顺次选中后续同名匹配
keymap("n", "<C-d>", "*gn", { desc = "Select next occurrence of word (Ctrl+D)" })

-- 8. Ctrl + Enter: 向下插入一行并进入插入模式
-- 对应 Sublime Text 的 "Add Line Below"
keymap("n", "<C-CR>", "o<Esc>k", { desc = "Insert line below and enter insert mode" })
-- 解释：o 是向下新开一行并进入插入模式，<Esc>k 是为了确保光标停留在新行的开头（可选）
-- 如果你希望光标直接停在新行中间，可以简化为：
-- keymap("n", "<C-CR>", "o", { desc = "Insert line below" })
--
--

-- Ctrl + Shift + F: 全局搜索 (使用 Telescope 的 live_grep)
keymap("n", "<C-S-f>", "<cmd>Telescope live_grep<cr>", { desc = "Global Search (Live Grep)" })

-- u: 撤回 (Undo) —— nvim 内置，明示意图
keymap("n", "u", "u", { desc = "Undo" })

-- U: 反向撤回 (Redo)
-- 注意：会覆盖 nvim 内置 U（撤销当前行）。若想保留内置 U，请注释此行。
keymap("n", "U", "<C-r>", { desc = "Redo" })

-- 9. 复制当前文件路径到系统剪贴板
-- :CopyRelativePath 复制相对路径（相对 cwd，即 LazyVim 的 root/worktree）
-- :CopyAbsolutePath 复制绝对路径
local function copy_path(kind)
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    vim.notify("当前 buffer 没有文件路径", vim.log.levels.WARN)
    return
  end

  local abs = vim.fn.fnamemodify(path, ":p")
  local text = kind == "relative" and vim.fn.fnamemodify(abs, ":.") or abs
  -- 相对路径若落在 cwd 之外，fnamemodify 会原样返回绝对路径

  vim.fn.setreg("+", text)
  vim.notify("已复制" .. (kind == "relative" and "相对" or "绝对") .. "路径: " .. text)
end

vim.api.nvim_create_user_command("CopyRelativePath", function()
  copy_path("relative")
end, { desc = "复制当前文件相对路径到系统剪贴板" })

vim.api.nvim_create_user_command("CopyAbsolutePath", function()
  copy_path("absolute")
end, { desc = "复制当前文件绝对路径到系统剪贴板" })
