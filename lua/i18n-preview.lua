-- I18n 可见化：把 I18n.t('some.key') / t('some.key') 的译文内联渲染在调用之后，
-- 光标落到那一行时恢复原样（纯虚拟文本，不污染源码、不进 git）。
--
-- 数据来源：项目 config/locales/**/*.yml 按 Rails load_path 语义深合并后压成的 JSON 缓存，
-- 由 lua/i18n-preview/build_cache.rb 生成（首次打开 / yml 更新后自动重建）。
--
--   <leader>it  切换显示/隐藏
--   <leader>is  浮窗查看本行 key 的完整译文
--   <leader>ir  重建当前项目 locale 缓存（改了 yml 后用）
--   :I18nPreviewLocale [locale]   查看/切换渲染语言（默认 en）
--
-- 挂载：lua/config/autocmds.lua 里一行 require("i18n-preview").setup()。

local M = {}

M.opts = {
  locale = "en", -- 默认渲染 en（:I18nPreviewLocale 可切换）
  enabled = true,
  filetypes = { ruby = true },
  max_len = 60, -- 译文超长截断（0 = 不截断）
  debounce_ms = 200,
  methods = { t = true, translate = true }, -- 视为 I18n 的方法名
  viewport_only = true, -- 只渲染视口内（大文件性能）
  -- "inline" = 紧跟调用之后（阅读直观，但光标进入该行时整行会轻微回流）
  -- "eol"    = 贴行尾（代码本体不回流，离得远时不易对应）
  virt_text_pos = "inline",
  sep = "  ← ",
  hl = "I18nPreviewText",
  arrow_hl = "I18nPreviewArrow",
}

local NS = vim.api.nvim_create_namespace("i18n_preview")

-- 按 root 缓存已解码的 locale 数据
local store = {}

-- ============================ Rails root 与缓存 ============================

local function find_root(path)
  if not path or path == "" then
    return nil
  end
  local dir = vim.fn.fnamemodify(path, ":p:h")
  for _ = 1, 12 do
    if vim.fn.isdirectory(dir .. "/config/locales") == 1 then
      return dir
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      return nil
    end
    dir = parent
  end
  return nil
end

local function cache_path_for(root)
  local dir = vim.fn.stdpath("cache") .. "/i18n-preview"
  vim.fn.mkdir(dir, "p")
  return dir .. "/" .. vim.fn.sha256(root):sub(1, 16) .. ".json"
end

local function build_cache(root, out_path)
  local script = vim.fn.stdpath("config") .. "/lua/i18n-preview/build_cache.rb"
  if vim.fn.filereadable(script) == 0 then
    return false, "找不到 build_cache.rb"
  end
  local ok, res = pcall(function()
    return vim.system({ "ruby", script, root, out_path }, { text = true }):wait()
  end)
  if not ok then
    return false, "无法执行 ruby"
  end
  if res.code ~= 0 then
    return false, vim.trim(res.stderr or "")
  end
  return true
end

-- yml 比缓存新 -> 需要重建
-- 除了项目自身 config/locales，也查 WORKSPACE 并入的 locales（home/acct）
local function stale_glob(cache_time, pattern)
  local files = vim.fn.glob(pattern, false, true)
  for _, f in ipairs(files) do
    if vim.fn.getftime(f) > cache_time then
      return true
    end
  end
  return false
end

local function cache_stale(root, cache_path)
  if vim.fn.filereadable(cache_path) == 0 then
    return true
  end
  local cache_time = vim.fn.getftime(cache_path)
  if stale_glob(cache_time, root .. "/config/locales/**/*.yml") then
    return true
  end
  local ws = vim.env.WORKSPACE
  if ws and ws ~= "" then
    if stale_glob(cache_time, ws .. "/config/locales/home/*.yml") then
      return true
    end
    if stale_glob(cache_time, ws .. "/config/locales/acct/*.yml") then
      return true
    end
  end
  return false
end

local function load_data(root)
  local path = cache_path_for(root)
  -- 每次都做轻量过期检查（glob + mtime，~0.3ms）。会话开着时 yml 有改动
  -- （git pull / 手改）也能自动重建，不必手动 <leader>ir 或重启。
  if cache_stale(root, path) then
    local ok, err = build_cache(root, path)
    if not ok then
      vim.notify("i18n-preview: 构建 locale 缓存失败: " .. err, vim.log.levels.WARN)
      return store[root]
    end
    store[root] = nil
  end
  if store[root] then
    return store[root]
  end
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok then
    vim.notify("i18n-preview: locale 缓存解析失败", vim.log.levels.WARN)
    return nil
  end
  store[root] = decoded
  return decoded
