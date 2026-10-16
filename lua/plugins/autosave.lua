return {
  "Pocco81/auto-save.nvim",
  event = { "InsertLeave", "BufLeave" }, -- 关键：在离开插入模式或切换窗口时触发
  config = function()
    require("auto-save").setup({
      enabled = true,
      write_all_buffers = false, -- 只保存当前修改的文件，更安全
      trigger_events = { "InsertLeave", "BufLeave" }, -- 停止打字或切换标签页时保存
      debounce_delay = 500, -- 延迟 500ms 保存，避免频繁写入
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
