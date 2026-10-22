-- 数据库表结构快速查看（PostgreSQL / vim-dadbod）
--
--   <leader>fc   下拉选择 connection（跨重启记住）     对应 :DBTableSchema
--   <leader>fd   在当前选中的 connection 搜索对象（表/视图/物化视图/函数/过程）
--                  * 列表统一展示（含对象类型），选了再取结构或源码
--                  * 若已选中 connection：直接进搜索
--                  * 若未选中过（或文件里没有记录）：先弹 connection 选择
--                  * 表/视图/物化视图 -> 列结构；函数/过程 -> \sf 源码
--                  * 结构与源码都在悬浮窗展示，q 或 Esc 关闭，回到原 buffer
--                  * 永远走本地(非TP)连接，TP 连接会按名字映射到本地对应连接
--   <leader>fq   新建一个 SQL buffer（filetype=sql，带 dadbod 补全）
--                  * 自动绑定当前选中的 connection；未选中则先弹选择
--                  * 在该 buffer 里 visual 选中 SQL，按 q 执行选中内容
--                  * 双线路：补全走本地(非TP)连接(快)；执行走选中的连接(可能 TP)
--                  * normal 模式 K：悬浮展示光标下单词的结构（表/视图/函数），
--                    q 或 Esc 关闭，回到 SQL buffer
--   ruby 文件 normal 模式 K（仅 filetype=ruby，其它文件类型不绑）：
--                  光标停在模型类名（如 PasAccount）上按 K，按
--                  「显式 self.table_name 优先、否则 Rails tableize 推导」
--                  解析成数据表并悬浮展示列结构，q 或 Esc 关闭。
--                  类名->表名见 lua/db-model-map.lua。
--                  非模型词（方法/变量/工具类）不接管：有支持 hover 的 LSP
--                  才转交 vim.lsp.buf.hover()，否则静默（本机没装 ruby LSP，
--                  直接调 hover 会报 textDocument/hover not supported）。
--
-- 表/视图结构默认只显示 Column / Type / Nullable / Default / Comment 五列；
-- 想换成别的列，设 vim.g.db_schema_columns（见文件内 schema_field_expr 的可用字段）。
--
-- 字段补全说明：vim-dadbod-completion 只在整库列数 <= 10000 时才加载全局列名，
-- 本地 pas 库有 13669 列，全局列名这条路永久不可用；因此靠"跟住当前 FROM/JOIN
-- 的表"设 b:db_table 走按表补全，不带表名前缀也能补出字段。
--
-- 连接来自 vim.g.dbs（见 lua/config/options.lua）。
-- 选中结果写入 XDG 数据目录，重启 nvim 后仍记住上次选的 connection。
--
-- 本地(非TP)连接映射规则（local_conn_of）：tp_xxx -> xxx，
-- tp_pas_2/3/4 去掉 _数字 后缀落回 pas；本就是非TP则原样使用；
-- 映射不到则补全回退到选中连接并给出 WARN 提示。
-- 想直接查 TP 的结构（绕过映射）用 :DBTableSchema <连接名>。
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

      -- 连接名 -> 本地(非TP)连接名：tp_xxx -> 本地 xxx，tp_pas_2/3/4 去掉 _数字 落回 pas。
      -- 本就是非TP则原样返回；映射不到返回 nil（调用方回退到原连接）。
      local function local_conn_of(conn)
        if not (conn and vim.g.dbs) then
          return conn
        end
        local base = conn
        if base:sub(1, 3) == "tp_" then
          base = base:gsub("^tp_", ""):gsub("_%d+$", "")
        end
        return vim.g.dbs[base] and base or nil
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

      -- 用悬浮窗展示结构/源码（<leader>fd 与 K 共用）。
      -- 看完 q 或 Esc 关闭，焦点回到原来的窗口/buffer。
      -- 注意：这里不能用 nvim_buf_call 包裹——它会在回调返回时把当前窗口还原回
      -- SQL 窗口，导致浮窗拿不到焦点、Esc 落到 SQL buffer 上关不掉浮窗。
      local function show_float(lines, title)
        local width = math.min(120, math.max(60, vim.o.columns - 4))
        local height = math.min(vim.o.lines - 8, #lines + 2)
        local buf = vim.api.nvim_create_buf(false, true)
        vim.bo[buf].bufhidden = "wipe"
        vim.bo[buf].swapfile = false
        vim.bo[buf].filetype = "sql"
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        pcall(vim.api.nvim_buf_set_name, buf, "db-float://" .. title)
        local win = vim.api.nvim_open_win(buf, true, {
          relative = "editor",
          width = width,
          height = height,
          col = math.max(0, math.floor((vim.o.columns - width) / 2)),
          row = math.max(0, math.floor((vim.o.lines - height) / 2)),
          style = "minimal",
          border = "rounded",
          title = " " .. title .. " ",
          title_pos = "center",
        })
        vim.wo[win].wrap = false
        -- Esc / q 关闭浮窗（焦点随之回到 SQL 窗口）；浮窗只读，不需要其它键
        local close = function()
          if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
          end
        end
        vim.keymap.set("n", "<Esc>", close, { buffer = buf, desc = "关闭" })
        vim.keymap.set("n", "q", close, { buffer = buf, desc = "关闭" })
        -- 兜底：窗口被别的途径切走/关闭时一并收掉
        vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
          buffer = buf,
          once = true,
          callback = function()
            if vim.api.nvim_win_is_valid(win) and vim.api.nvim_get_current_win() ~= win then
              vim.api.nvim_win_close(win, true)
            end
          end,
        })
      end

      -- 表/视图结构要展示哪些列（顺序即展示顺序）。
      -- 改这里，或在配置里设 vim.g.db_schema_columns 覆盖，例如只要三列：
      --   vim.g.db_schema_columns = { "Column", "Type", "Comment" }
      -- 可选：Column / Type / Nullable / Default / Comment / Collation / Storage / Stats
      local schema_field_expr = {
        Column = "a.attname",
        Type = "format_type(a.atttypid, a.atttypmod)",
        Nullable = "CASE WHEN a.attnotnull THEN 'not null' ELSE '' END",
        Default = "pg_get_expr(d.adbin, d.adrelid)",
        Comment = "col_description(a.attrelid, a.attnum)",
        Collation = "CASE WHEN a.attcollation <> t.typcollation THEN cl.collname END",
        Storage = "CASE a.attstorage"
          .. " WHEN 'p' THEN 'plain' WHEN 'e' THEN 'external'"
          .. " WHEN 'm' THEN 'main' WHEN 'x' THEN 'extended' END",
        Stats = "CASE WHEN a.attstattarget < 0 THEN '' ELSE a.attstattarget::text END",
      }
      local default_schema_columns = { "Column", "Type", "Nullable", "Default", "Comment" }

      local function quote_ident(s)
        return '"' .. s:gsub('"', '""') .. '"'
      end

      -- 按配置的列拼列结构查询；psql 对齐输出，不用自己排版。
      local function relation_schema_sql(schema, name)
        local want = vim.g.db_schema_columns or default_schema_columns
        local sel = {}
        for _, field in ipairs(want) do
          local expr = schema_field_expr[field]
          if expr then
            sel[#sel + 1] = string.format('%s AS %s', expr, quote_ident(field))
          end
        end
        if #sel == 0 then
          return nil
        end
        local fqn = quote_ident(schema) .. "." .. quote_ident(name)
        return string.format([[
SELECT %s
FROM pg_attribute a
LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
LEFT JOIN pg_type t ON t.oid = a.atttypid
LEFT JOIN pg_collation cl ON cl.oid = a.attcollation
WHERE a.attrelid = '%s'::regclass AND a.attnum > 0 AND NOT a.attisdropped
ORDER BY a.attnum]], table.concat(sel, ",\n       "), fqn)
      end

      -- 取表/视图的列结构；视图/物化视图再附上定义（否则看不出视图是什么）。失败返回 nil。
      local function relation_body(conn, schema, name, kind)
        local sql = relation_schema_sql(schema, name)
        if not sql then
          vim.notify(
            "vim.g.db_schema_columns 里没有可用的列名",
            vim.log.levels.WARN,
            { title = "DB" }
          )
          return nil
        end
        local out = run_psql(conn, sql)
        if not out or #out == 0 then
          return nil
        end
        if kind ~= "v" and kind ~= "m" then
          return out
        end
        local fqn = quote_ident(schema) .. "." .. quote_ident(name)
        local def = run_psql(conn, "SELECT pg_get_viewdef('" .. fqn .. "'::regclass, true);", true)
        if not def or #def == 0 then
          return out
        end
        local body = {}
        for _, line in ipairs(out) do
          body[#body + 1] = line
        end
        body[#body + 1] = ""
        body[#body + 1] = "-- 视图定义:"
        vim.list_extend(body, def)
        return body
      end

      -- 悬浮展示表/视图结构（不替换当前 buffer）
      local function describe(conn, schema, name, kind)
        local body = relation_body(conn, schema, name, kind)
        if not body then
          vim.notify("获取结构失败: " .. schema .. "." .. name, vim.log.levels.ERROR)
          return
        end
        show_float(body, conn .. "." .. schema .. "." .. name)
      end

      -- 取函数/过程源码（等价 \sf，经 oid 精确取，避免重载歧义）
      local function show_func(conn, oid, fqn)
        local out = run_psql(conn, "SELECT pg_get_functiondef(" .. oid .. ");", true)
        if not out or #out == 0 then
          vim.notify("获取函数源码失败: " .. fqn, vim.log.levels.ERROR)
          return
        end
        show_float(out, conn .. "." .. fqn)
      end

      -- 按名字查对象类型（表/视图/物化视图/函数/过程），走本地连接。
      -- 结果按 (conn, name) 缓存，同一对象反复 K 不再查库。
      local obj_cache = {}
      local kind_label = {
        r = "table", p = "table", v = "view", m = "matview",
        f = "function", d = "procedure",
      }

      -- 已知表名集合（每连接缓存一次），用于判断"这个表名已经打完整了"
      local tables_cache = {}
      local function known_table(conn, name)
        local set = tables_cache[conn]
        if not set then
          local url = url_of(conn)
          if not url then
            return false
          end
          local ok, list = pcall(vim.fn["db#adapter#call"], url, "tables", { url }, {})
          set = {}
          if ok then
            for _, n in ipairs(list or {}) do
              set[n] = true
            end
          end
          tables_cache[conn] = set
        end
        return set[name] == true
      end

      local function lookup_object(conn, name)
        obj_cache[conn] = obj_cache[conn] or {}
        local cached = obj_cache[conn][name]
        if cached ~= nil then
          return cached ~= false and cached or nil
        end
        local esc = name:gsub("'", "''")
        local sql = string.format([[
          SELECT 'rel|' || c.relkind::text || '|' || n.nspname || '|' || c.relname
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE c.relname = '%s' AND c.relkind IN ('r','p','v','m')
            AND n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
          UNION ALL
          SELECT 'fn|' || p.prokind::text || '|' || n.nspname || '|' || p.proname
                 || '|' || p.oid::text
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE p.proname = '%s'
            AND n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
        ]], esc, esc)
        local out = run_psql(conn, sql, true) or {}
        local found = {}
        for _, line in ipairs(out) do
          local t, k, sc, nm, oid = line:match("^(%a+)|([%a]+)|([^|]+)|([^|]+)|?(%d*)$")
          if t then
            -- 关系 p(分区表)=table；函数 prokind p=procedure，用 d 区分
            local kind = k
            if t == "fn" and k == "p" then
              kind = "d"
            end
            found[#found + 1] = { kind = kind, schema = sc, name = nm, oid = oid ~= "" and oid or nil }
          end
        end
        -- 同名对象优先取 public schema，其次关系对象（表/视图）优先于函数
        table.sort(found, function(a, b)
          local ap, bp = a.schema == "public", b.schema == "public"
          if ap ~= bp then
            return ap
          end
          return (a.oid == nil) and not (b.oid == nil)
        end)
        local result = found[1] or false
        obj_cache[conn][name] = result
        return result or nil
      end

      -- K 键：判断光标下单词是表/视图/函数，悬浮展示结构（走本地连接）
      local function hover_object()
        local conn = vim.b.db_comp_conn or load_saved()
        if not conn then
          vim.notify("未选择数据库连接", vim.log.levels.WARN, { title = "DB" })
          return
        end
        local word = vim.fn.expand("<cword>")
        if word == "" then
          return
        end
        local obj = lookup_object(conn, word)
        if not obj then
          vim.notify("未找到对象: " .. word, vim.log.levels.WARN, { title = "DB" })
          return
        end
        local label = kind_label[obj.kind] or "?"
        local title = string.format("%s %s.%s", label, obj.schema, obj.name)
        if obj.oid then
          -- 函数/过程：展示签名 + 源码
          local out = run_psql(conn, "SELECT pg_get_functiondef(" .. obj.oid .. ");", true) or {}
          if #out == 0 then
            vim.notify("获取函数源码失败: " .. obj.name, vim.log.levels.ERROR)
            return
          end
          -- 同名重载：在标题里提示数量
          local sig = run_psql(conn, string.format(
            "SELECT pg_get_function_identity_arguments(p.oid) FROM pg_proc p "
              .. "JOIN pg_namespace n ON n.oid = p.pronamespace "
              .. "WHERE p.proname = '%s' AND n.nspname = '%s'",
            obj.name:gsub("'", "''"), obj.schema:gsub("'", "''")
          ), true) or {}
          local body = out
          if #sig > 1 then
            title = string.format("%s %s.%s (%d 个重载)", label, obj.schema, obj.name, #sig)
            body = { "-- 重载签名:" }
            for _, s in ipairs(sig) do
              body[#body + 1] = "--   " .. obj.name .. "(" .. s .. ")"
            end
            body[#body + 1] = ""
            vim.list_extend(body, out)
          end
          show_float(body, title)
        else
          -- 表/视图/物化视图：按配置的列展示（Column/Type/Nullable/Default/Comment…）
          local body = relation_body(conn, obj.schema, obj.name, obj.kind)
          if not body then
            vim.notify("获取结构失败: " .. obj.name, vim.log.levels.ERROR)
            return
          end
          show_float(body, title)
        end
      end

      -- Ruby 模型类名 -> 表名的 K：光标停在 PasAccount 这类模型类名时，
      -- 解析成数据库表并悬浮展示结构（q/Esc 关闭）。复用上方的
      -- load_saved/local_conn_of/lookup_object/show_float。
      -- 非模型（方法/变量/工具类）时回落到 LSP hover，不吞 K。
      -- 安全的 K 回落：仅当有客户端支持 hover 才调 vim.lsp.buf.hover()。
      -- 否则（如没装 ruby LSP，或 ctags-lsp 不支持 hover）会报
      -- 「textDocument/hover is not supported by any server」——不能吞掉不报错。
      local function fallback_hover()
        local ok = vim.lsp.get_clients({ method = "textDocument/hover", bufnr = 0 })
        if #ok > 0 then
          vim.lsp.buf.hover()
        end
      end

      local function ruby_model_hover()
        local ok, modelmap = pcall(require, "db-model-map")
        if not ok then
          fallback_hover()
          return
        end
        local file = vim.api.nvim_buf_get_name(0)
        local root = modelmap.rails_root_of(file)
        if not root then
          fallback_hover()
          return
        end
        local word = vim.fn.expand("<cword>")
        if word == "" then
          fallback_hover()
          return
        end
        local map = modelmap.map_for(root)
        local table_name = map[word]
        if not table_name then
          -- 不是模型类：转交 LSP（若支持 hover）
          fallback_hover()
          return
        end
        local conn = local_conn_of(load_saved()) or load_saved()
        if not conn then
          vim.notify("未选择数据库连接", vim.log.levels.WARN, { title = "DB" })
          return
        end
        local obj = lookup_object(conn, table_name)
        if not obj then
          -- 类在但表解析不到（工具类 or 表不在该连接）：转交 LSP（若支持 hover）
          fallback_hover()
          return
        end
        local label = kind_label[obj.kind] or "?"
        local title = string.format("model %s -> %s %s.%s", word, label, obj.schema, obj.name)
        if obj.oid then
          local out = run_psql(conn, "SELECT pg_get_functiondef(" .. obj.oid .. ");", true) or {}
          if #out == 0 then
            vim.notify("获取函数源码失败: " .. obj.name, vim.log.levels.ERROR)
            return
          end
          show_float(out, title)
        else
          local body = relation_body(conn, obj.schema, obj.name, obj.kind)
          if not body then
            vim.notify("获取结构失败: " .. obj.name, vim.log.levels.ERROR)
            return
          end
          show_float(body, title)
        end
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
            describe(conn, choice.schema, choice.name, choice.kind)
          end
        end)
      end

      -- <leader>fc: 下拉选择 connection
      local function choose_connection()
        pick_conn(function() end)
      end

      -- <leader>fd: 搜对象永远走本地(非TP)连接；没选中过则先选 connection
      local function schema_for_selected()
        local conn = load_saved()
        if not conn then
          pick_conn(function(c)
            search_objects(local_conn_of(c) or c)
          end)
          return
        end
        search_objects(local_conn_of(conn) or conn)
      end

      vim.api.nvim_create_user_command("DBTableSchema", function(a)
        if a.args ~= "" then
          set_selected(a.args)
          -- 显式指定连接时按原样查（含 TP），不走本地映射，作为逃生口
          search_objects(a.args)
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

      -- 给 SQL buffer 打上补全/执行两条线路的连接与键位。
      -- 双线路：补全(b:db/b:dadbod)与结构查看走本地(非TP)连接(快)；
      --         执行(q 键)走选中的连接(可能 TP)，避免本地查询时的慢/网络往返。
      local function setup_sql_buffer(buf, conn)
        -- conn = 选中的连接（执行目标，可能 TP）
        local exec_url = url_of(conn) -- 执行连接 URL

        -- 补全/结构连接：本地(非TP)映射；映射不到则回退到选中连接并提醒
        local comp_conn = local_conn_of(conn)
        local comp_url = comp_conn and url_of(comp_conn) or exec_url
        if not comp_conn then
          vim.notify(
            "未找到 " .. conn .. " 的本地连接，补全回退到该连接",
            vim.log.levels.WARN,
            { title = "DB" }
          )
        end

        vim.b[buf].db = comp_url -- dadbod 空闲连接/补全默认走本地
        vim.b[buf].dadbod = comp_url
        vim.b[buf].db_query_temp = true
        -- 本地(非TP)连接名：结构查看/K 悬浮用（只在 SQL buffer 设）
        vim.b[buf].db_comp_conn = comp_conn or conn

        -- 执行连接信息存独立变量，供 q 键显式传给 :DB
        vim.b[buf].db_exec_conn = conn
        vim.b[buf].db_exec_url = exec_url

        -- 从 buffer 文本里，找光标所在分号段内最后一个 FROM/JOIN/UPDATE/INTO 的表名
        -- （裸名，去 schema 前缀）。dadbod 的补全只认裸表名，不依赖正则，按关键字字面扫。
        local function detect_from_table()
          local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          local cursor = vim.api.nvim_win_get_cursor(0) -- {row(1-based), col(0-based)}
          -- 只取光标之前的文本（当前正在写的语句部分）
          local parts = {}
          for i = 1, cursor[1] do
            if i < cursor[1] then
              parts[#parts + 1] = lines[i]
            else
              parts[#parts + 1] = lines[i]:sub(1, cursor[2])
            end
          end
          local seg = table.concat(parts, "\n")
          -- 只看最后一个 ';' 之后的段落（即当前语句）
          local semi = 0
          while true do
            local p = seg:find(";", semi + 1, true)
            if not p then
              break
            end
            semi = p
          end
          if semi > 0 then
            seg = seg:sub(semi + 1)
          end
          local lower = seg:lower()
          -- 逐个关键字找最后一次出现（Lua pattern 无交替，故分开扫）
          local best_pos, best_name = 0, nil
          for _, kw in ipairs({ "from", "join", "update", "into" }) do
            local init = 1
            while true do
              local s, e, cap = lower:find("%f[%a]" .. kw .. "%f[%A]%s+([%w_%.]+)", init)
              if not s then
                break
              end
              if s > best_pos then
                best_pos, best_name = s, seg:sub(e - #cap + 1, e)
              end
              init = e + 1
            end
          end
          if not best_name then
            return nil
          end
          -- 去 schema 前缀：取最后一个 '.' 之后
          local dot = best_name:find("%.")
          if dot then
            best_name = best_name:sub(dot + 1)
          end
          return best_name
        end

        -- 表切换时才更新 b:db_table 并触发 dadbod 拉该表字段（补全焦点化）。
        -- 必须防抖 + 校验表名有效：否则边打 "pas_sleeve_accts" 会每个前缀都触发一次
        -- fetch（每次约 300ms 且内含一次连库校验），卡到没法打字。
        vim.b[buf].db_table = nil
        vim.b[buf]._db_tracked_table = ""

        local track_timer ---@type uv_timer_t?
        local function refresh_table_tracking()
          if not vim.api.nvim_buf_is_valid(buf) then
            return
          end
          -- 防抖：停手 500ms 后再判断，避免打表名过程中反复触发
          if track_timer then
            track_timer:stop()
            track_timer:close()
            track_timer = nil
          end
          local t = vim.uv.new_timer()
          track_timer = t
          t:start(500, 0, vim.schedule_wrap(function()
            if not track_timer then
              return
            end
            track_timer:stop()
            track_timer:close()
            track_timer = nil
            if not vim.api.nvim_buf_is_valid(buf) then
              return
            end
            local tbl = detect_from_table()
            -- 表名没打完整（不是已知表）就先不动，等打完再说。
            -- 用本地连接校验（补全走的就是它）。
            if not tbl or not known_table(vim.b[buf].db_comp_conn or conn, tbl) then
              return
            end
            if tbl == vim.b[buf]._db_tracked_table then
              return
            end
            vim.b[buf]._db_tracked_table = tbl
            vim.b[buf].db_table = tbl
            -- 同步给 dadbod-completion（它的 buf.table 只在 fetch 时刷新）
            pcall(vim.fn["vim_dadbod_completion#fetch"], buf)
            -- 预取该表字段：dadbod 是按需异步拉的，先踢一次，
            -- 等用户写到 where 时字段已就绪（否则第一次补不出字段）
            pcall(vim.fn["vim_dadbod_completion#omni"], 0, "_db_prefetch_")
            vim.notify("当前表: " .. tbl .. "（已准备字段补全）", vim.log.levels.INFO, {
              title = "DB",
            })
          end))
        end

        vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP", "CursorMovedI" }, {
          buffer = buf,
          callback = refresh_table_tracking,
        })

        -- 执行键：显式携带 db_exec_url，实际执行走选中连接（可能 TP）
        -- 用 b: 变量引用作为 :DB 前缀 URL（dadbod 原生支持 [gtwb]: 变量 eval，
        -- 避免 URL 中 % @ 等字符命令展开出错）。
        if exec_url then
          vim.keymap.set("x", "q", ":DB b:db_exec_url<CR>", {
            buffer = buf, desc = "DB: 执行选中 SQL（走选中连接）" })
          vim.keymap.set("n", "q", ":%DB b:db_exec_url<CR>", {
            buffer = buf, desc = "DB: 执行整个 buffer（走选中连接）" })
        end

        -- K：悬浮显示光标下对象结构（走本地连接）
        vim.keymap.set("n", "K", hover_object, {
          buffer = buf, desc = "DB: 悬浮查看对象结构" })
      end

      -- 实时写盘：查询文件很小，改动即保存，避免 bdelete/<C-w> 退出时反复问是否保存。
      -- 单独负责（不走 auto-save 节流），因为它是临时查询 buffer。
      -- 用 write! 强制覆盖：buffer 是新建的、没走过 read，否则每次都会问「Overwrite existing file?」。
      local function auto_write_sql(buf)
        vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
          buffer = buf,
          callback = function()
            if vim.bo[buf].modified then
              pcall(vim.api.nvim_buf_call, buf, function()
                vim.cmd("silent! write!")
              end)
            end
          end,
        })
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
          auto_write_sql(existing)
          vim.api.nvim_set_current_buf(existing)
          return
        end

        -- 可编辑文件 buffer：带文件名才能落盘。用 bufadd+bufload 读入已有文件，
        -- 否则新 buffer 是空的，一保存就把上次写的 SQL 冲掉。
        local buf = vim.fn.bufadd(name)
        vim.fn.bufload(buf)
        vim.bo[buf].filetype = "sql"
        vim.bo[buf].swapfile = false
        -- 标记为临时查询 buffer：不参与 auto-save.nvim 自动保存
        setup_sql_buffer(buf, conn)
        auto_write_sql(buf)
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

      -- .rb（含 Rakefile 等 ruby 文件）里 K 展示模型对应的表结构。
      -- LazyVim 的 K（Snacks.keymap.set + lsp 过滤器）在 LSP attach 后经 100ms 防抖
      -- 才写入 buffer 局部映射，且始终晚于 FileType/LspAttach。所以在这里：
      --   * LspAttach 后再延迟一点盖回一次，压过 snacks 防抖写入的 Hover；
      --   * BufEnter 兜底，确保进 buffer 后最终生效的一定是本映射。
      -- 非模型词时 ruby_model_hover 会安全回落到 LSP hover（见 fallback_hover）。
      local function bind_ruby_k(buf)
        if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "ruby" then
          return
        end
        vim.keymap.set("n", "K", ruby_model_hover, {
          buffer = buf, desc = "DB: 悬浮查看模型对应的表结构",
        })
      end

      vim.api.nvim_create_autocmd({ "FileType" }, {
        callback = function(ev)
          bind_ruby_k(ev.buf)
        end,
      })
      -- snacks 的 LSP keymap 是 100ms 防抖延后写；LspAttach 后同样延后 200ms 再盖回
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(ev)
          local buf = ev.buf
          vim.defer_fn(function()
            bind_ruby_k(buf)
          end, 200)
        end,
      })
      -- 每次进入 buffer 都盖回，最终一定生效（覆盖面 LazyVim 的 Hover）
      vim.api.nvim_create_autocmd("BufEnter", {
        callback = function(ev)
          bind_ruby_k(ev.buf)
        end,
      })

      -- 退出时把当前选中写盘（load_saved 时已写，这里兜底）
      vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = save_selected,
      })
    end,
  },
}
