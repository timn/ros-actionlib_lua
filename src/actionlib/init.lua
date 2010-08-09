
----------------------------------------------------------------------------
--  init.lua - base file for actionlib library
--
--  Created: Thu Aug 05 17:56:25 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

--- Actionlib utilities for Lua
-- This module and its sub-modules provide tools to make use of actionlib from
-- withing Lua.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("actionlib", package.seeall)

require("actionlib.action_spec")
require("actionlib.action_client")

get_actionspec = actionlib.action_spec.get_actionspec
ActionClient   = actionlib.action_client.ActionClient

function action_client(name, type)
   return ActionClient:new{name=name, type=type}
end
