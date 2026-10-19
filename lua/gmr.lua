-- 把当前分支改动提到 GitLab MR（space g m 触发）。
-- 移植自 ~/.config/fish/functions/gmr.fish 并结合进 nvim。
--
-- 交互（中途可取消；远端写操作只在最后一步自动执行）：
--   1. 列出本地已有的 origin/* 远端跟踪分支，挑 MR 目标分支（推荐项排最前、标 ●）
--      纯本地读取，不走网络；代价是列表为上次 fetch 的状态
--   2. 输入 MR 描述
--   3. 之后全自动：抓 Jira title → push → glab mr create，成功给 MR 链接
--      （不再要“确认提交”那一步）
--
-- 实现要点：
--   * 所有 git/glab/jira 调用都异步（vim.system 回调）。同步 :wait() 会阻塞事件
--     循环，进度动画就动不起来，所以整条链路用回调串起来。
--   * 进度用 Snacks notifier 的旋转图标（按 id 原位更新）+ uv 定时器驱动；
--     结束或出错时必须 spinner_stop()，否则动画会一直转。
--   * 解析 Jira 响应用 vim.json.decode，不经 jq。
--   * MR 链接直接从 glab mr create 的输出里抓，不用 `glab mr view --web`
--     （--web 会真的打开浏览器）。
--
-- 依赖：git / glab / jira 必须在 PATH 上，且 glab 已登录 gitlab.yhlsoft.com。
local M = {}

local SPIN = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local function notifier()
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks and snacks.notifier and snacks.notifier.notify then
    return snacks.notifier
  end
  return nil
end

local function msg(text, level)
  vim.notify("gmr: " .. text, level or vim.log.levels.INFO, { title = "gmr" })
end

----------------------------------------------------------------------
-- 进度动画
----------------------------------------------------------------------

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
  local n = notifier()
  if n and s.id then
    n.hide(s.id)
  end
end

local function spinner_show(text, frame, id)
  local n = notifier()
  if not n then
    return nil
  end
  return n.notify(text, vim.log.levels.INFO, {
    id = id,
    title = "gmr",
    timeout = false,
    icon = SPIN[frame],
  })
end

local function spinner_start(text)
  spinner_stop()
  if not notifier() then
    -- 没有 Snacks：退化为静态通知（不会动，但至少能看到在进行中）
    msg(text)
    return
  end
  local s = { text = text, frame = 1 }
  s.id = spinner_show(text, s.frame, nil)
  s.timer = vim.uv.new_timer()
  s.timer:start(0, 80, vim.schedule_wrap(function()
    if spin.state ~= s then
      return
    end
    s.frame = s.frame % #SPIN + 1
    spinner_show(s.text, s.frame, s.id)
  end))
  spin.state = s
end

local function spinner_update(text)
  local s = spin.state
  if s then
    s.text = text
    spinner_show(text, s.frame, s.id)
  else
    msg(text)
  end
end

----------------------------------------------------------------------
-- 工具
----------------------------------------------------------------------

local function run(cmd, cb) -- 异步执行，回调在 schedule 上下文里
  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function()
      cb(res)
    end)
  end)
end

-- 仓库名 = origin URL 去掉前缀与 .git 后缀
local function repo_from_url(url)
  return (url:match("([^/]+)%.git$") or url:match("([^/]+)$")):gsub("%.git$", "")
end

-- 从分支名提取标准 Jira issue key（GI-1234）
local function extract_issue_key(branch)
  return branch:match("([A-Z]+%-%d+)")
end

-- 推荐目标：含 master → master；含 release → RELEASE；否则 QA
local function recommended_target(branch)
  local lower = branch:lower()
  if lower:match("master") then
    return "master"
  elseif lower:match("release") then
    return "RELEASE"
  else
    return "QA"
  end
end

----------------------------------------------------------------------
-- 流程（forward declaration：Lua 的 local 必须先声明后引用）
----------------------------------------------------------------------

local pick_target, prompt_description, fetch_title, create_mr

-- 第 1 步：列本地已有的 origin/* 远端跟踪分支让用户挑（纯本地，不走网络）
-- 注意：用本地 refs，列表是上次 fetch 时的状态；没 fetch 过的分支不会出现。
local function choose_target(branch, issue_key, repo_name, assignee, reviewer)
  run({ "git", "for-each-ref", "--format=%(refname:short)", "refs/remotes/origin/" }, function(res)
    if res.code ~= 0 then
      msg("获取本地远端分支失败:\n" .. res.stderr, vim.log.levels.ERROR)
      return
    end

    local rec = recommended_target(branch)
    local targets = {}
    for line in vim.gsplit(res.stdout, "\n", { plain = true }) do
      local name = vim.trim(line)
      local short = name:match("^origin/(.+)$")
      -- 排除 origin/HEAD 这个符号引用和当前分支本身
      if short and short ~= "HEAD" and short ~= branch then
        targets[#targets + 1] = short
      end
    end

    if #targets == 0 then
      msg("本地没有 origin/* 分支，先执行 git fetch", vim.log.levels.ERROR)
      return
    end

    -- 推荐项排最前，其余按字母序
    table.sort(targets, function(a, b)
      if a == rec then
        return true
      end
      if b == rec then
        return false
      end
      return a < b
    end)

    pick_target(targets, rec, branch, issue_key, repo_name, assignee, reviewer)
  end)
end

pick_target = function(targets, rec, branch, issue_key, repo_name, assignee, reviewer)
  local ok, snacks = pcall(require, "snacks")
  local prompt = ("MR target branch (recommended: %s)"):format(rec)

  local function on_choice(target)
    if not target then
      return
    end
    prompt_description(branch, issue_key, repo_name, target, assignee, reviewer)
  end

  if ok and snacks and snacks.picker and snacks.picker.select then
    snacks.picker.select(targets, {
      prompt = prompt,
      format_item = function(t)
        return (t == rec and "● " or "  ") .. t
      end,
      snacks = { layout = { width = 0.6, min_width = 80, height = 0.5 } },
    }, on_choice)
  else
    vim.ui.select(targets, {
      prompt = prompt,
      format_item = function(t)
        return (t == rec and "● " or "  ") .. t
      end,
    }, on_choice)
  end
end

-- 第 2 步：输入描述，然后自动往下走
prompt_description = function(branch, issue_key, repo_name, target, assignee, reviewer)
  vim.ui.input({ prompt = "MR Description: " }, function(description)
    if not description or vim.trim(description) == "" then
      msg("description cannot be empty.", vim.log.levels.ERROR)
      return
    end
    fetch_title(branch, issue_key, repo_name, target, assignee, reviewer, vim.trim(description))
  end)
end

-- 第 3 步：抓 Jira title（慢，带动画）→ 建 MR
fetch_title = function(branch, issue_key, repo_name, target, assignee, reviewer, description)
  spinner_start("Fetching Jira issue " .. issue_key .. "...")
  run({ "jira", "issue", "view", issue_key, "--raw" }, function(res)
    if res.code ~= 0 then
      spinner_stop()
      msg("获取 Jira issue " .. issue_key .. " 失败", vim.log.levels.ERROR)
      return
    end

    local ok, data = pcall(vim.json.decode, res.stdout)
    local title = ok and data and data.fields and data.fields.summary
    if type(title) ~= "string" or vim.trim(title) == "" then
      spinner_stop()
      msg("解析 Jira 响应失败（缺少 fields.summary）", vim.log.levels.ERROR)
      return
    end

    create_mr(branch, target, assignee, reviewer, description, issue_key .. " " .. vim.trim(title))
  end)
end

-- 第 4 步：push + glab mr create（都带动画）
create_mr = function(branch, target, assignee, reviewer, description, mr_title)
  spinner_update("Pushing '" .. branch .. "' to origin...")
  run({ "git", "push", "-u", "origin", branch }, function(push)
    if push.code ~= 0 then
      spinner_stop()
      msg("推送失败:\n" .. push.stderr, vim.log.levels.ERROR)
      return
    end

    spinner_update("Creating merge request (target: " .. target .. ")...")
    run({
      "glab", "mr", "create",
      "--source-branch", branch,
      "--target-branch", target,
      "--title", mr_title,
      "--description", description,
      "--assignee", assignee,
      "--reviewer", reviewer,
      "--remove-source-branch=true",
      "--squash-before-merge=true",
    }, function(res)
      spinner_stop()
      if res.code ~= 0 then
        msg("创建 MR 失败:\n" .. res.stderr, vim.log.levels.ERROR)
        return
      end

      -- 从输出里抓 MR 链接（stdout/stderr 都看一眼），不调 --web 免得弹浏览器
      local out = (res.stdout or "") .. "\n" .. (res.stderr or "")
      local url = out:match("https?://%S+")
      if url then
        msg("MR 创建成功: " .. url)
      else
        msg("Merge request created successfully.")
      end
    end)
  end)
end

----------------------------------------------------------------------
-- 入口
----------------------------------------------------------------------

function M.create()
  for _, c in ipairs({ "git", "glab", "jira" }) do
    if vim.fn.executable(c) == 0 then
      msg("'" .. c .. "' is not installed.", vim.log.levels.ERROR)
      return
    end
  end

  run({ "git", "rev-parse", "--is-inside-work-tree" }, function(res)
    if res.code ~= 0 then
      msg("当前不在 git 仓库内", vim.log.levels.ERROR)
      return
    end

    run({ "git", "branch", "--show-current" }, function(res2)
      local branch = vim.trim(res2.stdout)
      if branch == "" then
        msg("无法获取当前 Git 分支", vim.log.levels.ERROR)
        return
      end

      local issue_key = extract_issue_key(branch)
      if not issue_key then
        msg("分支中未找到 Jira issue key: " .. branch, vim.log.levels.ERROR)
        return
      end

      run({ "git", "remote", "get-url", "origin" }, function(res3)
        if res3.code ~= 0 then
          msg("无法获取 Git origin", vim.log.levels.ERROR)
          return
        end
        local repo_name = repo_from_url(vim.trim(res3.stdout))

        -- Assignee：PAS → Kevin，其它 → Xiaoliang；Reviewer 恒为 Xiaoliang
        local assignee = repo_name == "PAS" and "kevin.zhang_yhlsoft.com" or "xiaoliang.zhao_yhlsoft.com"
        local reviewer = "xiaoliang.zhao_yhlsoft.com"

        choose_target(branch, issue_key, repo_name, assignee, reviewer)
      end)
    end)
  end)
end

return M
