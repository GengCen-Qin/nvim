-- 通过 glab 查看当前项目的 GitLab MR，选中后在 buffer 里看 diff。
--
--   <leader>sm   当前项目里「我创建的」未合并 MR
--   <leader>sM   当前项目里「我创建的」MR（含已合并 / 已关闭）
-- 两者都只取最近 20 条（glab 默认按最近更新排序），MR 攒多了也不会拖慢。
--
-- 交互：Snacks picker 列出 MR，右侧预览是该 MR 的详情（字段与 glab mr view 一致：
-- 标题/状态/作者/指派/评审/分支/评论数/链接/描述），回车在新 tab 打开一个
-- ft=diff 的 buffer 展示 glab mr diff 的内容。
-- diff buffer 里按 o 跳到对应源码文件的新版本行位置（方便直接改代码），
-- [ / ] 在改动块之间上下跳（支持 3] 这样的次数前缀，落点回中）；
-- 当前分支不是 MR 的 source 分支时会提示行号可能对不上，但照常打开本地文件。
-- 列表里已合并 / 已关闭的标 [merged] / [closed]，草稿标 [draft]；
-- 未合并且有冲突的（has_conflicts）整行标红并加 [conflict]，一眼能看出哪个要处理。
-- 列表里按 <C-e> 切换选中 MR 的 draft 状态（draft ↔ ready），成功后原地刷新该行。
--
-- 实现要点：
--   * 只跑一次 `glab mr list -F json`，列表和预览都从这份 JSON 渲染。预览不额外
--     起 `glab mr view` 进程，否则光标每移动一次就是一次网络请求，picker 会顿。
--   * 取数用 vim.system 异步回调，网络不卡 UI；diff 同理，先开好 buffer 再回填。
--   * 等待网络期间用 Snacks notifier 转圈（取列表、取 diff 各一处），结束即停；
--     没有 Snacks 时退化成一条静态通知。
--   * 预览里 key（title: / state: ...）与 "--" 分隔线单独高亮，高亮组
--     GitlabMrKey / GitlabMrSep（默认 link Title / NonText），可在 colorscheme 覆盖。
--   * 列表里有冲突的 MR 整行用 GitlabMrConflict（默认 link DiagnosticError）标红。
--   * cwd 用当前工作目录，glab 据此自动识别项目，不需要 -R。
--
-- 依赖：glab 在 PATH 上且已登录（本机为 gitlab.yhlsoft.com）。
local M = {}

----------------------------------------------------------------------
-- 高亮组
----------------------------------------------------------------------

-- 预览里 key 与分隔线的颜色。用 default = true，方便在 colorscheme 里覆盖。
vim.api.nvim_set_hl(0, "GitlabMrKey", { link = "Title", default = true })
vim.api.nvim_set_hl(0, "GitlabMrSep", { link = "NonText", default = true })
-- 列表里「有冲突待处理」的 MR 用这个颜色整行标出来
vim.api.nvim_set_hl(0, "GitlabMrConflict", { link = "DiagnosticError", default = true })

----------------------------------------------------------------------
-- 工具
----------------------------------------------------------------------

local function notify(text, level)
  vim.notify("gitlab-mr: " .. text, level or vim.log.levels.INFO, { title = "GitLab MR" })
end

----------------------------------------------------------------------
-- 加载动画（取 MR 列表要走网络，等待期间得让用户看到是在正常进行）
----------------------------------------------------------------------

local SPIN = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spin = { state = nil }

local function spinner_stop()
  local s = spin.state
  if not s then
    return
  end
  spin.state = nil
  if s.timer then
    s.timer:stop()
    s.timer:close()
  end
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks and snacks.notifier and s.id then
    snacks.notifier.hide(s.id)
  end
end

---@param text string
---@param frame integer
---@param id integer|nil
local function spinner_show(text, frame, id)
  local ok, snacks = pcall(require, "snacks")
  if not (ok and snacks and snacks.notifier) then
    return nil
  end
  return snacks.notifier.notify(text, vim.log.levels.INFO, {
    id = id,
    title = "GitLab MR",
    timeout = false, -- 一直转到有结果为止
    icon = SPIN[frame],
  })
end

---@param text string
local function spinner_start(text)
  spinner_stop()
  local s = { text = text, frame = 1 }
  s.id = spinner_show(text, s.frame, nil)
  if not s.id then
    -- 没有 Snacks notifier：退化成静态通知，至少能看到正在进行
    return notify(text)
  end
  s.timer = vim.uv.new_timer()
  s.timer:start(
    0,
    80,
    vim.schedule_wrap(function()
      if spin.state ~= s then
        return
      end
      s.frame = s.frame % #SPIN + 1
      spinner_show(s.text, s.frame, s.id)
    end)
  )
  spin.state = s
