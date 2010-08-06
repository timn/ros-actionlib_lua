
----------------------------------------------------------------------------
--  action_client_fsm.lua - Action Client FSM
--
--  Created: Fri Aug 06 16:45:09 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

--- Action client FSM.
-- This module contains the ActionClientFSM class which resembles the finite
-- state machine for goals initiated by an ActionClient.
-- <br /><br />
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("actionlib_lua.action_client_fsm", package.seeall)

require("roslua")
require("fawkes.fsm")
require("fawkes.fsm.state")

local State = fawkes.fsm.state.State
local FSM = fawkes.fsm.FSM

ActionClientFSM = {}

function ActionClientFSM:new(o)
   setmetatable(o, self)
   self.__index = self

   assert(o.goal_id, "No Goal ID set for ActionClientFSM")

   o.fsm = FSM:new{name="ActionClientFSM:"..goal_id, start="WAIT_GOAL_ACK"}
   o.fsm:new_state("WAIT_GOAL_ACK")
   o.fsm:new_state("PENDING")
   o.fsm:new_state("ACTIVE")
   o.fsm:new_state("WAIT_CANCEL_ACK")
   o.fsm:new_state("RECALLING")
   o.fsm:new_state("PREEMPTING")
   o.fsm:new_state("WAIT_RESULT")
   o.fsm:new_state("DONE")

   return o
end

function ActionClientFSM:set_goal_state(goal_status, msg)
   self.goal_status = goal_status
   self.msg = msg
end


function ActionClientFSM:spin()
   self.fsm:loop()
end
