local api = vim.api

local M = {}


function M.apply_winopts(win, opts)
  if not opts then return end
  assert(
    type(opts) == 'table',
    'winopts must be a table, not ' .. type(opts) .. ': ' .. vim.inspect(opts)
  )
  for k, v in pairs(opts) do
    if k == 'width' then
      api.nvim_win_set_width(win, v)
    elseif k == 'height' then
      api.nvim_win_set_height(win, v)
    else
      api.nvim_win_set_option(win, k, v)
    end
  end
end


--- Same as M.pick_one except that it skips the selection prompt if `items`
--  contains exactly one item.
function M.pick_if_many(items, prompt, label_fn, cb)
  if #items == 1 then
    cb(items[1])
  else
    M.pick_one(items, prompt, label_fn, cb)
  end
end


function M.pick_one(items, prompt, label_fn, cb)
  local choices = {prompt}
  for i, item in ipairs(items) do
    table.insert(choices, string.format('%d: %s', i, label_fn(item)))
  end
  local choice = vim.fn.inputlist(choices)
  if choice < 1 or choice > #items then
    return cb(nil)
  end
  return cb(items[choice])
end


local function with_indent(indent, fn)
  local move_cols = function(hl_group)
    local end_col = hl_group[3] == -1 and -1 or hl_group[3] + indent
    return {hl_group[1], hl_group[2] + indent, end_col}
  end
  return function(...)
    local text, hl_groups = fn(...)
    return string.rep(' ', indent) .. text, vim.tbl_map(move_cols, hl_groups)
  end
end


function M.new_tree(opts)
  local expanded = {}

  local expand = function(layer, value, lnum, context)
    expanded[value] = true
    opts.fetch_children(value, function(children)
      local ctx = {
        actions = context.actions,
        indent = context.indent + 2,
      }
      local render = with_indent(ctx.indent, opts.render_child)
      layer.render(children, render, ctx, lnum + 1)
    end)
  end

  local collapse = function(layer, value, lnum, context)
    if not expanded[value] then
      return
    end
    local num_vars = 1
    local collapse_child
    collapse_child = function(parent)
      num_vars = num_vars + 1
      if expanded[parent] then
        expanded[parent] = false
        for _, child in pairs(opts.get_children(parent)) do
          collapse_child(child)
        end
      end
    end
    expanded[value] = nil
    for _, child in ipairs(opts.get_children(value)) do
      collapse_child(child)
    end
    layer.render({}, tostring, context, lnum + 1, lnum + num_vars)
  end

  local self
  self = {
    toggle = function(layer, value, lnum, context)
      if expanded[value] then
        collapse(layer, value, lnum, context)
      elseif opts.has_children(value) then
        expand(layer, value, lnum, context)
      end
    end,

    render = function(layer, value)
      layer.render({value}, opts.render_parent)
      if not opts.has_children(value) then
        return
      end
      local context = {
        indent = 0,
        actions = {
          { label = "Expand", fn = self.toggle, }
        }
      }
      opts.fetch_children(value, function(children)
        layer.render(children, opts.render_child, context)
      end)
    end,
  }
  return self
end


do
  function M.get_last_lnum(bufnr)
    return api.nvim_buf_call(bufnr, function() return vim.fn.line('$') - 1 end)
  end

  function M.layer(buf)
    assert(buf, 'Need a buffer to operate on')
    local marks = {}
    local ns = api.nvim_create_namespace('dap.ui_layer_' .. buf)
    local nshl = api.nvim_create_namespace('dap.ui_layer_hl_' .. buf)
    return {
      __marks = marks,
      --- Render the items and associate each item to the rendered line
      -- The item and context can then be retrieved using `.get(lnum)`
      --
      -- lines between start and end_ are replaced
      -- If start == end_, new lines are inserted at the given position
      -- If start == nil, appends to the end of the buffer
      --
      -- start is 0-indexed
      -- end_ is 0-indexed exclusive
      render = function(xs, render_fn, context, start, end_)
        start = start or M.get_last_lnum(buf)
        end_ = end_ or start
        if end_ > start then
          local extmarks = api.nvim_buf_get_extmarks(buf, ns, {start, 0}, {end_ - 1, -1}, {})
          for _, mark in pairs(extmarks) do
            local mark_id = mark[1]
            marks[mark_id] = nil
            api.nvim_buf_del_extmark(buf, ns, mark_id)
          end
        end
        -- This is a dummy call to insert new lines in a region
        -- the loop below will add the actual values
        local lines = vim.tbl_map(function() return '' end, xs)
        api.nvim_buf_set_lines(buf, start, end_, true, lines)

        for i = start, start + #lines - 1 do
          local item = xs[i + 1 - start]
          local text, hl_regions = render_fn(item)
          text = text:gsub('\n', ' ') -- Might make sense to change this and preserve newlines?
          api.nvim_buf_set_lines(buf, i, i + 1, true, {text})
          if hl_regions then
            for _, hl_region in pairs(hl_regions) do
              api.nvim_buf_add_highlight(
                buf, nshl, hl_region[1], i, hl_region[2], hl_region[3])
            end
          end
          local line = api.nvim_buf_get_lines(buf, i, i + 1, true)[1]
          local mark_id = api.nvim_buf_set_extmark(buf, ns, i, 0, {end_col=(#line - 1)})
          marks[mark_id] = { mark_id = mark_id, item = item, context = context }
        end
      end,

      --- Get the information associated with a line
      --
      -- lnum is 0-indexed
      get = function(lnum, start_col, end_col)
        local line = api.nvim_buf_get_lines(buf, lnum, lnum + 1, true)[1]
        start_col = start_col or 0
        end_col = end_col or #line
        local start = {lnum, start_col}
        local end_ = {lnum, end_col}
        local extmarks = api.nvim_buf_get_extmarks(buf, ns, start, end_, {})
        if not extmarks or #extmarks == 0 then
          return
        end
        assert(#extmarks == 1, 'Expecting only a single mark per line and region: ' .. vim.inspect(extmarks))
        local extmark = extmarks[1]
        return marks[extmark[1]]
      end
    }
  end
end


return M
