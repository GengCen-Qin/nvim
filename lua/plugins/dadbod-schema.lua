-- 数据库表结构快速查看（PostgreSQL / vim-dadbod）
--
--   <leader>fc   下拉选择 connection（跨重启记住）     对应 :DBTableSchema
--   <leader>fd   在当前选中的 connection 搜索对象（表/视图/物化视图/函数/过程）
--                  * 列表统一展示（含对象类型），选了再取结构或源码
--                  * 若已选中 connection：直接进搜索
--                  * 若未选中过（或文件里没有记录）：先弹 connection 选择
--                  * 表/视图/物化视图 -> 列结构；函数/过程 -> \sf 源码
--   <leader>fq   新建一个 SQL buffer（filetype=sql，带 dadbod 补全）
--                  * 自动绑定当前选中的 connection；未选中则先弹选择
--                  * 在该 buffer 里 visual 选中 SQL，按 q 执行选中内容
--
-- 连接来自 vim.g.dbs（见 lua/config/options.lua）。
-- 选中结果写入 XDG 数据目录，重启 nvim 后仍记住上次选的 connection。
return {
  {
    -- tpope/vim-dadbod 为纯 autoload 插件，常驻开销极小；
    -- 常驻可保证 db#... 函数与 :DBTableSchema 随时可用。
    "tpope/vim-dadbod",
    lazy = false,
    config = function()
      local conn_file = vim.fn.stdpath("data") .. "/db_selected_connection"

      -- 记录当前选中的 connection（会话内）
      local selected_conn ---@type string?

      -- 连接名 -> URL
      local function url_of(conn)
        return conn and vim.g.dbs and vim.g.dbs[conn] or nil
      end

      local function conn_names()
        local names = vim.tbl_keys(vim.g.dbs or {})
        table.sort(names)
        return names
      end

      -- 读上次保存的 connection（仅校验是否仍存在于 vim.g.dbs）
      local function load_saved()
        if selected_conn then
          return selected_conn
        end
        local f = io.open(conn_file, "r")
        if f then
          local saved = f:read("*l")
          f:close()
          if saved and vim.g.dbs and vim.g.dbs[saved] then
            selected_conn = saved
          end
        end
        return selected_conn
      end

      -- 持久化当前选中（保存时校验名字有效）
      local function save_selected()
        if not (selected_conn and vim.g.dbs and vim.g.dbs[selected_conn]) then
          return
        end
        local f = io.open(conn_file, "w")
        if f then
          f:write(selected_conn)
          f:close()
        end
      end

      -- 切换 connection
      local function set_selected(conn)
        selected_conn = conn
        save_selected()
        vim.notify("当前数据库连接: " .. conn, vim.log.levels.INFO, { title = "DB" })
      end

      -- 无参数时先用已保存的；若无则弹选择
      local function pick_conn(cb)
        local names = conn_names()
        if #names == 0 then
          vim.notify("vim.g.dbs 为空，请先配置连接", vim.log.levels.ERROR)
          return
        end
        vim.ui.select(names, {
          prompt = "选择数据库连接",
          format_item = function(name)
            local url = url_of(name)
            -- 隐去密码，仅展示 user@host/database
            local pretty = url and url:gsub("://([^:]+):[^@]*@", "://%1@") or ""
            return string.format("%-9s %s", name, pretty)
          end,
        }, function(choice)
          if choice then
            set_selected(choice)
            cb(choice)
          end
        end)
      end

      -- 打开只读 scratch 新 buffer 展示结构（当前窗口直接显示，不切分屏）
      local function show(lines, title)
        local prev = vim.api.nvim_get_current_buf()
        local buf = vim.api.nvim_create_buf(false, true) -- 新 scratch buffer
        vim.bo[buf].buftype = "nofile"
        vim.bo[buf].bufhidden = "wipe"
        vim.bo[buf].swapfile = false
        vim.bo[buf].modifiable = true
        vim.bo[buf].filetype = "sql"
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.bo[buf].modifiable = false
        -- schema 行可能很长，关闭换行：先切为当前窗口再设（vim.wo 需要 buffer 在窗口上）
        -- 不是分屏，所以 q 直接回到之前的 buffer
        vim.keymap.set("n", "q", function()
          if vim.api.nvim_buf_is_valid(prev) then
            vim.api.nvim_set_current_buf(prev)
          else
            vim.cmd("enew")
          end
        end, { buffer = buf, desc = "Close (回到上一个 buffer)" })
        pcall(vim.api.nvim_buf_set_name, buf, "db-schema://" .. title)
        vim.api.nvim_set_current_buf(buf)
        -- schema 行可能很长，关闭换行：对显示该 buffer 的当前窗口设置（不影响外部文件）
        vim.api.nvim_set_option_value("wrap", false, { win = 0 })
      end

      -- 统一执行一条 psql 只读命令。raw=true 加 -tA（行结果便于解析，如对象列表、函数源码）；
      -- 结构展示（\d+）不带 -tA，保留 psql 对齐表头。
      local function run_psql(conn, sql, raw)
        local url = url_of(conn)
        if not url then
          vim.notify("未知连接: " .. conn, vim.log.levels.ERROR)
          return nil
        end
        local canon = vim.fn["db#adapter#postgresql#canonicalize"](url)
        local flags = raw and { "--no-psqlrc", "-tA" } or { "--no-psqlrc" }
        local cmd = vim.fn["db#adapter#postgresql#interactive"](
          canon, vim.list_extend(flags, { "-c", sql })
        )
        return vim.fn["db#systemlist"](cmd)
      end

      -- 用 psql 执行 \d+ 取对象（表/视图/物化视图）结构，视图会连带定义
      local function describe(conn, schema, name)
        local q = function(s)
          return '"' .. s:gsub('"', '""') .. '"'
        end
        local out = run_psql(conn, '\\d+ ' .. q(schema) .. '.' .. q(name))
        if not out or #out == 0 then
          vim.notify("获取结构失败: " .. schema .. "." .. name, vim.log.levels.ERROR)
          return
        end
        show(out, conn .. "." .. schema .. "." .. name)
      end

      -- 取函数/过程源码（等价 \sf，经 oid 精确取，避免重载歧义）
      local function show_func(conn, oid, fqn)
        local out = run_psql(conn, "SELECT pg_get_functiondef(" .. oid .. ");", true)
        if not out or #out == 0 then
          vim.notify("获取函数源码失败: " .. fqn, vim.log.levels.ERROR)
          return
        end
        show(out, conn .. "." .. fqn)
      end

      -- 拉取全部对象（表/视图/物化视图/函数/过程），统一模糊选择
      local function search_objects(conn)
        vim.notify("正在获取 " .. conn .. " 的对象列表...", vim.log.levels.INFO)
        -- 关系对象：relkind r/p=表, v=视图, m=物化视图；忽略系统 schema 与 pg_ 前缀
        local rels = run_psql(conn, [[
          SELECT c.relkind::text || '|' || n.nspname || '|' || c.relname
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE c.relkind IN ('r','p','v','m')
            AND c.relname !~ '^pg_'
            AND n.nspname !~ '^pg_'
            AND n.nspname <> 'information_schema'
          ORDER BY 1
        ]], true) or {}
        -- 函数/过程对象（带 oid 与参数签名，签名仅用于区分重载）
        local funcs = run_psql(conn, [[
          SELECT p.prokind::text || '|' || n.nspname || '|' || p.proname || '|' || p.oid::text
                 || '|' || pg_get_function_identity_arguments(p.oid)
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE p.prokind IN ('f','p')
            AND n.nspname !~ '^pg_'
            AND n.nspname <> 'information_schema'
          ORDER BY 1
        ]], true) or {}

        local kind_label = {
          r = "table", p = "table", v = "view", m = "matview",
          f = "function", p = "procedure",
        }

        -- items: {kind, fqn, schema, name, oid?}
        local items = {}
        for _, line in ipairs(rels) do
          local k, s, n = line:match("^([rpvm])|([^|]+)|(.+)$")
          if k then
            items[#items + 1] = { kind = k, fqn = s .. "." .. n, schema = s, name = n }
          end
        end
        -- 同名函数（重载）才追加参数签名，平时列表保持简洁
        local overloaded = {}
        local raw_funcs = {}
        for _, line in ipairs(funcs) do
          local k, s, n, oid, args = line:match("^([fp])|([^|]+)|([^|]+)|(%d+)|(.*)$")
          if k then
            local fqn = s .. "." .. n
            overloaded[fqn] = (overloaded[fqn] or 0) + 1
            raw_funcs[#raw_funcs + 1] = { kind = k, fqn = fqn, schema = s, name = n, oid = oid, args = args }
          end
        end
        for _, it in ipairs(raw_funcs) do
          if overloaded[it.fqn] > 1 and it.args ~= "" then
            it.fqn = it.fqn .. "(" .. it.args .. ")"
          end
          items[#items + 1] = it
        end

        if #items == 0 then
          vim.notify("未获取到对象（连接失败或网络不通）: " .. conn, vim.log.levels.ERROR)
          return
        end
        vim.ui.select(items, {
          prompt = string.format("[%s] 搜索对象（共 %d 个）", conn, #items),
          format_item = function(it)
            local label = kind_label[it.kind] or "?"
            return string.format("%-9s %s", label, it.fqn)
          end,
        }, function(choice)
          if not choice then
            return
          end
          if choice.oid then
            show_func(conn, choice.oid, choice.fqn)
          else
            describe(conn, choice.schema, choice.name)
          end
        end)
      end

      -- <leader>fc: 下拉选择 connection
      local function choose_connection()
        pick_conn(function() end)
      end

      -- <leader>fd: 在当前选中 connection 搜对象；没选中过则先选 connection
      local function schema_for_selected()
        local conn = load_saved()
        if conn then
          search_objects(conn)
        else
          pick_conn(search_objects)
        end
      end

      vim.api.nvim_create_user_command("DBTableSchema", function(a)
        if a.args ~= "" then
          set_selected(a.args)
          search_tables(a.args)
        else
          choose_connection()
        end
      end, {
        nargs = "?",
        complete = function(arg)
          return vim.tbl_filter(function(n)
            return n:find(arg, 1, true) == 1
          end, conn_names())
        end,
      })

      vim.keymap.set("n", "<leader>fs", choose_connection, { desc = "DB: 选择连接" })
      vim.keymap.set("n", "<leader>fd", schema_for_selected, { desc = "DB: 搜索表结构" })

      -- 给 SQL buffer 打上连接与执行键位（新建与复用都调用，确保 q 一定生效）
      local function setup_sql_buffer(buf, conn)
        local url = url_of(conn)
        vim.b[buf].db = url
        vim.b[buf].dadbod = url
        vim.b[buf].db_query_temp = true
        -- 在该 buffer 里：visual 选中按 q 执行选中；normal 下 q 执行整个 buffer
        -- 注意必须用 ":"（而非 <cmd>）——<cmd> 不会更新 '< '> 可视标记
        vim.keymap.set("x", "q", ":DB<CR>", { buffer = buf, desc = "DB: 执行选中 SQL" })
        vim.keymap.set("n", "q", ":%DB<CR>", { buffer = buf, desc = "DB: 执行整个 buffer" })
      end

      -- <leader>fq: 新建 SQL buffer，绑定当前选中 connection（带 dadbod 补全）
      local function open_sql_buffer(conn)
        local dir = vim.fn.stdpath("data") .. "/db_queries"
        vim.fn.mkdir(dir, "p")
        local name = dir .. "/" .. conn .. ".sql"

        -- 已存在同名 buffer 就直接切过去（复用也补上键位，防止旧 buffer 缺映射）
        local existing = vim.fn.bufnr(name)
        if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) then
          setup_sql_buffer(existing, conn)
          vim.api.nvim_set_current_buf(existing)
          return
        end

        -- 普通可编辑 buffer（非 scratch）：可以 :w 存盘，切走再回来内容还在
        local buf = vim.api.nvim_create_buf(true, false)
        vim.bo[buf].filetype = "sql"
        vim.bo[buf].swapfile = false
        -- 标记为临时查询 buffer：不参与 auto-save.nvim 自动保存
        pcall(vim.api.nvim_buf_set_name, buf, name)
        setup_sql_buffer(buf, conn)
        vim.api.nvim_set_current_buf(buf)
        vim.notify(
          "SQL buffer（连接: " .. conn .. "），visual 选中按 q 执行",
          vim.log.levels.INFO,
          { title = "DB" }
        )
      end

      local function new_sql_buffer()
        local conn = load_saved()
        if conn then
          open_sql_buffer(conn)
        else
          pick_conn(open_sql_buffer)
        end
      end

      vim.keymap.set("n", "<leader>fq", new_sql_buffer, { desc = "DB: 新建 SQL buffer" })

      -- 退出时把当前选中写盘（load_saved 时已写，这里兜底）
      vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = save_selected,
      })
    end,
  },
}
