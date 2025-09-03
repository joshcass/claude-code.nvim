---@mod claude-code Claude Code Neovim Integration
---@brief [[
--- A plugin for seamless integration between Claude Code AI assistant and Neovim.
--- This plugin provides a terminal-based interface to Claude Code within Neovim.
---
--- Requirements:
--- - Neovim 0.7.0 or later
--- - Claude Code CLI tool installed and available in PATH
--- - plenary.nvim (dependency for git operations)
---
--- Usage:
--- ```lua
--- require('claude-code').setup({
---   -- Configuration options (optional)
--- })
--- ```
---@brief ]]

-- Import modules
local config = require('claude-code.config')
local commands = require('claude-code.commands')
local keymaps = require('claude-code.keymaps')
local file_refresh = require('claude-code.file_refresh')
local terminal = require('claude-code.terminal')
local git = require('claude-code.git')
local version = require('claude-code.version')

local M = {}

-- Make imported modules available
M.commands = commands

-- Store the current configuration
--- @type table
M.config = {}

-- Terminal buffer and window management
--- @type table
M.claude_code = terminal.terminal

--- Get the current active buffer number
--- @return number|nil bufnr Current Claude instance buffer number or nil
local function get_current_buffer_number()
  -- Get current instance from the instances table
  local current_instance = M.claude_code.current_instance
  if current_instance and type(M.claude_code.instances) == 'table' then
    return M.claude_code.instances[current_instance]
  end
  return nil
end

--- Force insert mode when entering the Claude Code window
--- This is a public function used in keymaps
function M.force_insert_mode()
  terminal.force_insert_mode(M, M.config)
end

--- Send current file path to Claude Code terminal
--- This is called from any buffer to send its file path to Claude Code
function M.send_current_file_path()
  -- Get the file path of the currently active buffer (the one we're calling this from)
  local current_file = vim.api.nvim_buf_get_name(0)

  if current_file == '' or vim.fn.isdirectory(current_file) == 1 then
    vim.notify('No file to send to Claude Code', vim.log.levels.WARN)
    return
  end

  -- Get path relative to project root, fallback to full path
  local git_root = git.get_git_root()
  local file_path
  if git_root then
    -- Use string.sub to remove git root path more reliably
    local git_root_with_slash = git_root .. '/'
    if current_file:sub(1, #git_root_with_slash) == git_root_with_slash then
      file_path = current_file:sub(#git_root_with_slash + 1)
    else
      -- File is not under git root, use full path
      file_path = current_file
    end
  else
    -- Fallback to full absolute path if not in git repo
    file_path = current_file
  end

  -- Ensure Claude Code terminal exists, create if needed
  local bufnr = get_current_buffer_number()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    -- Toggle to create/show Claude Code terminal
    M.toggle()
    -- Get the buffer number after toggle
    bufnr = get_current_buffer_number()
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
      vim.notify('Failed to create Claude Code terminal', vim.log.levels.ERROR)
      return
    end
  end

  -- Send the file path to the terminal
  local job_id = vim.b[bufnr].terminal_job_id
  if not job_id then
    vim.notify('Claude Code terminal job not found', vim.log.levels.ERROR)
    return
  end

  vim.api.nvim_chan_send(job_id, file_path)

  -- Switch to Claude Code terminal window and enter insert mode
  local wins = vim.api.nvim_list_wins()
  local target_win = nil

  -- Find the window that contains our Claude buffer
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      target_win = win
      break
    end
  end

  if not target_win then
    -- Terminal buffer exists but no window is showing it, open it
    M.toggle()
    -- Find the window again after toggle
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
        target_win = win
        break
      end
    end
  end

  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
    vim.cmd('startinsert!')
  end

  vim.notify('Sent file path: ' .. file_path, vim.log.levels.INFO)
end

--- Toggle the Claude Code terminal window
--- This is a public function used by commands
function M.toggle()
  terminal.toggle(M, M.config, git)

  -- Set up terminal navigation keymaps after toggling
  local bufnr = get_current_buffer_number()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    keymaps.setup_terminal_navigation(M, M.config)
  end
end

--- Toggle the Claude Code terminal window with a specific command variant
--- @param variant_name string The name of the command variant to use
function M.toggle_with_variant(variant_name)
  if not variant_name or not M.config.command_variants[variant_name] then
    -- If variant doesn't exist, fall back to regular toggle
    return M.toggle()
  end

  -- Store the original command
  local original_command = M.config.command

  -- Set the command with the variant args
  M.config.command = original_command .. ' ' .. M.config.command_variants[variant_name]

  -- Call the toggle function with the modified command
  terminal.toggle(M, M.config, git)

  -- Set up terminal navigation keymaps after toggling
  local bufnr = get_current_buffer_number()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    keymaps.setup_terminal_navigation(M, M.config)
  end

  -- Restore the original command
  M.config.command = original_command
end

--- Get the current version of the plugin
--- @return string version Current version string
function M.get_version()
  return version.string()
end

--- Version information
M.version = version

--- Setup function for the plugin
--- @param user_config? table User configuration table (optional)
function M.setup(user_config)
  -- Parse and validate configuration
  -- Don't use silent mode for regular usage - users should see config errors
  M.config = config.parse_config(user_config, false)

  -- Set up autoread option
  vim.o.autoread = true

  -- Set up file refresh functionality
  file_refresh.setup(M, M.config)

  -- Register commands
  commands.register_commands(M)

  -- Register keymaps
  keymaps.register_keymaps(M, M.config)
end

return M
