-- LazyRead：把「只给自己看、不进 git」的行级注释挂在代码行上
-- （Sublime Text 插件 lazy_read 的 nvim 版）
--
--   cc          当前行添加 / 编辑注释（弹输入框，回车保存；已有注释则预填）
--   cv          浮窗查看当前行注释的完整内容
--   <leader>cf  搜索所有注释（snacks picker，回车跳转）
--   <leader>cd  删除当前行注释
--   <leader>ct  显示 / 隐藏行尾注释预览
--
-- 数据与 Sublime 版共用 ~/.lazyRead/notes.json，两个编辑器互相可见。
-- 注释只写这个外部文件、不写进源码，所以永远不会进 git，也无需 .gitignore。
--
-- 实现要点：
--   * 行锚定沿用 Sublime 版同一套字段（line / line_text / line_hash），
--     行号漂移后在 ±line_drift_search_radius 行内按内容重新定位。
--   * 行尾预览用 extmark 的 virt_text(eol)，等价 Sublime 的 annotation 模式；
--     extmark 会随编辑自动移动，比 Sublime 手动重算省事。
--   * hash 用 sha256（nvim 没有 sha1）。line_text 才是主匹配键，hash 只在文本
--     完全相同时才可能命中，故算法与 Sublime 的 sha1 不同也不影响两边互通。
--   * notes.json 被外部改坏时只读不写，避免把用户已有注释覆盖掉。
--   * 跨 worktree：注释额外带 repo_key = (git 公共目录 | 仓库内相对路径)，
--     同一仓库的各个 worktree 共享该键，故写在公共代码上的注释在每个
--     worktree 里都可见；只存在于某个 worktree 的文件天然不会串到别处。
--     行号跨 worktree 常差很远，±radius 搜不到时退到全文件按内容定位。
local M = {}

local NS = vim.api.nvim_create_namespace("lazy_read")

-- 与 Sublime 版共用同一份数据。Sublime 跑在 Windows 上（家目录是 Windows 的），
-- 所以这里指向 /mnt/c/... 而不是 WSL 的 ~/.lazyRead，否则读不到之前写的注释。
-- 想换位置可在 setup({ notes_path = "..." }) 里覆盖。
local DEFAULT_NOTES_PATH = "/mnt/c/Users/Sicheng/.lazyRead/notes.json"
local NOTES_PATH = DEFAULT_NOTES_PATH

M.opts = {
  summary_max_length = 80, -- 行尾预览截断长度
  line_drift_search_radius = 20, -- 行漂移后在此范围内按内容重新定位
  display = true, -- 是否显示行尾预览
  debounce_ms = 250, -- 编辑后刷新预览的防抖（同 Sublime 的 300ms）
}

-- ============================ 基础工具 ============================

local function now()
  return os.date("%Y-%m-%dT%H:%M:%S")
end

