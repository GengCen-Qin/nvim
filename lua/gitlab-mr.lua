-- 通过 glab 查看当前项目的 GitLab MR，选中后在 buffer 里看 diff。
--
--   <leader>sm   当前项目里「我创建的」未合并 MR
--   <leader>sM   当前项目里「我创建的」MR（含已合并 / 已关闭）
-- 两者都只取最近 20 条（glab 默认按最近更新排序），MR 攒多了也不会拖慢。
--
-- 交互：Snacks picker 列出 MR，右侧预览是该 MR 的详情（字段与 glab mr view 一致：
-- 标题/状态/作者/指派/评审/分支/评论数/链接/描述），回车在新 tab 打开一个
-- ft=diff 的 buffer 展示 glab mr diff 的内容。
-- 列表里已合并 / 已关闭的标 [merged] / [closed]，草稿标 [draft]；
-- 未合并且有冲突的（has_conflicts）整行标红并加 [conflict]，一眼能看出哪个要处理。
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

---在新 tab 打开一个 buffer 展示 glab mr diff
---@param item table
function M.open_diff(item)
  local mr = item.mr
  local root = git_root()
  if not root then
    notify("当前不在 git 仓库里", vim.log.levels.WARN)
    return
  end

  vim.cmd("tabnew")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  -- 用伪 URI 当 buffer 名：状态栏能看出是哪个 MR，又不会被当成项目里的真实文件
  -- （相对名会被 nvim 解析到 cwd 下）。同一 MR 再开一次时同名会冲突，忽略即可。
  pcall(vim.api.nvim_buf_set_name, buf, ("glab-mr://%d.diff"):format(mr.iid))
  vim.bo[buf].filetype = "diff"
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "loading diff of !" .. mr.iid .. " ..." })
  vim.bo[buf].modifiable = false

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
