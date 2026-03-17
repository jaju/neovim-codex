local M = {}

local unpack_args = table.unpack or unpack

function M.new(callback)
  local scheduled = false
  local disposed = false
  local latest_args = nil

  local function run()
    scheduled = false
    if disposed then
      latest_args = nil
      return
    end

    local args = latest_args or {}
    latest_args = nil
    callback(unpack_args(args))
  end

  return {
    trigger = function(_, ...)
      if disposed then
        return false
      end

      latest_args = { ... }
      if scheduled then
        return false
      end

      scheduled = true
      vim.schedule(run)
      return true
    end,
    dispose = function()
      disposed = true
      latest_args = nil
    end,
  }
end

return M