-- Sublime 在 Windows 上记的是 \\wsl.localhost\Ubuntu\home\lucas\... 或 C:\...，
-- nvim 在 WSL 里用的是 /home/lucas/... 或 /mnt/c/...，两边必须互相换算，
-- 否则读不到对方写的注释（之前 71 条里 68 条都是 UNC 形式）。
local function to_local_path(path)
  if not path or path == "" then
    return ""
  end
  local distro = vim.env.WSL_DISTRO_NAME or "Ubuntu"
  for _, prefix in ipairs({ "\\\\wsl.localhost\\" .. distro .. "\\", "\\\\wsl$\\" .. distro .. "\\" }) do
    if path:sub(1, #prefix) == prefix then
      return "/" .. (path:sub(#prefix + 1):gsub("\\", "/"))
    end
  end
  local drive, rest = path:match("^([A-Za-z]):\\(.*)$")
  if drive then
    return "/mnt/" .. drive:lower() .. "/" .. rest:gsub("\\", "/")
  end
  return path
end

-- 反向换算：写成 Windows 侧能直接打开的写法，保证 Sublime 也能跳过来
local function to_stored_path(path)
  if not path or path == "" then
    return path
  end
  local drive, rest = path:match("^/mnt/([a-zA-Z])/(.*)$")
  if drive then
    return drive:upper() .. ":\\" .. rest:gsub("/", "\\")
  end
  if path:sub(1, 1) == "/" then
    local distro = vim.env.WSL_DISTRO_NAME or "Ubuntu"
    return "\\\\wsl.localhost\\" .. distro .. "\\" .. path:sub(2):gsub("/", "\\")
  end
  return path
end

local function normalize_path(path)
  local local_path = to_local_path(path)
  if local_path == "" then
    return ""
  end
  return vim.fn.fnamemodify(vim.fn.expand(local_path), ":p")
end

-- ====================== git worktree 归属（跨 worktree 可见） ======================
--
-- 同一仓库的多个 worktree（如 PAS 主仓与 orca/workspaces/PAS/* 里的分支工作区）
-- 共享同一个 git 目录，而同一文件在各 worktree 里的「相对仓库根路径」相同。
-- 于是用 (git 公共目录, 相对路径) 作为跨 worktree 的稳定标识：公共代码上的注释
-- 在任何 worktree 里都能命中；只存在于某个 worktree 的文件，别的 worktree 里
-- 本来就没这个文件，自然也不会串。
--
-- 注释里的 file_path 仍是绝对路径（与 Sublime 版共用、可读性好），repo_key 只是
-- 额外的匹配键；Sublime 版读到不认识的字段会原样保留，不受影响。
local repo_cache = {}

-- 返回 { common = git 公共目录, root = 本 worktree 根 }；不在 git 仓库里则 false
local function repo_of(path)
  local dir = vim.fn.fnamemodify(path, ":h")
  local cached = repo_cache[dir]
  if cached ~= nil then
    return cached
  end

  local function git(arg)
    local out = vim.fn.systemlist({ "git", "-C", dir, "rev-parse", "--path-format=absolute", arg })
    if vim.v.shell_error ~= 0 or #out == 0 then
      return nil
    end
    return out[1]
  end

  local common, root = git("--git-common-dir"), git("--show-toplevel")
  local info = false
  if common and root then
    local c = vim.fn.fnamemodify(common, ":p"):gsub("/+$", "")
    info = { common = c, root = vim.fn.fnamemodify(root, ":p") }
  end
  repo_cache[dir] = info
  return info
end

-- "git公共目录|仓库内相对路径"，不在 git 仓库里返回 nil
local function repo_key(path)
  local info = repo_of(path)
  if not info then
    return nil
  end
  local abs = vim.fn.fnamemodify(path, ":p")
  if abs:sub(1, #info.root) ~= info.root then
    return nil
  end
  return info.common .. "|" .. abs:sub(#info.root + 1)
end

local function split_repo_key(key)
  if type(key) ~= "string" then
    return nil, nil
  end
  return key:match("^(.-)|(.+)$")
end

local function line_hash(text)
  return vim.fn.sha256(text or "")
end

local id_counter = 0

-- 生成 UUID 形状的 id。只需在本地唯一，不必是真 uuid4。
local function gen_id()
  id_counter = id_counter + 1
  local seed = string.format("%d-%d-%d-%d", vim.uv.hrtime(), os.time(), id_counter, math.random(1, 2 ^ 31 - 1))
  local h = vim.fn.sha256(seed)
  return string.format("%s-%s-%s-%s-%s", h:sub(1, 8), h:sub(9, 12), h:sub(13, 16), h:sub(17, 20), h:sub(21, 32))
end

local function set_highlights()
  -- default = true：用户若自定义过同名组则不覆盖
  vim.api.nvim_set_hl(0, "LazyReadMark", { fg = "#b89878", default = true })
  vim.api.nvim_set_hl(0, "LazyReadNote", { link = "Comment", default = true })
end

-- ============================ 读写 notes.json ============================

local cache = { mtime = nil, data = nil, broken = false }

local function file_mtime()
  local st = vim.uv.fs_stat(NOTES_PATH)
  if not st then
    return nil
  end
  return string.format("%d.%d", st.mtime.sec, st.mtime.nsec)
end

local function load_data()
  local mtime = file_mtime()
  if cache.data and cache.mtime == mtime then
    return cache.data
  end

  local data = { version = 1, notes = {} }
  cache.broken = false

  if mtime then
    local f = io.open(NOTES_PATH, "r")
    if f then
      local content = f:read("*a")
      f:close()
      local ok, decoded = pcall(vim.json.decode, content)
      if ok and type(decoded) == "table" then
        data = decoded
      else
        -- 解析失败就只读不写，绝不覆盖用户已有注释
        cache.broken = true
        vim.notify("LazyRead: " .. NOTES_PATH .. " 解析失败，已进入只读模式", vim.log.levels.ERROR)
      end
    end
  end

  if type(data.notes) ~= "table" then
    data.notes = {}
  end
  if data.version == nil then
    data.version = 1
  end

  cache.mtime = mtime
  cache.data = data
  return data
end

-- 按 key 排序输出，与 Sublime 的 json.dump(sort_keys=True, indent=2) 保持一致；
-- 遍历 note 的全部 key 而非固定字段，避免丢掉 Sublime 将来新增的字段。
local function encode_pretty(data)
  local out = { "{" }
  local notes = data.notes or {}

  if #notes == 0 then
    out[#out + 1] = '  "notes": [],'
  else
    out[#out + 1] = '  "notes": ['
    for i, note in ipairs(notes) do
      local keys = {}
      for k in pairs(note) do
        keys[#keys + 1] = k
      end
      table.sort(keys)

      local parts = {}
      for _, k in ipairs(keys) do
        parts[#parts + 1] = string.format("      %s: %s", vim.json.encode(k), vim.json.encode(note[k]))
      end

      out[#out + 1] = "    {"
      out[#out + 1] = table.concat(parts, ",\n")
      out[#out + 1] = "    }" .. (i < #notes and "," or "")
    end
    out[#out + 1] = "  ],"
  end

  local top = {}
  for k in pairs(data) do
    if k ~= "notes" then
      top[#top + 1] = k
    end
  end
  table.sort(top)
  for i, k in ipairs(top) do
    out[#out + 1] = string.format('  %s: %s%s', vim.json.encode(k), vim.json.encode(data[k]), i < #top and "," or "")
  end

  out[#out + 1] = "}"
  return table.concat(out, "\n") .. "\n"
end

local function save_data(data)
  if cache.broken then
    vim.notify("LazyRead: notes.json 已损坏，跳过写入以免覆盖", vim.log.levels.ERROR)
    return false
  end

  vim.fn.mkdir(vim.fn.fnamemodify(NOTES_PATH, ":h"), "p")

  local tmp = NOTES_PATH .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then
    vim.notify("LazyRead: 无法写入 " .. tmp, vim.log.levels.ERROR)
    return false
  end
  f:write(encode_pretty(data))
  f:close()

  -- 先写临时文件再 rename，避免写一半崩掉留下坏文件（同 Sublime 的做法）
  local ok = os.rename(tmp, NOTES_PATH)
  if not ok then
    vim.fn.delete(NOTES_PATH)
    ok = os.rename(tmp, NOTES_PATH)
  end
  if not ok then
    vim.notify("LazyRead: 保存失败 " .. NOTES_PATH, vim.log.levels.ERROR)
    return false
  end

  cache.data = data
  cache.mtime = file_mtime()
  return true
end

-- ============================ 行 / 注释 定位 ============================

local function buf_path(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return nil
  end
  return normalize_path(name)
end

local function line_text(buf, row)
  if row < 0 or row >= vim.api.nvim_buf_line_count(buf) then
    return nil
  end
  return vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
end

local function notes_for_file(path, data)
  local out = {}
  local target = normalize_path(path)
  local target_key = repo_key(target)
  for _, note in ipairs(data.notes or {}) do
    if normalize_path(note.file_path or "") == target then
      out[#out + 1] = note
    elseif target_key ~= nil and note.repo_key == target_key then
      -- 同一个仓库的另一个 worktree 上写的注释（公共代码），这里也命中
      out[#out + 1] = note
    end
  end
  return out
end

-- 老注释没有 repo_key：文件还在的话补算一次并落盘，之后就能跨 worktree 共享。
-- 每个会话只跑一次，git 结果按目录缓存，代价可忽略。
local migrated_repo_keys = false
local function migrate_repo_keys()
  if migrated_repo_keys then
    return
  end
  migrated_repo_keys = true

  local data = load_data()
  local changed = false
  for _, note in ipairs(data.notes or {}) do
    if note.repo_key == nil then
      local file = to_local_path(note.file_path or "")
      if file ~= "" and vim.fn.filereadable(file) == 1 then
        local key = repo_key(file)
        if key then
          note.repo_key = key
          changed = true
        end
      end
    end
  end
  if changed then
    save_data(data)
  end
end

local function find_note(data, id)
  for _, note in ipairs(data.notes or {}) do
    if note.id == id then
      return note
    end
  end
  return nil
end

local function note_matches_line(note, text)
  if text == nil then
    return false
  end
  if note.line_text == text then
    return true
  end
  return note.line_hash ~= nil and note.line_hash == line_hash(text)
end

-- 返回 行号(0-based) 和「是否发生了重新定位」
local function resolve_note_row(buf, note)
  local row = (tonumber(note.line) or 1) - 1

  if note_matches_line(note, line_text(buf, row)) then
    return row, false
  end

  local expected = note.line_text or ""
  if vim.trim(expected) == "" then
    return nil, false
  end

  local radius = M.opts.line_drift_search_radius
  local last = vim.api.nvim_buf_line_count(buf) - 1
  local best_row, best_dist

  for r = math.max(0, row - radius), math.min(last, row + radius) do
    if note_matches_line(note, line_text(buf, r)) then
      local dist = math.abs(r - row)
      if best_dist == nil or dist < best_dist then
        best_row, best_dist = r, dist
      end
    end
  end

  if best_row == nil then
    -- 跨 worktree 时行号通常差很多，±radius 搜不到：退到全文件按内容找。
    -- 公共代码行文本相同，这足以定位；性能只在备注量少时触发，可接受。
    for r = 0, last do
      if note_matches_line(note, line_text(buf, r)) then
        best_row = r
        break
      end
    end
    if best_row == nil then
      return nil, false
    end
    note.line = best_row + 1
    note.line_text = line_text(buf, best_row)
    note.line_hash = line_hash(note.line_text)
    note.updated_at = now()
    return best_row, true
  end

  note.line = best_row + 1
  note.line_text = line_text(buf, best_row)
  note.line_hash = line_hash(note.line_text)
  note.updated_at = now()
  return best_row, true
end

local function note_for_row(buf, row, data)
  local changed = false
  for _, note in ipairs(notes_for_file(buf_path(buf), data)) do
    local resolved, did_change = resolve_note_row(buf, note)
    changed = changed or did_change
    if resolved == row then
      return note, changed
    end
  end
  return nil, changed
end

local function summary_of(note)
  local text = vim.trim((note.note or ""):gsub("%s+", " "))
  local max = M.opts.summary_max_length
  if max > 0 and vim.fn.strchars(text) > max then
    text = vim.fn.strcharpart(text, 0, max) .. "…"
  end
  return text
end

-- ============================ 行尾预览 ============================

function M.refresh(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  migrate_repo_keys()

  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)

  if not M.opts.display then
    return
  end
  local path = buf_path(buf)
  if not path then
    return
  end

  local data = load_data()
  local notes = notes_for_file(path, data)
  if #notes == 0 then
    return
  end

  local changed = false
  for _, note in ipairs(notes) do
    local row, did_change = resolve_note_row(buf, note)
    changed = changed or did_change
    if row then
      vim.api.nvim_buf_set_extmark(buf, NS, row, 0, {
        virt_text = {
          { "  ▏", "LazyReadMark" },
          { summary_of(note), "LazyReadNote" },
        },
        virt_text_pos = "eol",
      })
    end
  end

  if changed then
    save_data(data)
  end
end

-- 编辑期间频繁触发，防抖后再刷新（同 Sublime 的 debounce）
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

-- ============================ 浮窗展示 ============================

local function open_float(note)
  -- 只展示写的内容本身，不掺路径/时间等无关信息
  local body = vim.split(note.note or "", "\n", { plain = true })
  if #body == 0 then
    body = { "" }
  end

  local width = 0
  for _, l in ipairs(body) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.min(math.max(width + 2, 28), math.max(20, vim.o.columns - 8))
  local height = math.min(#body, math.max(1, math.floor(vim.o.lines * 0.5)))

  local fbuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(fbuf, 0, -1, false, body)

  local win = vim.api.nvim_open_win(fbuf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  for _, key in ipairs({ "q", "<Esc>", "<C-c>" }) do
    vim.keymap.set("n", key, close, { buffer = fbuf, nowait = true, silent = true })
  end
  vim.api.nvim_create_autocmd("BufLeave", { buffer = fbuf, once = true, callback = close })
end

-- ============================ 对外命令 ============================

function M.add_or_edit()
  local buf = vim.api.nvim_get_current_buf()
  local path = buf_path(buf)
  if not path then
    vim.notify("LazyRead: 需要一个已保存到磁盘的文件", vim.log.levels.WARN)
    return
  end

  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local data = load_data()
  local note, changed = note_for_row(buf, row, data)
  if changed then
    save_data(data)
  end

  vim.ui.input({ prompt = "LazyRead 注释: ", default = note and note.note or "" }, function(input)
    if input == nil then
      return -- Esc 取消
    end

    local text = vim.trim(input)
    if text == "" then
      vim.notify("LazyRead: 空注释已忽略", vim.log.levels.INFO)
      return
    end

    local lt = line_text(buf, row)
    if lt == nil then
      vim.notify("LazyRead: 目标行已不存在", vim.log.levels.WARN)
      return
    end

    local ts = now()
    if note then
      note.file_path = note.file_path or to_stored_path(path)
      note.line = row + 1
      note.line_text = lt
      note.line_hash = line_hash(lt)
      note.note = text
      note.updated_at = ts
      if note.repo_key == nil then
        note.repo_key = repo_key(path)
      end
    else
      note = {
        id = gen_id(),
        file_path = to_stored_path(path),
        line = row + 1,
        line_text = lt,
        line_hash = line_hash(lt),
        note = text,
        repo_key = repo_key(path),
        created_at = ts,
        updated_at = ts,
      }
      data.notes = data.notes or {}
      data.notes[#data.notes + 1] = note
    end

    if save_data(data) then
      M.refresh(buf)
      vim.notify("LazyRead: 已保存", vim.log.levels.INFO)
    end
  end)
end

function M.show()
  local buf = vim.api.nvim_get_current_buf()
  local path = buf_path(buf)
  if not path then
    vim.notify("LazyRead: 需要一个已保存到磁盘的文件", vim.log.levels.WARN)
    return
  end

  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local data = load_data()
  local note, changed = note_for_row(buf, row, data)
  if changed then
    save_data(data)
  end

  if not note then
    vim.notify("LazyRead: 这一行没有注释", vim.log.levels.INFO)
    return
  end

  open_float(note)
end

function M.delete()
  local buf = vim.api.nvim_get_current_buf()
  if not buf_path(buf) then
    vim.notify("LazyRead: 需要一个已保存到磁盘的文件", vim.log.levels.WARN)
    return
  end

  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local data = load_data()
  local note, changed = note_for_row(buf, row, data)
  if changed then
    save_data(data)
  end

  if not note then
    vim.notify("LazyRead: 这一行没有注释", vim.log.levels.INFO)
    return
  end

  -- 不再弹确认框：按这个键本身就是确认动作
  local kept = {}
  for _, item in ipairs(data.notes or {}) do
    if item.id ~= note.id then
      kept[#kept + 1] = item
    end
  end
  data.notes = kept

  if save_data(data) then
    M.refresh(buf)
    vim.notify("LazyRead: 已删除", vim.log.levels.INFO)
  end
end

function M.toggle()
  M.opts.display = not M.opts.display
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      M.refresh(buf)
    end
  end
  vim.notify("LazyRead: " .. (M.opts.display and "显示注释" or "隐藏注释"), vim.log.levels.INFO)
end

function M.jump(note)
  local path = to_local_path(note.file_path or "")

  if path == "" or vim.fn.filereadable(path) == 0 then
    -- 原 worktree 可能已被删掉：按 repo_key 在当前 worktree / 主仓里找同名文件
    local common, rel = split_repo_key(note.repo_key)
    local current = buf_path(vim.api.nvim_get_current_buf())
    local fallback
    if rel and current then
      local info = repo_of(current)
      if info and info.common == common then
        fallback = info.root .. rel
      end
      if (not fallback or vim.fn.filereadable(fallback) == 0) and common then
        fallback = common:gsub("/%.git/$", "/") .. rel
      end
    end

    if fallback and vim.fn.filereadable(fallback) == 1 then
      path = fallback
    else
      vim.notify("LazyRead: 文件不存在 " .. tostring(note.file_path), vim.log.levels.ERROR)
      return
    end
  end

  vim.cmd.edit(vim.fn.fnameescape(path))
  local buf = vim.api.nvim_get_current_buf()

  local data = load_data()
  local real = find_note(data, note.id)
  local row
  if real then
    local changed
    row, changed = resolve_note_row(buf, real)
    if changed then
      save_data(data)
    end
  end

  if not row then
    row = math.max(0, (tonumber(note.line) or 1) - 1)
  end
  row = math.min(row, vim.api.nvim_buf_line_count(buf) - 1)

  vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
  vim.cmd("normal! zz")
  M.refresh(buf)
end

function M.search()
  local data = load_data()
  local notes = vim.deepcopy(data.notes or {})
  if #notes == 0 then
    vim.notify("LazyRead: 还没有任何注释", vim.log.levels.INFO)
    return
  end

  table.sort(notes, function(a, b)
    if (a.file_path or "") ~= (b.file_path or "") then
      return (a.file_path or "") < (b.file_path or "")
    end
    local la, lb = tonumber(a.line) or 1, tonumber(b.line) or 1
    if la ~= lb then
      return la < lb
    end
    return (a.updated_at or "") < (b.updated_at or "")
  end)

  local items = {}
  for _, note in ipairs(notes) do
    local line = tonumber(note.line) or 1
    local local_file = to_local_path(note.file_path or "")
    local where = string.format("%s:%d", vim.fn.fnamemodify(local_file, ":~:."), line)
    local sum = summary_of(note)
    items[#items + 1] = {
      -- 注意：不能把展示用的位置字段命名为 loc —— snacks.picker 内部用
      -- item.loc.range 做定位，字符串赋给 loc 会让它索引 .range 时报错。
      text = sum .. "  " .. where, -- matcher 搜索用的完整文本
      summary = sum,
      where = where,
      note = note,
      -- file/pos 用本地路径，preview = "file" 才能正确打开并定位
      file = local_file,
      pos = { line, 0 },
    }
  end

  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.picker then
    snacks.picker.pick({
      title = "LazyRead 注释",
      items = items,
      format = function(item)
        return {
          { item.summary, "LazyReadNote" },
          { "  " .. item.where, "Comment" },
        }
      end,
      preview = "file",
      confirm = function(picker, item)
        picker:close()
        if item then
          M.jump(item.note)
        end
      end,
    })
    return
  end

  -- 兜底：没有 snacks 时用 vim.ui.select
  vim.ui.select(items, {
    prompt = "LazyRead 注释",
    format_item = function(item)
      return item.text
    end,
  }, function(choice)
    if choice then
      M.jump(choice.note)
    end
  end)
end

-- ============================ 初始化 ============================

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
  if opts and opts.notes_path then
    NOTES_PATH = vim.fn.expand(opts.notes_path)
    cache.mtime, cache.data, cache.broken = nil, nil, false
  end
  set_highlights()

  local group = vim.api.nvim_create_augroup("LazyRead", { clear = true })

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
end

return M
