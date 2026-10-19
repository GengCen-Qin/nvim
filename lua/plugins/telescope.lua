-- Telescope：补上 keymaps.lua 里 <leader>/ 全局搜索所依赖的 fuzzy finder。
--
-- 为什么需要单独装：LazyVim 默认用 snacks.picker（本机没有 telescope），
-- 而 keymaps.lua 里的 <leader>/ 走 "<cmd>Telescope live_grep<cr>"，
-- 没装 telescope 时一按就报 "Not an editor command: Telescope"。
--
-- 这里只装 telescope 本身、**不**启用 LazyVim 的 editor.telescope extra，
-- 因此 vim.g.lazyvim_picker 仍是 "auto"：
--   * LazyVim 自带的查找键位（<leader>ff / <leader>sg ...）继续走 snacks.picker，
--     lazy-read 的注释搜索也继续用 Snacks.picker，互不影响；
--   * 只有你自己的 <leader>/ 用 telescope（按需加载，不占启动时间）。
-- 若想让 telescope 全面接管，改为启用 extra 即可：
--   { import = "lazyvim.plugins.extras.editor.telescope" }
return {
  {
    "nvim-telescope/telescope.nvim",
    -- cmd 让 lazy.nvim 注册 :Telescope 命令桩，于是 keymaps.lua 里的
    -- "<cmd>Telescope live_grep<cr>" 首次按下时才加载插件（懒加载）
    cmd = "Telescope",
    version = false, -- telescope 只发过一个 release，用 HEAD
    dependencies = {
      "nvim-lua/plenary.nvim",
      {
        -- 原生 fzf 排序器，显著加快大仓库搜索；本机有 make 才构建
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
        cond = function()
          return vim.fn.executable("make") == 1
        end,
      },
    },
    config = function()
      require("telescope").setup({
        defaults = {
          -- 输入按「字面字符串」搜（rg --fixed-strings），不当正则用。
          -- live_grep 默认把输入原样交给 ripgrep 当正则，粘代码片段时里面的
          -- ( { " . 等元字符会让 rg 报 regex parse error 或匹配到别处，
          -- 表现就是「明明有这段代码却搜不到」。
          -- 这里整条命令照抄 telescope 默认值，只多一个 --fixed-strings
          -- （--smart-case 在字面模式下依然生效：全小写则忽略大小写）。
          vimgrep_arguments = {
            "rg",
            "--color=never",
            "--no-heading",
            "--with-filename",
            "--line-number",
            "--column",
            "--smart-case",
            "--fixed-strings",
          },
        },
      })
      -- fzf 扩展没构建成功也不影响 telescope 基本可用，故 pcall 兜住
      pcall(require("telescope").load_extension, "fzf")
    end,
  },
}
