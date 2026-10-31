-- Neovim takes its colour scheme from the active package theme (theme pick),
-- with a see-through background so it always sits on the terminal's colour.
-- The theme command writes the scheme name, then the mode (dark or light).
local function read_lines(path)
  local f = io.open(vim.fn.expand(path))
  if not f then return nil end
  local scheme, mode = f:read("*l"), f:read("*l")
  f:close()
  return scheme, mode
end
local scheme, mode = read_lines("~/.local/state/grand-line/current/theme/nvim-theme")
if not scheme then scheme, mode = read_lines("~/.local/state/grand-line/nvim-theme") end
scheme = scheme or "vscode"
mode = mode or "dark"

local by_theme = {
  -- Graphite (dark) and Daylight (light) both use vscode.nvim, in the theme's mode.
  ["vscode"] = { "Mofiqul/vscode.nvim", opts = { transparent = true, style = mode } },
  ["nord"] = { "gbprod/nord.nvim", opts = { transparent = true } },
  ["everforest"] = { "neanias/everforest-nvim", main = "everforest", opts = { transparent_background_level = 1 } },
}

if not by_theme[scheme] then scheme = "vscode" end
vim.o.background = mode
-- All of them are installed up front, so switching theme never waits on a
-- download; only the active one loads.
local specs = {}
for name, spec in pairs(by_theme) do
  spec.lazy = name ~= scheme
  spec.priority = 1000
  table.insert(specs, spec)
end
table.insert(specs, { "LazyVim/LazyVim", opts = { colorscheme = scheme } })
return specs
