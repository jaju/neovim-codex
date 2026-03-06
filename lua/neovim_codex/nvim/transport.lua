local M = {}
M.__index = M

local function close_handle(handle)
  if handle and not handle:is_closing() then
    handle:close()
  end
end

function M.new(opts)
  opts = opts or {}

  local self = setmetatable({
    cmd = opts.cmd or { "codex", "app-server" },
    cwd = opts.cwd,
    env = opts.env,
    handle = nil,
    stdin = nil,
    stdout = nil,
    stderr = nil,
    pid = nil,
  }, M)

  return self
end

function M:is_running()
  return self.handle ~= nil and not self.handle:is_closing()
end

function M:start(callbacks)
  if self:is_running() then
    return false, "transport already running"
  end

  local uv = vim.uv
  self.stdin = uv.new_pipe(false)
  self.stdout = uv.new_pipe(false)
  self.stderr = uv.new_pipe(false)

  local spawn_opts = {
    args = vim.list_slice(self.cmd, 2),
    stdio = { self.stdin, self.stdout, self.stderr },
    cwd = self.cwd,
    env = self.env,
  }

  self.handle, self.pid = uv.spawn(self.cmd[1], spawn_opts, function(code, signal)
    if callbacks and callbacks.on_exit then
      callbacks.on_exit(code, signal)
    end
    close_handle(self.stdin)
    close_handle(self.stdout)
    close_handle(self.stderr)
    close_handle(self.handle)
    self.stdin = nil
    self.stdout = nil
    self.stderr = nil
    self.handle = nil
    self.pid = nil
  end)

  if not self.handle then
    close_handle(self.stdin)
    close_handle(self.stdout)
    close_handle(self.stderr)
    self.stdin = nil
    self.stdout = nil
    self.stderr = nil
    return false, string.format("failed to spawn command: %s", self.cmd[1])
  end

  self.stdout:read_start(function(err, data)
    if err and callbacks and callbacks.on_stderr then
      callbacks.on_stderr(string.format("stdout error: %s", err))
      return
    end
    if data and callbacks and callbacks.on_stdout then
      callbacks.on_stdout(data)
    end
  end)

  self.stderr:read_start(function(err, data)
    if err and callbacks and callbacks.on_stderr then
      callbacks.on_stderr(string.format("stderr error: %s", err))
      return
    end
    if data and callbacks and callbacks.on_stderr then
      callbacks.on_stderr(data)
    end
  end)

  return true, nil, self.pid
end

function M:write(payload)
  if not self.stdin or self.stdin:is_closing() then
    return false, "stdin is not available"
  end
  self.stdin:write(payload)
  return true, nil
end

function M:stop()
  if self.handle and not self.handle:is_closing() then
    self.handle:kill("sigterm")
  end
end

return M
