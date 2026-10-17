-- 在窗口右上角悬浮显示当前文件名
--
--   <leader>uN   开/关悬浮文件名
--
-- 每个普通窗口（非浮窗）右上角贴一个无焦点的小浮窗，内容为「文件图标 + 相对路径
-- + 修改标记」，随 buffer 切换 / 保存 / 修改 / 分屏 / 缩放自动刷新。
-- 浮窗不抢焦点、不进窗口跳转，半透明（winblend）所以看起来是悬浮的。
--
-- 注意：浮窗贴在文本区第一行右上角，会遮住首行末尾一点内容（半透明）。
-- 不想要时 <leader>uN 关掉即可。
local M = {}

local ns = vim.api.nvim_create_namespace("float_filename")
local augroup = vim.api.nvim_create_augroup("FloatFilename", { clear = true })

-- win -> { win = 浮窗, buf = 浮窗 buffer, text = 上次内容 }
local floats = {}
local enabled = true
local max_width = 50 -- 浮窗最大列宽（含图标与内边距）

local function icon_for(name, ft)
  local ok, mini = pcall(require, "mini.icons")
  if ok then
    local icon, hl = mini.get("file", name ~= "" and name or ft)
    return icon or "", hl
  end
  return "", nil
end

local function label(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local name = vim.api.nvim_buf_get_name(buf)
  local ft = vim.bo[buf].filetype
  if name == "" then
    return (ft ~= "" and "[" .. ft .. "]" or "[No Name]"), nil, 0
  end
  -- 相对 cwd 的路径；太长时从左侧截断，保留文件名部分
  local rel = vim.fn.fnamemodify(name, ":.")
  if vim.fn.strchars(rel) > max_width - 6 then
    rel = "…" .. vim.fn.strcharpart(rel, vim.fn.strchars(rel) - (max_width - 7), max_width - 7)
  end
  local icon, hl = icon_for(name, ft)
  local mod = vim.bo[buf].modified and " ●" or ""
  return icon .. " " .. rel .. mod, hl, vim.fn.strchars(icon)
end

local function is_normal_win(win)
  return vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == ""
end

-- nvim-treesitter-context 把「当前类/函数」固定在窗口顶部（relative=win, row=0，
-- zindex 默认 20，横跨整行），会盖住贴在同一位置的悬浮文件名。它给自己的浮窗打了
-- w:treesitter_context 标记，这里据此算出它占用的行数，把文件名浮窗挪到它下方。
local function context_offset(win)
  local offset = 0
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= win and vim.api.nvim_win_is_valid(w) then
      local cfg = vim.api.nvim_win_get_config(w)
      if cfg.relative == "win" and cfg.win == win and vim.w[w].treesitter_context then
        -- 上下文浮窗固定顶在 row=0，底边即 row + height
        offset = math.max(offset, (cfg.row or 0) + (cfg.height or 0))
      end
    end
  end
  return offset
end

local function close(win)
  local f = floats[win]
  if not f then
    return
  end
  floats[win] = nil
  if vim.api.nvim_win_is_valid(f.win) then
    vim.api.nvim_win_close(f.win, true)
  end
  if vim.api.nvim_buf_is_valid(f.buf) then
    vim.api.nvim_buf_delete(f.buf, { force = true })
  end
end

function M.close_all()
  for win in pairs(floats) do
    close(win)
  end
end

function M.refresh(win)
  if not enabled or not is_normal_win(win) then
    return
  end
  -- 浮窗里不显示（比如 lazy / which-key / picker）
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return
  end
  local text, hl, icon_len = label(win)
  local width = vim.api.nvim_strwidth(text) + 2
  local win_width = vim.api.nvim_win_get_width(win)
  -- 有 treesitter-context 固定在顶部时下移，避免被盖住
  local top = context_offset(win)
  if win_width < 30 or width > win_width - 2 then
    close(win)
    return
  end

  local f = floats[win]
  if not f or not vim.api.nvim_win_is_valid(f.win) then
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    local fwin = vim.api.nvim_open_win(buf, false, {
      relative = "win",
      win = win,
      anchor = "NE",
      row = top,
      col = win_width - 1,
      width = width,
      height = 1,
      style = "minimal",
      border = "rounded",
      focusable = false,
      noautocmd = true,
      -- 高于 treesitter-context 的浮窗（默认 20），低于 lazy / picker / which-key
      -- 等常规浮窗（默认 50）：这样既不会被上下文固定行盖住，也不会盖住这些 UI
      zindex = 25,
    })
    vim.wo[fwin].winblend = 25
    vim.wo[fwin].wrap = false
    f = { win = fwin, buf = buf, text = nil, col = nil, width = nil, top = nil }
    floats[win] = f
  end

  -- 位置/尺寸随窗口变化重设（没变就不动，避免滚动时反复重设）
  if f.col ~= win_width - 1 or f.width ~= width or f.top ~= top then
    f.col, f.width, f.top = win_width - 1, width, top
    vim.api.nvim_win_set_config(f.win, {
      relative = "win",
      win = win,
      anchor = "NE",
      row = top,
      col = f.col,
      width = width,
      height = 1,
    })
  end

  if f.text ~= text then
    f.text = text
    vim.api.nvim_buf_set_lines(f.buf, 0, -1, false, { " " .. text .. " " })
    vim.api.nvim_buf_clear_namespace(f.buf, ns, 0, -1)
    if hl and icon_len > 0 then
      vim.api.nvim_buf_set_extmark(f.buf, ns, 0, 1, { end_col = 1 + icon_len, hl_group = hl })
    end
  end
end

local function refresh_all()
  if not enabled then
    return
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_normal_win(win) then
      M.refresh(win)
    end
  end
end

function M.toggle()
  enabled = not enabled
  if enabled then
    refresh_all()
  else
    M.close_all()
  end
  vim.notify("Float filename: " .. (enabled and "on" or "off"), vim.log.levels.INFO)
end

function M.setup()
  vim.api.nvim_create_autocmd({
    "BufEnter",
    "BufFilePost",
    "BufWritePost",
    "BufModifiedSet",
    "TextChanged",
    "TextChangedI",
    "CursorMoved",
    "CursorMovedI",
    "WinEnter",
    "WinNew",
    "TabEnter",
    "VimResized",
    "WinScrolled",
  }, {
    group = augroup,
    callback = function(args)
      M.refresh(vim.api.nvim_get_current_win())
      if args.event == "VimResized" or args.event == "TabEnter" then
        refresh_all()
      end
      if args.event == "CursorMoved" or args.event == "CursorMovedI" then
        -- treesitter-context 的上下文高度是异步(~150ms)更新的，光标移动后延迟
        -- 复检一次，让位置最终落到上下文下方。
        vim.defer_fn(function()
          M.refresh(vim.api.nvim_get_current_win())
        end, 200)
      end
    end,
  })

  -- 窗口关闭时清掉挂在它上面的浮窗
  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    callback = function(args)
      local win = tonumber(args.match)
      if win then
        close(win)
      end
      vim.schedule(refresh_all)
    end,
  })

  vim.keymap.set("n", "<leader>uN", M.toggle, { desc = "Toggle float filename" })

  refresh_all()
end

return M