end

local function lookup(data, locale, key)
  local loc = data and data[locale]
  if not loc then
    return nil
  end
  local s = loc.s and loc.s[key]
  if s and s ~= "" then
    return s
  end
  local h = loc.h and loc.h[key]
  if h then
    return "{" .. h .. "}"
  end
  return nil
end

-- ============================ treesitter 解析 ============================

local QUERY = [[
(call
  method: (identifier) @method
  arguments: (argument_list) @args)
]]

local query
local function get_query()
  if query then
    return query
  end
  local ok, q = pcall(vim.treesitter.query.parse, "ruby", QUERY)
  if not ok then
    return nil
  end
  query = q
  return q
end

local function unquote(text)
  local first = text:sub(1, 1)
  if (first == "'" or first == '"') and text:sub(-1) == first and #text >= 2 then
    return text:sub(2, -2)
  end
  return nil
end

-- 找出范围内的 I18n 调用，返回 { {key=, row=, col=}, ... }
-- col = 整个 call 结束位置（右括号之后），即虚拟文本插入点
local function find_calls(buf, row_start, row_end)
  local q = get_query()
  if not q then
    return {}
  end
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "ruby")
  if not ok or not parser then
    return {}
  end
  local ok2, trees = pcall(function()
    return parser:parse()
  end)
  if not ok2 or not trees or not trees[1] then
    return {}
  end

  local methods, args_nodes = {}, {}
  local ok3, iter = pcall(function()
    return q:iter_captures(trees[1]:root(), buf, row_start, row_end)
  end)
  if not ok3 then
    return {}
  end
  for id, node, _ in iter do
    local cap = q.captures[id]
    if cap == "method" then
      local r, c = node:start()
      methods[#methods + 1] = { row = r, col = c, name = vim.treesitter.get_node_text(node, buf) }
    elseif cap == "args" then
      args_nodes[#args_nodes + 1] = node
    end
  end

  local out = {}
  for _, args in ipairs(args_nodes) do
    local ar, ac = args:start()
    -- 同一行上、紧邻在参数表之前的那个方法名
    local best
    for _, m in ipairs(methods) do
      if m.row == ar and m.col < ac and (not best or m.col > best.col) then
        best = m
      end
    end
    if best and M.opts.methods[best.name] then
      local str
      for child in args:iter_children() do
        if child:type() == "string" then
          str = child
          break
        end
      end
      if str then
        local text = vim.treesitter.get_node_text(str, buf)
        local key = unquote(text)
        -- 跳过插值字符串（"#{x}.foo"）与空 key
        if key and key ~= "" and not key:find("#{", 1, true) then
          local parent = args:parent()
          local _, ec = (parent or args):end_()
          out[#out + 1] = { key = key, row = ar, col = ec }
        end
      end
    end
  end
  return out
end

-- ============================ 渲染 ============================

local function truncate(text)
  local max = M.opts.max_len
  if max and max > 0 and vim.fn.strchars(text) > max then
    return vim.fn.strcharpart(text, 0, max) .. "…"
  end
  return text
end

function M.refresh(buf, win)
  buf = buf or vim.api.nvim_get_current_buf()
  win = win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)

  if not M.opts.enabled or not M.opts.filetypes[vim.bo[buf].filetype] then
    return
  end
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" then
    return
  end
  local root = find_root(path)
  if not root then
    return
  end
  local data = load_data(root)
  if not data then
    return
  end

  local row_start, row_end = 0, -1
  if M.opts.viewport_only and vim.api.nvim_win_is_valid(win) then
    row_start = math.max(0, vim.fn.line("w0", win) - 1)
    row_end = vim.fn.line("w$", win)
  end

  -- 光标所在行不渲染 -> 恢复原样
  local cursor_row
  if vim.api.nvim_win_is_valid(win) then
    cursor_row = vim.api.nvim_win_get_cursor(win)[1] - 1
  end

  for _, c in ipairs(find_calls(buf, row_start, row_end)) do
    if c.row ~= cursor_row then
      local text = lookup(data, M.opts.locale, c.key)
      if text then
        local line = vim.api.nvim_buf_get_lines(buf, c.row, c.row + 1, false)[1] or ""
        if c.col <= #line then
          vim.api.nvim_buf_set_extmark(buf, NS, c.row, c.col, {
            virt_text = {
              { M.opts.sep, M.opts.arrow_hl },
              { truncate(text), M.opts.hl },
            },
            virt_text_pos = M.opts.virt_text_pos,
            hl_mode = "combine",
            priority = 100,
          })
        end
      end
    end
  end
end

-- ============================ 防抖与高亮 ============================

local pending = {}

local function schedule_refresh(buf)
  local token = (pending[buf] or 0) + 1
  pending[buf] = token
  vim.defer_fn(function()
    if pending[buf] ~= token or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    M.refresh(buf)
  end, M.opts.debounce_ms)
end

local function set_highlights()
  vim.api.nvim_set_hl(0, "I18nPreviewText", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "I18nPreviewArrow", { link = "NonText", default = true })
end

-- ============================ 对外命令 ============================

function M.toggle()
  M.opts.enabled = not M.opts.enabled
  vim.notify("i18n-preview: " .. (M.opts.enabled and "开启" or "关闭"))
  M.refresh()
end

function M.set_locale(loc)
  if not loc or loc == "" then
    local root = find_root(vim.api.nvim_buf_get_name(0))
    local data = root and load_data(root)
    local list = data and table.concat(vim.tbl_keys(data), ", ") or "?"
    vim.notify("i18n-preview: 当前 " .. M.opts.locale .. "，可用: " .. list)
    return
  end
  M.opts.locale = loc
  vim.notify("i18n-preview: locale = " .. loc)
  M.refresh()
end

function M.reload()
  local root = find_root(vim.api.nvim_buf_get_name(0))
  if not root then
    vim.notify("i18n-preview: 未找到 Rails root", vim.log.levels.WARN)
    return
  end
  local path = cache_path_for(root)
  store[root] = nil
  local ok, err = build_cache(root, path)
  if not ok then
    vim.notify("i18n-preview: 重建失败: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  vim.notify("i18n-preview: 缓存已重建")
  M.refresh()
end

-- 浮窗显示本行所有 key 的完整译文（长文本被截断时用）
function M.show()
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local root = find_root(vim.api.nvim_buf_get_name(buf))
  if not root then
    return
  end
  local data = load_data(root)
  if not data then
    return
  end
  local lines = {}
  for _, c in ipairs(find_calls(buf, row, row + 1)) do
    local text = lookup(data, M.opts.locale, c.key)
    if text then
      lines[#lines + 1] = c.key .. "  (" .. M.opts.locale .. ")"
      lines[#lines + 1] = "  " .. text
    end
  end
  if #lines == 0 then
    vim.notify("i18n-preview: 本行没有可解析的 I18n key", vim.log.levels.INFO)
    return
  end
  local fbuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(fbuf, 0, -1, false, lines)
  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  vim.api.nvim_open_win(fbuf, false, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = math.min(width + 2, math.max(20, vim.o.columns - 8)),
    height = #lines,
    style = "minimal",
    border = "rounded",
  })
end

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
  set_highlights()

  -- 命令与键位
  vim.api.nvim_create_user_command("I18nPreviewLocale", function(args)
    M.set_locale(args.args)
  end, { nargs = "?", desc = "I18nPreview: 查看/切换渲染语言" })

  vim.keymap.set("n", "<leader>it", M.toggle, { desc = "I18nPreview: 显示/隐藏译文" })
  vim.keymap.set("n", "<leader>is", M.show, { desc = "I18nPreview: 浮窗查看译文" })
  vim.keymap.set("n", "<leader>ir", M.reload, { desc = "I18nPreview: 重建 locale 缓存" })

  local group = vim.api.nvim_create_augroup("I18nPreview", { clear = true })

  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_highlights })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufReadPost", "BufWritePost" }, {
    group = group,
    callback = function(args)
      M.refresh(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
    group = group,
    callback = function(args)
      schedule_refresh(args.buf)
    end,
  })

  -- 光标跨行时才重绘（让光标所在行恢复原样 / 移走后重新显示）
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = function(args)
      local row = vim.api.nvim_win_get_cursor(vim.api.nvim_get_current_win())[1]
      if vim.w.i18n_preview_last_row ~= row then
        vim.w.i18n_preview_last_row = row
        schedule_refresh(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "WinScrolled", "WinEnter" }, {
    group = group,
    callback = function(args)
      schedule_refresh(args.buf)
    end,
  })
end

return M
