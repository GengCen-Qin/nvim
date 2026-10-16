-- 数据库表结构快速查看（PostgreSQL / vim-dadbod）
--
--   <leader>fc   下拉选择 connection（跨重启记住）     对应 :DBTableSchema
--   <leader>fd   在当前选中的 connection 搜索表结构（等价 psql \d+）
--                  * 若已选中 connection：直接进表搜索
--                  * 若未选中过（或文件里没有记录）：先弹 connection 选择
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

      -- 用 psql 执行 \d+ 取表结构
      local function describe(conn, table_name)
        local url = url_of(conn)
        if not url then
          vim.notify("未知连接: " .. conn, vim.log.levels.ERROR)
          return
        end
        local canon = vim.fn["db#adapter#postgresql#canonicalize"](url)
        local cmd = vim.fn["db#adapter#postgresql#interactive"](
          canon,
          { "--no-psqlrc", "-c", '\\d+ "' .. table_name:gsub('"', '""') .. '"' }
        )
        local out = vim.fn["db#systemlist"](cmd)
        if #out == 0 then
          vim.notify("获取表结构失败: " .. table_name, vim.log.levels.ERROR)
          return
        end
        show(out, conn .. "." .. table_name)
      end

      -- 拉表名 -> 模糊选表 -> 展示结构
      local function search_tables(conn)
        local url = url_of(conn)
        if not url then
          vim.notify("未知连接: " .. conn, vim.log.levels.ERROR)
          return
        end
        local canon = vim.fn["db#adapter#postgresql#canonicalize"](url)
        vim.notify("正在获取 " .. conn .. " 的表列表...", vim.log.levels.INFO)
        local tables = vim.fn["db#adapter#postgresql#tables"](canon)
        if #tables == 0 then
          vim.notify("未获取到表（连接失败或网络不通）: " .. conn, vim.log.levels.ERROR)
          return
        end
        vim.ui.select(tables, {
          prompt = string.format("[%s] 搜索表（共 %d 个）", conn, #tables),
        }, function(choice)
          if choice then
            describe(conn, choice)
          end
        end)
      end

      -- <leader>fc: 下拉选择 connection
      local function choose_connection()
        pick_conn(function() end)
      end

      -- <leader>fd: 在当前选中 connection 搜表；没选中过则先选 connection
      local function schema_for_selected()
        local conn = load_saved()
        if conn then
          search_tables(conn)
        else
          pick_conn(search_tables)
        end
      end

      vim.api.nvim_create_user_command("DBTableSchema", function(a)
        if a.args ~= "" then
          set_selected(a.args)
          search_tables(a.args)
        else
          choose_connection()
        end
      end, { nargs = "?", complete = function(arg)
        return vim.tbl_filter(function(n)
          return n:find(arg, 1, true) == 1
        end, conn_names())
      end })

      vim.keymap.set("n", "<leader>fc", choose_connection, { desc = "DB: 选择连接" })
      vim.keymap.set("n", "<leader>fd", schema_for_selected, { desc = "DB: 搜索表结构" })

      -- <leader>fq: 新建 SQL buffer，绑定当前选中 connection（带 dadbod 补全）
      local function open_sql_buffer(conn)
        local dir = vim.fn.stdpath("data") .. "/db_queries"
        vim.fn.mkdir(dir, "p")
        local name = dir .. "/" .. conn .. ".sql"

        -- 已存在同名 buffer 就直接切过去，避免重复创建
        local existing = vim.fn.bufnr(name)
        if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) then
          vim.api.nvim_set_current_buf(existing)
          vim.b[existing].db = url_of(conn)
          vim.b[existing].dadbod = url_of(conn)
          return
        end

        -- 普通可编辑 buffer（非 scratch）：可以 :w 存盘，切走再回来内容还在
        local buf = vim.api.nvim_create_buf(true, false)
        vim.bo[buf].filetype = "sql"
        vim.bo[buf].swapfile = false
        -- 让 dadbod 补全与 :DB 都知道用哪个连接（必须写到目标 buffer 上）
        local url = url_of(conn)
        vim.b[buf].db = url
        vim.b[buf].dadbod = url
        pcall(vim.api.nvim_buf_set_name, buf, name)
        -- 在该 buffer 里：visual 选中按 q 执行选中；normal 下 q 执行整个 buffer
        -- 注意必须用 ":"（而非 <cmd>）——<cmd> 不会更新 '< '> 可视标记
        vim.keymap.set("x", "q", ":DB<CR>", { buffer = buf, desc = "DB: 执行选中 SQL" })
        vim.keymap.set("n", "q", ":%DB<CR>", { buffer = buf, desc = "DB: 执行整个 buffer" })
        vim.api.nvim_set_current_buf(buf)
        vim.notify("SQL buffer（连接: " .. conn .. "），visual 选中按 q 执行", vim.log.levels.INFO, { title = "DB" })
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
