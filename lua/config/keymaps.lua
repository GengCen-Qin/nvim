-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
--
--
local keymap = vim.keymap.set

-- 1. Ctrl + w: 关闭当前 Buffer (窗口)
-- 注意：在 Vim 中 <C-w> 默认是窗口操作前缀，这里我们将其映射为关闭当前 buffer
keymap("n", "<C-w>", "<cmd>bdelete<CR>", { desc = "Close current buffer" })

-- 1.1. space + w + w: 关闭当前 Buffer
keymap("n", "<leader>ww", "<cmd>bdelete<CR>", { desc = "Close current buffer" })

-- 1.1.1. space + w + a / space + b + a: 关闭所有 Buffer (含当前)
for _, lhs in ipairs({ "<leader>wa", "<leader>ba" }) do
  keymap("n", lhs, function()
    Snacks.bufdelete.all()
  end, { desc = "Close all buffers" })
end

-- 1.2. Ctrl + a: 全选整个 buffer (进入 Visual 模式)
-- 覆盖 nvim 内置 <C-a>(数字 +1)；gg 到首行，V 进入行可视，G 选到末行
keymap({ "n", "v", "x" }, "<C-a>", "ggVG", { desc = "Select all (visual mode)" })

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

-- 7. space + n: 搜索光标下的单词并跳转到下一个匹配位置
-- * = 用光标下的单词作为搜索词（高亮全部匹配）并跳到下一个，之后用 n / N 继续前后查找
-- 注意：覆盖了 LazyVim 默认的 <leader>n（通知历史），需要通知历史用 :messages
keymap("n", "<leader>n", "*", { desc = "Search word under cursor & jump to next (then n/N)" })

-- 7.1. space + shift + n: 搜索光标下的单词并跳转到上一个匹配位置
-- # = 与 * 相同，但反向查找（跳到上一个匹配），之后用 n / N 继续前后查找
keymap("n", "<leader>N", "#", { desc = "Search word under cursor & jump to prev (then n/N)" })

-- 8. Ctrl + Enter: 向下插入一行并进入插入模式
-- 对应 Sublime Text 的 "Add Line Below"
keymap("n", "<C-CR>", "o<Esc>k", { desc = "Insert line below and enter insert mode" })
-- 解释：o 是向下新开一行并进入插入模式，<Esc>k 是为了确保光标停留在新行的开头（可选）
-- 如果你希望光标直接停在新行中间，可以简化为：
-- keymap("n", "<C-CR>", "o", { desc = "Insert line below" })
--
--

-- space + /: 全局搜索（字面匹配，非正则），比 LazyVim 默认的 <leader>sg 少按一次
-- 与 <leader><leader> 等键位统一走 snacks.picker，exclude 只在 snacks.lua 维护一处
keymap("n", "<leader>/", function()
  Snacks.picker.grep({ regex = false })
end, { desc = "Global Search (literal)" })

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

-- 注意：<leader>cr / <leader>ca 原本被 LSP 占用（Rename / Code Action），这里按需求覆盖为复制路径
keymap("n", "<leader>cr", "<cmd>CopyRelativePath<CR>", { desc = "Copy relative path" })
keymap("n", "<leader>ca", "<cmd>CopyAbsolutePath<CR>", { desc = "Copy absolute path" })

-- LazyVim 在 LspAttach 时用 buffer 局部键位设了 <leader>cr(Rename)/<leader>ca(Code Action)，
-- 会盖掉上面的全局绑定。本文件在 VeryLazy 加载，注册的 autocmd 晚于 LazyVim，故在其之后生效。
-- 10. Copy text object to system clipboard
-- ss: copy word under cursor (y i w)
keymap("n", "ss", '"+yiw', { desc = "Copy word under cursor" })

-- sw: copy inside quotes (single or double)
-- Determines the quote char on the cursor line: prefers being inside a
-- quote-pair (last opening quote behind the cursor), else the nearest
-- pair boundary, else defaults to double quotes.
keymap("n", "sw", function()
  local line = vim.api.nvim_get_current_line()
  local p = vim.api.nvim_win_get_cursor(0)[2] + 1 -- 1-based cursor position

  local regions, open = {}, nil
  for i = 1, #line do
    local ch = line:sub(i, i)
    if ch == '"' or ch == "'" then
      if open then
        regions[#regions + 1] = { open = open, close = i, quote = line:sub(open, open) }
        open = nil
      else
        open = i
      end
    end
  end

  -- inside a pair: the last opening quote behind the cursor is the region
  local quote
  for _, r in ipairs(regions) do
    if p > r.open and p < r.close then
      quote = r.quote
    end
  end

  if not quote then
    local best, bestd
    for _, r in ipairs(regions) do
      local d = math.min(math.abs(p - r.open), math.abs(p - r.close))
      if not bestd or d < bestd then best, bestd = r, d end
    end
    quote = best and best.quote or '"'
  end

  local ok = pcall(vim.cmd.normal, { '"+yi' .. quote, bang = true })
  if not ok then
    vim.notify("No " .. quote .. " quoted text found", vim.log.levels.WARN)
  end
end, { desc = "Copy inside quotes" })

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    keymap("n", "<leader>cr", "<cmd>CopyRelativePath<CR>", { buffer = args.buf, desc = "Copy relative path" })
    keymap("n", "<leader>ca", "<cmd>CopyAbsolutePath<CR>", { buffer = args.buf, desc = "Copy absolute path" })
  end,
})

-- 11. Ctrl + /: toggle comment (built-in gcc / gc, no plugin needed)
-- Most terminals send <C-_> (0x1F) for Ctrl+/; terminals speaking the kitty
-- keyboard protocol send a real <C-/>. Bind both so the key works everywhere.
-- Only n/x modes: t-mode <C-/> (LazyVim: hide terminal) is left alone.
for _, lhs in ipairs({ "<C-/>", "<C-_>" }) do
  keymap("n", lhs, "gcc", { remap = true, desc = "Toggle comment line" })
  keymap("x", lhs, "gc", { remap = true, desc = "Toggle comment" })
end

-- 12. space + k + <1..3>: 按层级折叠 / 展开
-- 依赖 options.lua 的 foldmethod=indent；折叠层级由 foldlevel 控制，数字越大展开越多
for _, lvl in ipairs({ 1, 2, 3 }) do
  keymap("n", "<leader>k" .. lvl, function()
    vim.o.foldlevel = lvl
    -- 折叠层级变化时同步刷新，否则若 showcmd 停在 0 附近会保留旧 fold column 状态
    vim.cmd.normal({ "zx", bang = true })
  end, { desc = "Fold to level " .. lvl })
end

-- 13. 功能键：直接复用已有键位，避免逻辑重复维护
-- F1: lazygit（等价 <leader>gg，root 目录）
if vim.fn.executable("lazygit") == 1 then
  keymap("n", "<F1>", function()
    Snacks.lazygit({ cwd = LazyVim.root.git() })
  end, { desc = "Lazygit (Root Dir)" })
end

-- F2: 转发 <leader>bb（当前被 plugins/git-review.lua 覆盖为 Git Review）
-- F3: 转发 <leader>fq（见 plugins/dadbod-schema.lua，新建 SQL buffer）
keymap("n", "<F2>", "<leader>bb", { remap = true, desc = "Git Review" })
keymap("n", "<F3>", "<leader>fq", { remap = true, desc = "DB: 新建 SQL buffer" })