end

---当前仓库根目录；不在 git 仓库里返回 nil
---@return string|nil
local function git_root()
  local out = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait(3000)
  if out.code ~= 0 then
    return nil
  end
  local root = vim.trim(out.stdout or "")
  return root ~= "" and root or nil
end

---异步跑 glab，stdout/stderr 以文本返回
---@param args string[]
---@param cwd string
---@param on_done fun(out: vim.SystemCompleted)
local function glab(args, cwd, on_done)
  vim.system(
    vim.list_extend({ "glab" }, args),
    { cwd = cwd, text = true },
    function(out) vim.schedule(function() on_done(out) end) end
  )
end

---把 [{username=...}] 拼成 "a, b"
---@param list table[]|nil
---@return string
local function names(list)
  if type(list) ~= "table" or #list == 0 then
    return ""
  end
  local out = {}
  for _, u in ipairs(list) do
    out[#out + 1] = u.username or u.name or "?"
  end
  return table.concat(out, ", ")
end

---glab 的 JSON 里 state 是 "opened"，view 里显示成 "open"，这里对齐 view
---@param state string|nil
---@return string
local function state_text(state)
  return (state == "opened") and "open" or (state or "")
end

----------------------------------------------------------------------
-- 渲染
----------------------------------------------------------------------

---按 glab mr view 的排版渲染一个 MR 的详情
---@param mr table
---@return string[]
local function render_view(mr)
  local lines = {}
  local function kv(key, value)
    lines[#lines + 1] = ("%-14s %s"):format(key .. ":", value or "")
  end

  local labels = {}
  for _, l in ipairs(mr.labels or {}) do
    labels[#labels + 1] = (type(l) == "table") and (l.name or "") or tostring(l)
  end

  kv("title", mr.title)
  kv("state", state_text(mr.state))
  kv("author", mr.author and mr.author.username or "")
  kv("labels", table.concat(labels, ", "))
  kv("assignees", names(mr.assignees))
  kv("reviewers", names(mr.reviewers))
  kv("source_branch", mr.source_branch)
  kv("target_branch", mr.target_branch)
  kv("comments", tostring(mr.user_notes_count or 0))
  kv("number", tostring(mr.iid))
  kv("url", mr.web_url)
  -- view 里没有、但挑 MR 时值得看的几项
  kv("draft", mr.draft and "yes" or "no")
  kv("changes", tostring(mr.changes_count or "?"))
  kv("conflicts", mr.has_conflicts and "yes" or "no")

  lines[#lines + 1] = "--"
  local desc = vim.trim(mr.description or "")
  if desc == "" then
    lines[#lines + 1] = "(no description)"
  else
    for _, line in ipairs(vim.split(desc, "\n", { plain = true })) do
      lines[#lines + 1] = line
    end
  end
  return lines
end

---picker 里每行的样式
---@param item table
---@return snacks.picker.Highlight[]
local function format_item(item)
  local mr = item.mr
  local ret = {}
  local function add(text, hl)
    ret[#ret + 1] = { text, hl }
  end

  -- 有冲突是要优先处理的，整行用冲突色标出（iid / 标题都会变红）。
  -- 只看未合并的：已合并/已关闭的 MR 即使 has_conflicts 为 true 也不用再处理了。
  local conflict = mr.has_conflicts == true and mr.state == "opened"
  local iid_hl = conflict and "GitlabMrConflict" or "Number"
  add(("!%-6d"):format(mr.iid), iid_hl)
  if conflict then
    add("[conflict] ", "GitlabMrConflict")
  end
  -- 看全部 MR 时列表里混着已合并/已关闭的，标出来才分得清；open 是常态就不标了
  if mr.state == "merged" then
    add("[merged] ", "DiagnosticOk")
  elseif mr.state == "closed" then
    add("[closed] ", "DiagnosticError")
  end
  if mr.draft then
    add("[draft] ", "DiagnosticWarn")
  end
  add(mr.title or "", conflict and "GitlabMrConflict" or "Normal")
  add(("  %s ← %s"):format(mr.target_branch or "?", mr.source_branch or "?"), "Comment")
  return ret
end

---预览 buffer 里 key 高亮用的 namespace（自己管理，别用 snacks 的）
local preview_ns = vim.api.nvim_create_namespace("gitlab-mr-preview")

---给预览的每一行首部 key（"title:" / "state:" ...）与 "--" 分隔线加高亮
---行内容从 buffer 实读，保证 extmark 的行列一定落在真实存在的文本上
---@param buf integer
local function highlight_keys(buf)
  vim.api.nvim_buf_clear_namespace(buf, preview_ns, 0, -1)
  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line == "--" then
      vim.api.nvim_buf_set_extmark(buf, preview_ns, i - 1, 0, {
        end_col = #line,
        hl_group = "GitlabMrSep",
      })
    else
      -- key 是行首连续的 [%w_] 后面跟冒号，只给这一段上色，value 保持原样
      local key = line:match("^([%w_]+):")
      if key then
        vim.api.nvim_buf_set_extmark(buf, preview_ns, i - 1, 0, {
          end_col = #key + 1,
          hl_group = "GitlabMrKey",
        })
      end
    end
  end
end

---picker 右侧预览：直接复用 view 的渲染结果，并把 key 高亮出来
---@param ctx snacks.picker.preview.ctx
function M.preview(ctx)
  ctx.preview:set_lines(ctx.item.detail or {})
  highlight_keys(ctx.preview.win.buf)
end

----------------------------------------------------------------------
-- diff buffer
----------------------------------------------------------------------

---按完整名字找 buffer（伪 URI 名交给 :b 的模糊匹配不可靠，这里精确比对）
---@param name string
---@return integer|nil
local function buf_by_name(name)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b) == name then
      return b
    end
  end
end

---解析当前 diff buffer：返回 行号→{path,new} 的映射，以及每个连续增删块的首行列表。
---glab mr diff 输出是精简 unified diff（--- / +++ / @@，没有 diff --git 头），
---路径相对仓库根；new 是 + 侧（MR 新版本）的行号，按 hunk 逐行累计出来。
---连续 + / - 行算一个改动块（[ ] 跳转用它定位首行），遇到上下文行或换 hunk 就断开。
---@param buf integer
---@return table<integer,{path:string|nil,new:integer}>, integer[]
local function parse_meta(buf)
  local meta, targets = {}, {}
  local path
  local old_ln, new_ln
  local changed = false -- 上一个内容行是否是 +/-
  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:match("^%+%+%+ ") then
      local p = line:sub(5)
      path = (p ~= "/dev/null") and p:gsub("^[ab]/", "") or nil
      changed = false
    elseif line:match("^@@ ") then
      -- 4 个捕获依次是 旧起始/旧行数/新起始/新行数，只取起始两个
      local a, _, b = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
      if a then
        old_ln, new_ln = tonumber(a) - 1, tonumber(b) - 1
        meta[i] = { path = path, new = math.max(1, tonumber(b)) }
      end
      changed = false
    elseif path then
      local c = line:sub(1, 1)
      if c == "-" then
        old_ln = old_ln + 1
        meta[i] = { path = path, new = math.max(1, new_ln) }
        if not changed then targets[#targets + 1] = i end
        changed = true
      elseif c == "+" then
        new_ln = new_ln + 1
        meta[i] = { path = path, new = new_ln }
        if not changed then targets[#targets + 1] = i end
        changed = true
      elseif c == " " or c == "" then
        old_ln = old_ln + 1
        new_ln = new_ln + 1
        meta[i] = { path = path, new = new_ln }
        changed = false
      end
    end
  end
  return meta, targets
end

---o：跳到光标所在改动对应的源码位置（工作区的新版本文件 + 行号）。
---分支不是 MR 的 source 分支时，本地内容和 MR 对不上，先提示行号可能错位。
local function open_file_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local root = vim.b[buf].gitlab_mr_root
  if not root then
    return notify("这不是 MR diff buffer", vim.log.levels.WARN)
  end

  local out = vim.system({ "git", "-C", root, "branch", "--show-current" }, { text = true }):wait(3000)
  local cur = vim.trim(out.stdout or "")
  local source = vim.b[buf].gitlab_mr_source
  if cur ~= "" and source and source ~= "" and cur ~= source then
    notify(("当前分支 %s 不是 MR 的 source 分支 %s，行号可能与 MR 对不上"):format(cur, source), vim.log.levels.WARN)
  end

  local m = parse_meta(buf)[vim.api.nvim_win_get_cursor(0)[1]]
  if not m then
    return notify("光标不在改动行", vim.log.levels.WARN)
  end
  if not m.path then
    return notify("该文件在 MR 里被删除，没有可跳的行", vim.log.levels.WARN)
  end
  local fpath = root .. "/" .. m.path
  if vim.fn.filereadable(fpath) ~= 1 then
    return notify(("本地没有 %s，先切到 %s 分支再试"):format(m.path, source or "source"), vim.log.levels.WARN)
  end
  vim.cmd("edit " .. vim.fn.fnameescape(fpath))
  vim.api.nvim_win_set_cursor(0, { math.min(m.new, vim.api.nvim_buf_line_count(0)), 0 })
end

---[ / ]：在改动块之间跳转（direction 1 向下 / -1 向上），支持次数前缀，落点整屏回中。
---与 git-review 的 space bb 一致：跳的是每个连续增删块的起始行，到末尾环绕。
---@param direction integer
local function jump(direction)
  local buf = vim.api.nvim_get_current_buf()
  if not vim.b[buf].gitlab_mr_root then
    return notify("这不是 MR diff buffer", vim.log.levels.WARN)
  end
  local _, targets = parse_meta(buf)
  if #targets == 0 then
    return notify("没有可跳的改动", vim.log.levels.INFO)
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local count = vim.v.count1
  for _ = 1, count do
    local next_
    if direction > 0 then
      for _, t in ipairs(targets) do
        if t > row then next_ = t; break end
      end
      row = next_ or targets[1]
    else
      for i = #targets, 1, -1 do
        if targets[i] < row then next_ = targets[i]; break end
      end
      row = next_ or targets[#targets]
    end
  end
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  vim.cmd("normal! zz")
end

---在新 tab 打开一个 buffer 展示 glab mr diff
---@param item table
function M.open_diff(item)
  local mr = item.mr
  local root = git_root()
  if not root then
    notify("当前不在 git 仓库里", vim.log.levels.WARN)
    return
  end

  -- 用伪 URI 当 buffer 名：状态栏能看出是哪个 MR，又不会被当成项目里的真实文件
  -- （相对名会被 nvim 解析到 cwd 下）。
  local name = ("glab-mr://%d.diff"):format(mr.iid)
  local existing = buf_by_name(name)
  if existing then
    -- 同一个 MR 已经开过：跳回原来的 buffer，别再造一个同名的
    local win = vim.fn.bufwinid(existing)
    if win ~= -1 then
      vim.api.nvim_set_current_win(win)
    else
      vim.api.nvim_set_current_buf(existing)
    end
    return
  end

  vim.cmd("tabnew")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  -- hide 而不是 wipe：wipe 会在 buffer 不再显示于任何窗口时把它整个删掉，
  -- 于是「在这个 tab 里打开别的文件」就会顺手把 diff 丢掉。
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  pcall(vim.api.nvim_buf_set_name, buf, name)
  vim.bo[buf].filetype = "diff"
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "loading diff of !" .. mr.iid .. " ..." })
  vim.bo[buf].modifiable = false

  -- b: 变量随 buffer 存活，o 跳转源码时用；source 分支不同时行号可能对不上，要提示
  vim.b[buf].gitlab_mr_root = root
  vim.b[buf].gitlab_mr_iid = mr.iid
  vim.b[buf].gitlab_mr_source = mr.source_branch
  vim.keymap.set("n", "o", open_file_at_cursor, { buffer = buf, silent = true })
  vim.keymap.set("n", "]", function() jump(1) end, { buffer = buf, silent = true })
  vim.keymap.set("n", "[", function() jump(-1) end, { buffer = buf, silent = true })

  spinner_start("fetching diff of !" .. mr.iid .. " ...")
  glab({ "mr", "diff", tostring(mr.iid) }, root, function(out)
    spinner_stop()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local lines
    if out.code ~= 0 then
      vim.bo[buf].filetype = "text"
      lines = vim.split("glab mr diff 失败:\n" .. vim.trim(out.stderr or out.stdout or ""), "\n", { plain = true })
    else
      local stdout = vim.trim(out.stdout or "")
      lines = (stdout == "") and { "(empty diff)" } or vim.split(stdout, "\n", { plain = true })
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end)
end

----------------------------------------------------------------------
-- draft 切换
----------------------------------------------------------------------

---把 MR 的 draft 状态翻过来：draft → ready，ready → draft。
---只对 open 的 MR 有意义（已合并/已关闭的改不了）。成功后改本地字段并刷新列表。
---@param picker snacks.picker|nil
---@param item table|nil
function M.toggle_draft(picker, item)
  local mr = item and item.mr
  if not mr then
    return
  end
  if mr.state ~= "opened" then
    return notify(
      ("!%d 已是 %s，draft 状态只对 open 的 MR 有效"):format(mr.iid, state_text(mr.state)),
      vim.log.levels.WARN
    )
  end
  local root = git_root()
  if not root then
    return notify("当前不在 git 仓库里", vim.log.levels.WARN)
  end

  local to_draft = not mr.draft
  spinner_start(("%s !%d ..."):format(to_draft and "marking draft" or "marking ready", mr.iid))
  glab({ "mr", "update", tostring(mr.iid), to_draft and "--draft" or "--ready" }, root, function(out)
    spinner_stop()
    if out.code ~= 0 then
      return notify(
        ("!%d 切换 draft 失败: %s"):format(mr.iid, vim.trim(out.stderr or out.stdout or "")),
        vim.log.levels.ERROR
      )
    end
    -- 改的是远端：把本地字段翻过来重渲染即可，不用重新拉整个列表
    mr.draft = to_draft
    item.detail = render_view(mr)
    if picker and not picker.closed then
      picker:refresh()
    end
    notify(("!%d %s"):format(mr.iid, to_draft and "已标为 draft" or "已取消 draft"))
  end)
end

----------------------------------------------------------------------
-- 取数
----------------------------------------------------------------------

---最多取多少条：MR 会越攒越多，只要最近这批就够了（glab 默认按最近更新排序）
local LIMIT = 20

---列出当前项目里我创建的 MR（近 LIMIT 条），回调里拿到解析后的列表
---@param opts { all?: boolean }|nil all=true 含已合并/已关闭，默认只开着的
---@param cb fun(mrs: table[]|nil, err: string|nil)
function M.fetch(opts, cb)
  opts = opts or {}
  if vim.fn.executable("glab") ~= 1 then
    return cb(nil, "找不到 glab 命令")
  end
  local root = git_root()
  if not root then
    return cb(nil, "当前不在 git 仓库里")
  end

  -- 总是看我创建的；all=true 时加 -A 把已合并/已关闭也带进来
  local args = { "mr", "list", "-F", "json", "--per-page", tostring(LIMIT), "--author", "@me" }
  if opts.all then
    args[#args + 1] = "-A"
  end

  glab(args, root, function(out)
    if out.code ~= 0 then
      return cb(nil, vim.trim(out.stderr or out.stdout or "glab mr list 失败"))
    end
    local ok, decoded = pcall(vim.json.decode, out.stdout or "")
    if not ok or type(decoded) ~= "table" then
      return cb(nil, "解析 glab 的 JSON 输出失败")
    end
    cb(decoded, nil)
  end)
end

----------------------------------------------------------------------
-- 入口
----------------------------------------------------------------------

---@param opts { author?: boolean }|nil
function M.open(opts)
  opts = opts or {}
  local label = opts.all and "my MRs (all states)" or "my open MRs"

  -- 取列表要走网络，先转起来；下面每条返回路径都会 spinner_stop()
  spinner_start("fetching " .. label .. " ...")

  M.fetch(opts, function(mrs, err)
    spinner_stop()
    if err then
      return notify(err, vim.log.levels.WARN)
    end
    if #mrs == 0 then
      return notify(("当前项目没有%s (%s)"):format(opts.all and "我创建的 MR" or "我创建的未合并 MR", label))
    end

    local items = {}
    for _, mr in ipairs(mrs) do
      items[#items + 1] = {
        -- text 是 matcher 匹配的对象，把 iid/标题/分支都放进去，随便搜哪个都能命中
        text = ("!%d %s %s %s"):format(mr.iid, mr.title or "", mr.target_branch or "", mr.source_branch or ""),
        mr = mr,
        detail = render_view(mr),
      }
    end

    require("snacks").picker.pick({
      title = ("GitLab MR: %s (%s)"):format(label, vim.fn.fnamemodify(git_root() or "", ":t")),
      items = items,
      format = format_item,
      preview = M.preview,
      -- <C-e>：把选中 MR 的 draft 状态翻过来（不动光标、不关 picker）
      actions = { toggle_draft = M.toggle_draft },
      win = {
        input = { keys = { ["<C-e>"] = { "toggle_draft", mode = { "i", "n" }, desc = "toggle draft" } } },
        list = { keys = { ["<C-e>"] = { "toggle_draft", mode = { "n" }, desc = "toggle draft" } } },
      },
      confirm = function(picker, item)
        picker:close()
        if item then
          M.open_diff(item)
        end
      end,
    })
  end)
end

return M
