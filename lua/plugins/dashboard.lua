--- Dashboard：极简，且默认关闭。
--- 启动 nvim 不再显示 snacks dashboard（直接进入空 buffer 可编辑），
--- 需要时用 :lua Snacks.dashboard() 手动打开。
local function greeting()
  local hour = tonumber(vim.fn.strftime("%H"))
  -- [02:00, 10:00) - morning, [10:00, 18:00) - day, [18:00, 02:00) - evening
  local part_id = math.floor((hour + 6) / 8) + 1
  local day_part = ({ "evening", "morning", "afternoon", "evening" })[part_id]
  local username = os.getenv("USER") or os.getenv("USERNAME") or "user"
  return ("Good %s, %s"):format(day_part, username)
end

return {
  {
    "snacks.nvim",
    opts = {
      dashboard = {
        enabled = false,
        sections = {
          { section = "header" },
          { padding = 2, align = "center", text = { greeting(), hl = "header" } },
        },
      },
    },
  },
}
