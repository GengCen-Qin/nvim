-- fzf-lua：全局 picker（替代 snacks.picker / telescope）
--
-- 由 LazyVim 的 editor.fzf extra 引入（见 lazyvim.json），这里只做两件事：
--   1. 收敛查找过滤：找文件 / 全局搜索都不显示 cpp/js/cs 等代码文件
--   2. 保护 LSP 键位：fzf extra 默认会把 gd/gr/gI/gy 重绑成 FzfLua 的 LSP 命令，
--      其中 gd 是 ctags 跳转（ctags_lsp 提供），必须保持原样

-- 查找时不想看到的代码文件（字面匹配，无正则）
local exclude = {
  "*.cpp",
  "*.cc",
  "*.cxx",
  "*.hpp",
  "*.h",
  "*.js",
  "*.mjs",
  "*.ts",
  "*.cs",
  "*.csproj",
}

-- rg：`rg --files` 用 -g "!xxx"，grep 用 --glob "!xxx"，各自拼进 rg_opts 字符串
local rg_files = { "--color=never --files -g \"!.git\" -g \"!.jj\"" }
local rg_grep = { "--column --line-number --no-heading --color=always --smart-case " }
for _, g in ipairs(exclude) do
  rg_files[#rg_files + 1] = ('-g "!%s"'):format(g)
  rg_grep[#rg_grep + 1] = ('--glob "!%s"'):format(g)
end

return {
  {
    "ibhagwan/fzf-lua",
    opts = {
      files = {
        rg_opts = table.concat(rg_files, " "),
        -- 若走 fd 分支也一并排除（fd 用 --exclude=，语法不同，单列一份）
        fd_opts = "--color=never --type f --type l --exclude .git --exclude .jj "
          .. table.concat(vim.tbl_map(function(g)
            return ("--exclude=%s"):format(g)
          end, exclude), " "),
      },
      grep = {
        rg_opts = table.concat(rg_grep, " "),
      },
    },
  },

  {
    -- 还原 fzf extra 覆盖掉的 LSP 键位，回到 LazyVim 默认：
    -- gd 走 ctags_lsp 的定义跳转，gr/gI/gy 走 vim.lsp.buf.*
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ["*"] = {
          keys = {
            { "gd", vim.lsp.buf.definition, desc = "Goto Definition", has = "definition" },
            { "gr", vim.lsp.buf.references, desc = "References", nowait = true },
            { "gI", vim.lsp.buf.implementation, desc = "Goto Implementation" },
            { "gy", vim.lsp.buf.type_definition, desc = "Goto T[y]pe Definition" },
          },
        },
      },
    },
  },
}
