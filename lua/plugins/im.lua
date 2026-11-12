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

    -- Focus back on nvim (Alt-Tab back to the terminal window, etc.) => English.
    -- Skip it in insert/replace/cmdline/terminal mode so returning to the
    -- terminal never interrupts Chinese you were in the middle of typing.
    -- Note: FocusGained only fires when the terminal *window* regains focus;
    -- switching between panes inside zellij/tmux does not trigger it, because
    -- neither multiplexer forwards pane-level focus events.
    local focus_group = vim.api.nvim_create_augroup("im-focus", { clear = true })
    vim.api.nvim_create_autocmd("FocusGained", {
      group = focus_group,
      callback = function()
        if vim.api.nvim_get_mode().mode:match("^[iRct]") then
          return
        end
        if vim.fn.executable("im-select.exe") == 1 then
          vim.fn.system({ "im-select.exe", "1033" })
        end
      end,
    })
  end,
}
