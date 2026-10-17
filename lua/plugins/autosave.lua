return {
  "Pocco81/auto-save.nvim",
  event = { "InsertLeave", "BufLeave" }, -- 关键：在离开插入模式或切换窗口时触发
  config = function()
    require("auto-save").setup({
      enabled = true,
      write_all_buffers = false, -- 只保存当前修改的文件，更安全
      trigger_events = { "InsertLeave", "BufLeave" }, -- 停止打字或切换标签页时保存
      debounce_delay = 500, -- 延迟 500ms 保存，避免频繁写入
      -- 临时 SQL buffer（<leader>fq）标记了 b:db_query_temp，不自动保存
      condition = function(buf)
        -- 定时器回调时 buffer 可能已关闭（auto-save 的 debounce 用了 vim.defer_fn，
        -- 但自己没对失效 buffer 兜底），先校验，避免 vim.b[buf] 抛 Invalid buffer id
        if not vim.api.nvim_buf_is_valid(buf) then
          return false
        end
        if vim.b[buf].db_query_temp then
          return false
        end
        return vim.bo[buf].modifiable and vim.bo[buf].buftype == ""
      end,
      execution_message = {
        message = function()
          return "AutoSaved"
        end,
        dim = 0.18,
        cleaning_interval = 1250,
      },
    })
  end,
}
