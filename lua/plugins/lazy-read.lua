-- LazyRead：把「只给自己看、不进 git」的行级注释挂在代码行上
-- （Sublime Text 插件 lazy_read 的 nvim 版，实现见 lua/lazy-read.lua）
--
--   cc          当前行添加 / 编辑注释（弹输入框，回车保存）
--   cv          浮窗查看当前行注释的完整内容
--   <leader>cf  搜索所有注释（snacks picker，回车跳转）
--   <leader>cD  删除当前行注释
--   <leader>ct  显示 / 隐藏行尾注释预览
--
-- 数据与 Sublime 版共用 ~/.lazyRead/notes.json，两边互相可见；
-- 注释不写进源码文件，所以永远不会进 git。
--
-- 注意：
--   * 这里**不声明 lazy = true**。LazyVim 以 lazy = false 常驻加载 snacks.nvim，
--     重复声明会覆盖掉它，导致 snacks 变懒加载并影响 dashboard / notifier 等。
--     只挂 init / keys 即安全。
--   * cc 覆盖了 nvim 内置的「修改整行」，需要时用 S 代替。
--   * <leader>cf 覆盖了 LazyVim 的格式化（conform.nvim）。要换键改下面一行即可，
--     例如把搜索挪到 <leader>cF、把格式化还给 <leader>cf。
return {
  {
    "folke/snacks.nvim",
    init = function()
      require("lazy-read").setup()
    end,
    keys = {
      {
        "cc",
        function()
          require("lazy-read").add_or_edit()
        end,
        desc = "LazyRead: 添加/编辑本行注释",
      },
      {
        "cv",
        function()
          require("lazy-read").show()
        end,
        desc = "LazyRead: 查看本行注释",
      },
      {
        "<leader>cf",
        function()
          require("lazy-read").search()
        end,
        desc = "LazyRead: 搜索注释",
      },
      {
        "<leader>cD",
        function()
          require("lazy-read").delete()
        end,
        desc = "LazyRead: 删除本行注释",
      },
      {
        "<leader>ct",
        function()
          require("lazy-read").toggle()
        end,
        desc = "LazyRead: 显示/隐藏注释",
      },
    },
  },
}
