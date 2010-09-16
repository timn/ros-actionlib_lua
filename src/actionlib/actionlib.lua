
----------------------------------------------------------------------------
--  init.lua - base file for actionlib library
--
--  Created: Thu Aug 05 17:56:25 2010 (at Intel Research, Pittsburgh)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

--- Actionlib implementation for Lua.
-- This module and its sub-modules provide tools to make use of actionlib from
-- within Lua.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("actionlib", package.seeall)

require("actionlib.action_spec")
require("actionlib.action_client")
require("actionlib.action_server")

get_actionspec = actionlib.action_spec.get_actionspec
ActionClient   = actionlib.action_client.ActionClient
ActionServer   = actionlib.action_server.ActionServer

--- Create a new action client.
-- This is a convenience method for ActionClient:new(). Since no registration
-- is performed it is ok to use the constructor directly.
-- @param name name of the action client
-- @param type type of the action (i.e. the package-prefixed action file)
-- @param flags Optional table of flags, passed as named arguments exactly as in the table
function action_client(name, type, flags)
   local o = {name=name, type=type}
   if flags then for k,v in pairs(flags) do o[k] = v end end
   return ActionClient:new(o)
end

--- Create a new action server.
-- This is a convenience method for ActionServer:new(). Since no registration
-- is performed it is ok to use the constructor directly.
-- @param name name of the action server
-- @param type type of the action (i.e. the package-prefixed action file)
-- @param goal_cb goal callback
-- @param spin_cb spin callback
-- @param cancel_cb cancel callback (optional)
function action_server(name, type, goal_cb, spin_cb, cancel_cb)
   return ActionServer:new{name=name, type=type, goal_cb=goal_cb,
			   spin_cb=spin_cb, cancel_cb=cancel_cb}
end
