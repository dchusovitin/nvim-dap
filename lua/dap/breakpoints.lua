local api = vim.api
local non_empty = require('dap.utils').non_empty

local bp_by_sign = {}
local ns = 'dap_breakpoints'
local M = {}


local function get_breakpoint_signs(bufexpr)
  if bufexpr then
    return vim.fn.sign_getplaced(bufexpr, {group = ns})
  end
  local bufs_with_signs = vim.fn.sign_getplaced()
  local result = {}
  for _, buf_signs in ipairs(bufs_with_signs) do
    buf_signs = vim.fn.sign_getplaced(buf_signs.bufnr, {group = ns})[1]
    if #buf_signs.signs > 0 then
      table.insert(result, buf_signs)
    end
  end
  return result
end


function M.remove(bufnr, lnum)
  local placements = vim.fn.sign_getplaced(bufnr, { group = ns; lnum = lnum; })
  local signs = placements[1].signs
  if signs and #signs > 0 then
    for _, sign in pairs(signs) do
      vim.fn.sign_unplace(ns, { buffer = bufnr; id = sign.id; })
      bp_by_sign[sign.id] = nil
    end
    return true
  else
    return false
  end
end


function M.toggle(opts, bufnr, lnum)
  opts = opts or {}
  bufnr = bufnr or api.nvim_get_current_buf()
  lnum = lnum or api.nvim_win_get_cursor(0)[1]
  if M.remove(bufnr, lnum) and not opts.replace then
    return
  end
  local sign_id = vim.fn.sign_place(
    0,
    ns,
    non_empty(opts.log_message) and 'DapLogPoint' or 'DapBreakpoint',
    bufnr,
    { lnum = lnum; priority = 11; }
  )
  if sign_id ~= -1 then
    bp_by_sign[sign_id] = {
      condition = opts.condition,
      logMessage = opts.log_message,
      hitCondition = opts.hit_condition
    }
  end
end


function M.set(opts, bufnr, lnum)
  opts = opts or {}
  opts.replace = true
  M.toggle(opts, bufnr, lnum)
end


--- Returns all breakpoints grouped by bufnr
function M.get(bufexpr)
  local signs = get_breakpoint_signs(bufexpr)
  if #signs == 0 then
    return {}
  end
  local result = {}
  for _, buf_bp_signs in pairs(signs) do
    local breakpoints = {}
    local bufnr = buf_bp_signs.bufnr
    result[bufnr] = breakpoints
    for _, bp in pairs(buf_bp_signs.signs) do
      local bp_entry = bp_by_sign[bp.id] or {}
      table.insert(breakpoints, {
        line = bp.lnum;
        condition = bp_entry.condition;
        hitCondition = bp_entry.hitCondition;
        logMessage = bp_entry.logMessage;
      })
    end
  end
  return result
end


function M.clear()
  vim.fn.sign_unplace(ns)
  bp_by_sign = {}
end


do
  local function not_nil(x)
    return x ~= nil
  end

  function M.to_qf_list(breakpoints)
    local qf_list = {}
    for bufnr, buf_bps in pairs(breakpoints) do
      for _, bp in pairs(buf_bps) do
        local text_parts = {
          unpack(api.nvim_buf_get_lines(bufnr, bp.line - 1, bp.line, false), 1),
          non_empty(bp.logMessage) and "Log message: " .. bp.logMessage,
          non_empty(bp.condition) and "Condition: " .. bp.condition,
          non_empty(bp.hitCondition) and "Hit condition: " .. bp.hitCondition,
        }
        local text = table.concat(vim.tbl_filter(not_nil, text_parts), ', ')
        table.insert(qf_list, {
          bufnr = bufnr,
          lnum = bp.line,
          col = 0,
          text = text,
        })
      end
    end
    return qf_list
  end
end


return M
