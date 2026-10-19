--- Dashboard：极简
--- 去掉快捷键操作说明和最近项目，只保留 header 图和问候语。
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
        sections = {
          { section = "header" },
          { padding = 2, align = "center", text = { greeting(), hl = "header" } },
        },
      },
    },
  },
}
