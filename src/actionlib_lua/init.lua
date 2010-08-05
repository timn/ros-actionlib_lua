
----------------------------------------------------------------------------
--  init.lua - base file for actionlib_lua library
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
module("actionlib_lua", package.seeall)

require("roslua.action_spec")

get_actionspec = actionlib_lua.action_spec.get_actionspec
