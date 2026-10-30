return {
  "keaising/im-select.nvim",
  config = function()
    require("im_select").setup({
      -- Windows/WSL 下默认英文输入法的 ID 通常是 1033
      default_im_select = "1033",
      -- Keep the IME as-is on entering insert mode. By default the plugin
      -- restores the IME used in the previous insert session, which forces
      -- Chinese back on every `i` even when English is wanted.
      set_previous_events = {},
    })
  end,
}
