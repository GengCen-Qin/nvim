-- 在 ga（Change Assignee）里补一个「指派给别人」的分支。
-- 插件原生把选项硬编码成 { "Assign to Me", "Unassign" }（lua/jira/board/init.lua:409），
-- 所以在用户侧 monkey-patch；不改 lazy 插件目录，插件更新后依然有效。
local function patch_change_assignee()
  local board = require("jira.board")
  local state = require("jira.board.state")
  local helper = require("jira.board.helper")
  local api = require("jira.jira-api.api")
  local common_ui = require("jira.common.ui")
  local auth = require("jira.common.auth")
  local version = require("jira.jira-api.version")

  -- 查「可指派到该项目」的用户。username 是前缀匹配，比 query 准
  local function search_assignable(project, keyword, cb)
    local a = auth.get_auth() or {}
    local base = (a.base or ""):gsub("/+$", "")
    if base == "" then
      return cb(nil, "缺少 Jira 认证，请先执行 :Jira auth login")
    end

    local args = { "curl", "-s", "-H", "Accept: application/json" }
    if auth.is_bearer(a.type) then
      vim.list_extend(args, { "-H", "Authorization: Bearer " .. (a.token or "") })
    else
      vim.list_extend(args, { "-u", (a.email or "") .. ":" .. (a.token or "") })
    end
    vim.list_extend(args, {
      "-G",
      base .. version.get_api_path() .. "/user/assignable/search",
      "--data-urlencode",
      "project=" .. project,
      "--data-urlencode",
      "username=" .. keyword,
      "--data-urlencode",
      "maxResults=20",
    })

    vim.system(args, { text = true }, function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          return cb(nil, "curl 执行失败: " .. tostring(res.stderr))
        end
        local ok, data = pcall(vim.json.decode, res.stdout)
        if not ok then
          return cb(nil, "返回内容不是合法 JSON")
        end
        if type(data) == "table" and data.errorMessages then
          return cb(nil, table.concat(data.errorMessages, "\n"))
        end
        cb(type(data) == "table" and data or {}, nil)
      end)
    end)
  end

  local function do_assign(issue_key, uid, label)
    common_ui.start_loading(("Assigning %s to %s..."):format(issue_key, label))
    api.assign_issue(issue_key, uid, function(_, err)
      vim.schedule(function()
        common_ui.stop_loading()
        if err then
          return vim.notify("Error assigning issue: " .. err, vim.log.levels.ERROR)
        end
        vim.notify(("Assigned %s to %s"):format(issue_key, label), vim.log.levels.INFO)
        board.refresh_view()
      end)
    end)
  end

  board.change_assignee = function()
    local node = helper.get_node_at_cursor()
    if not node or not node.key then
      return
    end

    local issue_key = node.key
    -- 项目 Key 直接取自 issue key 前缀（GI-123 -> GI），比读 state 更可靠
    local project = issue_key:match("^(%u+)%-") or state.project_key

    local choices = { "Assign to Me", "Assign to someone else...", "Unassign" }
    vim.ui.select(choices, { prompt = "Change Assignee for " .. issue_key .. ":" }, function(choice)
      if not choice then
        return
      end

      if choice == "Assign to Me" then
        common_ui.start_loading("Fetching your account info...")
        api.get_myself(function(me, err)
          vim.schedule(function()
            common_ui.stop_loading()
            local uid = me and (me.accountId or me.name or me.key)
            if err or not uid then
              return vim.notify("Error fetching account info: " .. (err or "Unknown error"), vim.log.levels.ERROR)
            end
            do_assign(issue_key, uid, "you")
          end)
        end)
      elseif choice == "Assign to someone else..." then
        vim.ui.input({ prompt = ("Search user for %s (username prefix): "):format(issue_key) }, function(input)
          if not input or input == "" then
            return
          end
          common_ui.start_loading("Searching users...")
          search_assignable(project, input, function(users, err)
            common_ui.stop_loading()
            if err then
              return vim.notify("Search failed: " .. err, vim.log.levels.ERROR)
            end
            if #users == 0 then
              return vim.notify(("No assignable user matches '%s' in %s"):format(input, project), vim.log.levels.WARN)
            end

            local labels, by_label = {}, {}
            for _, u in ipairs(users) do
              local label = ("%s  <%s>"):format(u.displayName or u.name, u.name or u.key or "?")
              if not by_label[label] then
                labels[#labels + 1] = label
                by_label[label] = u
              end
            end

            vim.ui.select(labels, { prompt = ("Assign %s to:"):format(issue_key) }, function(pick)
              if not pick then
                return
              end
              local u = by_label[pick]
              do_assign(issue_key, u.name or u.key or u.accountId, u.displayName or u.name)
            end)
          end)
        end)
      else -- Unassign
        common_ui.start_loading("Unassigning " .. issue_key .. "...")
        api.assign_issue(issue_key, "-1", function(_, err)
          vim.schedule(function()
            common_ui.stop_loading()
            if err then
              return vim.notify("Error unassigning issue: " .. err, vim.log.levels.ERROR)
            end
            vim.notify("Unassigned " .. issue_key, vim.log.levels.INFO)
            board.refresh_view()
          end)
        end)
      end
    end)
  end
end

return {
  "letieu/jira.nvim",
  opts = {
    jira = {
      api_version = "2", -- 自建 Jira Server/DC，只支持 v2；Cloud 才用 "3"
      limit = 200, -- Global limit of tasks per view (default: 200)
    },

    -- S 键（Sprint 视图）：只看分配给自己的 ticket
    -- 去掉 assignee = currentUser() 就是全项目，当前 GI 下 351 条 vs 4 条
    active_sprint_query = "project = '%s' AND sprint in openSprints() AND assignee = currentUser() ORDER BY Rank ASC",

    -- J 键（JQL 视图）里的预设查询。名字按字母序排列，所以加数字前缀固定顺序，
    -- 打开 JQL 视图时默认落在第一个（即 "1. My Sprint"）。
    -- %s 会被替换成项目 Key，不含 %s 的查询就是跨项目。
    queries = {
      ["1. My Sprint"] = "project = '%s' AND sprint in openSprints() AND assignee = currentUser() ORDER BY Rank ASC",
      ["2. My Open (this project)"] = "project = '%s' AND assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC",
      ["3. My Open (all projects)"] = "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC",
      ["4. Reported by Me"] = "reporter = currentUser() AND statusCategory != Done ORDER BY updated DESC",
      ["5. All Sprint (everyone)"] = "project = '%s' AND sprint in openSprints() ORDER BY Rank ASC",
      ["Backlog"] = "project = '%s' AND (issuetype IN standardIssueTypes() OR issuetype = Sub-task) AND (sprint IS EMPTY OR sprint NOT IN openSprints()) AND statusCategory != Done ORDER BY Rank ASC",
    },
  },

  config = function(_, opts)
    require("jira").setup(opts)
    patch_change_assignee()

    -- 提取 issue key：接受 "https://jira.yhlsoft.com/browse/GI-151843" 或 "GI-151843"
    local function extract_issue_key(input)
      local trimmed = vim.trim(input or "")
      if trimmed == "" then
        return nil
      end
      local m = trimmed:match("browse/([%w%-]+)")
      if m then
        return m:upper()
      end
      -- 形如 KEY-123（字母开头，项目 Key 可含数字，如 GI2-123）
      local k = trimmed:match("^([%a][%w]*%-%d+)$")
      if k then
        return k:upper()
      end
      return nil
    end

    -- space s j：打开 GI 看板（Sprint 视图，只含分配给我的 ticket）
    vim.keymap.set("n", "<leader>sj", function()
      require("jira").open("GI")
    end, { desc = "Jira: open GI board" })

    -- space f j：输入 issue URL 或 key 后展示该 ticket 详情
    vim.keymap.set("n", "<leader>fj", function()
      vim.ui.input({ prompt = "Jira issue (URL or KEY, e.g. GI-151843): " }, function(input)
        local key = extract_issue_key(input)
        if not key then
          return vim.notify("无法解析 Jira issue: '" .. tostring(input) .. "'", vim.log.levels.WARN)
        end
        require("jira").open("info " .. key)
      end)
    end, { desc = "Jira: show issue info by URL/KEY" })
  end,
}
