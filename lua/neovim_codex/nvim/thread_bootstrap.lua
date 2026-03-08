local M = {}

local uv = vim.uv or vim.loop

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function present(value)
  return value ~= nil and value ~= vim.NIL and value ~= ""
end

local function maybe_text(value)
  if not present(value) then
    return nil
  end
  return tostring(value)
end

local function copy(value)
  if type(value) ~= "table" then
    return value
  end
  return vim.deepcopy(value)
end

local function joinpath(...)
  if vim.fs and vim.fs.joinpath then
    return vim.fs.joinpath(...)
  end
  return table.concat({ ... }, "/")
end

local function read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, tostring(lines)
  end
  return table.concat(lines, "\n"), nil
end

local function collect_agents_layers(cwd)
  if not present(cwd) then
    return {}
  end

  local current = cwd
  local seen = {}
  local reverse_layers = {}

  while current and not seen[current] do
    seen[current] = true

    local candidate = joinpath(current, "AGENTS.md")
    if uv.fs_stat(candidate) then
      local content, err = read_file(candidate)
      reverse_layers[#reverse_layers + 1] = {
        path = candidate,
        content = content,
        read_error = err,
      }
    end

    local parent = vim.fs.dirname(current)
    if not parent or parent == current then
      break
    end
    current = parent
  end

  local layers = {}
  for index = #reverse_layers, 1, -1 do
    layers[#layers + 1] = reverse_layers[index]
  end
  return layers
end

local function normalize_requested(params)
  return {
    cwd = maybe_text(params.cwd),
    model = maybe_text(params.model),
    model_provider = maybe_text(params.modelProvider),
    service_name = maybe_text(params.serviceName),
    personality = maybe_text(params.personality),
    approval_policy = maybe_text(params.approvalPolicy),
    sandbox = copy(params.sandbox),
    ephemeral = params.ephemeral,
    base_instructions = maybe_text(params.baseInstructions),
    developer_instructions = maybe_text(params.developerInstructions),
  }
end

function M.capture(opts)
  opts = opts or {}
  local thread = assert(opts.thread, "thread is required")
  local params = opts.params or {}
  local cwd = maybe_text(thread.cwd) or maybe_text(params.cwd)

  return {
    captured_at = now_iso(),
    origin = maybe_text(opts.origin) or "thread/start",
    requested = normalize_requested(params),
    thread = {
      id = thread.id,
      name = maybe_text(thread.name),
      cwd = cwd,
      ephemeral = thread.ephemeral == true,
      model_provider = maybe_text(thread.modelProvider),
      cli_version = maybe_text(thread.cliVersion),
      source = copy(thread.source),
      git_info = copy(thread.gitInfo),
    },
    agents_layers = collect_agents_layers(cwd),
  }
end

local function push(lines, ...)
  for _, value in ipairs({ ... }) do
    lines[#lines + 1] = value
  end
end

local function render_scalar(value, fallback)
  if not present(value) then
    return fallback or "_server default_"
  end
  return string.format("`%s`", tostring(value))
end

local function render_code_block(lines, lang, text)
  push(lines, string.format("```%s", lang or "text"))
  if present(text) then
    for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
      lines[#lines + 1] = line
    end
  end
  lines[#lines + 1] = "```"
end

function M.render(thread)
  local bootstrap = thread and thread.bootstrap or nil
  if not thread then
    return {
      "# Codex Thread Bootstrap",
      "",
      "No thread was selected.",
    }
  end

  if not bootstrap then
    return {
      "# Codex Thread Bootstrap",
      "",
      string.format("No bootstrap snapshot is available for thread `%s`.", thread.id),
      "",
      "This inspector only knows about threads that were started or resumed through `neovim-codex` in the current NeoVim session.",
    }
  end

  local lines = {
    "# Codex Thread Bootstrap",
    "",
    "This report shows the startup context captured by `neovim-codex` before the first message sent from this session.",
    "It does not include later user turns or a raw dump of Codex's internal prompt assembly.",
    "",
    "## Thread",
    "",
    string.format("- id: `%s`", thread.id),
    string.format("- name: %s", render_scalar(thread.name, "_unnamed_")),
    string.format("- captured_at: `%s`", bootstrap.captured_at or "-"),
    string.format("- captured_via: `%s`", bootstrap.origin or "-"),
    string.format("- cwd: %s", render_scalar((bootstrap.thread or {}).cwd, "_unknown_")),
    string.format("- model_provider: %s", render_scalar((bootstrap.thread or {}).model_provider, "_server default_")),
    string.format("- requested_model: %s", render_scalar((bootstrap.requested or {}).model, "_server default_")),
    string.format("- requested_model_provider: %s", render_scalar((bootstrap.requested or {}).model_provider, "_server default_")),
    string.format("- requested_service_name: %s", render_scalar((bootstrap.requested or {}).service_name, "_server default_")),
    string.format("- personality: %s", render_scalar((bootstrap.requested or {}).personality, "_none_")),
    string.format("- approval_policy: %s", render_scalar((bootstrap.requested or {}).approval_policy, "_server default_")),
    string.format("- ephemeral: `%s`", tostring((bootstrap.thread or {}).ephemeral == true)),
  }

  if type((bootstrap.requested or {}).sandbox) == "table" then
    push(lines, "- sandbox:")
    render_code_block(lines, "lua", vim.inspect(bootstrap.requested.sandbox))
  else
    push(lines, string.format("- sandbox: %s", render_scalar((bootstrap.requested or {}).sandbox, "_server default_")))
  end

  push(lines, "", "## Base Instructions", "", "- source: upstream Codex default", string.format("- override: %s", render_scalar((bootstrap.requested or {}).base_instructions, "_none_")))

  if present((bootstrap.requested or {}).base_instructions) then
    push(lines, "")
    render_code_block(lines, "text", bootstrap.requested.base_instructions)
  else
    push(lines, "- `neovim-codex` did not send `baseInstructions` for this thread.")
  end

  push(
    lines,
    "",
    "## Developer Layer",
    "",
    "- built-in Codex developer guidance still applies for approvals, sandboxing, and tool behavior.",
    string.format("- explicit developer overlay: %s", render_scalar((bootstrap.requested or {}).developer_instructions, "_none_"))
  )

  if present((bootstrap.requested or {}).developer_instructions) then
    push(lines, "")
    render_code_block(lines, "text", bootstrap.requested.developer_instructions)
  end

  push(lines, "", "## Shared Repo Context", "")

  local layers = bootstrap.agents_layers or {}
  if #layers == 0 then
    push(lines, "- No `AGENTS.md` file was captured from the thread cwd upward.")
  else
    push(lines, string.format("- captured `AGENTS.md` layers: `%d`", #layers))
    for index, layer in ipairs(layers) do
      push(lines, "", string.format("### AGENTS Layer %d", index), "", string.format("- path: `%s`", layer.path))
      if layer.read_error then
        push(lines, string.format("- read_error: `%s`", layer.read_error))
      else
        push(lines, "- content:")
        render_code_block(lines, "markdown", layer.content)
      end
    end
  end

  push(
    lines,
    "",
    "## Notes",
    "",
    "- This inspector is plugin-owned. It is exact for the bootstrap snapshot captured in this NeoVim session, and intentionally avoids claiming hidden Codex prompt text it cannot read.",
    "- If you want different thread behavior, leave base instructions alone and change only the additive developer overlay or other thread settings."
  )

  return lines
end

return M
