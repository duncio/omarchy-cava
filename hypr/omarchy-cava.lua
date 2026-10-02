-- Cava as a desktop backdrop, installed by the omarchy-cava plugin.
--
-- Cava is an ncurses TUI and cannot be a layer surface on its own, so it runs in
-- a transparent terminal window of its own (see scripts/backdrop). Hyprland has
-- no "stay out of the way while other windows are open" effect, so the rule
-- below and the bookkeeping after it move that window in and out of a special
-- workspace instead. Everything ends where it started: the process keeps
-- running, so the bars come back the moment a workspace empties again.

local CLASS = "omarchy-cava" -- the terminal is launched with this app id
local HIDDEN = "special:omarchy-cava"

hl.window_rule({
  match = { class = "^" .. CLASS .. "$" },

  -- Out of sight until the first empty workspace asks for it.
  workspace = HIDDEN,

  float = true,

  -- Full width, and as tall as the terminal asked to be. The terminal is
  -- launched with a size in terminal cells (scripts/backdrop), which is the only
  -- size that means the same thing across fonts and font sizes; keeping
  -- window_h and anchoring the bottom edge to the screen keeps the bars flush
  -- with it without any font math here. Resizing to the window's own height is
  -- a no-op, which is exactly the point: the width follows the monitor and the
  -- height is left alone.
  size = { "monitor_w", "window_h" },
  move = { "0", "monitor_h-window_h" },

  -- Nothing but the bars should show, and nothing should change when the window
  -- is moved: no border, shadow, blur or animation, and no theme opacity.
  tag = "-default-opacity",
  opacity = "1.0 override 1.0 override",
  decorate = false,
  border_size = 0,
  rounding = 0,
  no_shadow = true,
  no_blur = true,
  no_anim = true,

  -- Scenery, not a window to type in.
  no_initial_focus = true,
  no_focus = true,
  no_follow_mouse = true,
})

-- Where the window is, so the events that arrive in the middle of a move settle
-- instead of queueing up a second one, and so the next event can tell an already
-- placed backdrop from one that has to move. window.open is the only event that
-- can introduce it, and window.destroy arrives empty, so liveness is read back
-- off the workspace the window was last sent to.
local address, workspace = nil, HIDDEN

local function listed(where, who)
  for _, window in ipairs(hl.get_workspace_windows(where)) do
    if window.address == who then
      return true
    end
  end

  return false
end

local function send(to)
  address, workspace = address, to
  hl.dispatch(hl.dsp.window.move({
    window = "address:" .. address,
    workspace = to,
    follow = false,
  }))
end

local function occupied(id)
  for _, window in ipairs(hl.get_workspace_windows(id)) do
    if window.class ~= CLASS then
      return true
    end
  end

  return false
end

-- A reload runs this file again while the backdrop is still running, which
-- leaves the bookkeeping above empty and the window where it was. Pick it back
-- up where it actually is, so the next window event settles it instead of
-- deciding it is gone.
for _, window in ipairs(hl.get_windows()) do
  if window.class == CLASS then
    address = window.address

    if window.workspace.name ~= HIDDEN then
      workspace = window.workspace.id
    end
  end
end

-- A backdrop belongs to the workspace in front and to nothing else, so an empty
-- one shows it and any other window at all takes the screen back. Where it
-- already is decides whether anything has to move: two empty workspaces in a row
-- have to hand it over, not leave it behind on the one it came from.
local function place()
  local active = hl.get_active_workspace()

  if not active then
    return
  end

  if occupied(active.id) then
    if workspace ~= HIDDEN then
      send(HIDDEN)
    end
  elseif workspace ~= active.id then
    send(active.id)
  end
end

-- The same, for everything that happens after the window exists. A backdrop that
-- died without a close event of its own, killed or crashed, is no longer listed
-- on the workspace it was sent to, and there is nothing left to show.
local function sync()
  if address == nil or not listed(workspace, address) then
    address, workspace = nil, HIDDEN
    return
  end

  place()
end

hl.on("window.open", function(window)
  if window.class == CLASS then
    -- Freshly opened and still on the hidden workspace, so it is placed without
    -- being looked up first: this early in its life the window need not be
    -- listed on any workspace yet.
    address, workspace = window.address, HIDDEN
    place()
  else
    sync()
  end
end)

-- window.close still counts the window on its way out, so it is only used to
-- forget the backdrop; window.destroy follows and does the counting.
hl.on("window.close", function(window)
  if window.class == CLASS then
    address, workspace = nil, HIDDEN
  end
end)

hl.on("window.destroy", sync)

hl.on("workspace.active", sync)

-- Moving a window between workspaces changes whether the one in front is empty
-- without anything opening or closing. The backdrop's own moves land here too,
-- but they have already written down where it went, so this settles instead of
-- moving it again.
hl.on("window.move_to_workspace", sync)