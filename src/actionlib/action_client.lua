
----------------------------------------------------------------------------
--  action_client.lua - Action client
--
--  Created: Fri Aug 06 11:41:07 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

--- Action client.
-- This module contains the ActionClient class to call the execution of
-- actions provided by an action server. It reads the given action
-- specification and opens the appropriate topics for communication.
-- <br /><br />
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("actionlib.action_client", package.seeall)

require("roslua")
require("actionlib.action_spec")

local ActionSpec = actionlib.action_spec.ActionSpec


GoalHandle = { WAIT_GOAL_ACK = 0,
	       PENDING = 1,
	       ACTIVE = 2,
	       WAIT_CANCEL_ACK = 3,
	       RECALLING = 4,
	       PREEMPTING = 5,
	       WAIT_RESULT = 6,
	       DONE = 7
	      }


function GoalHandle:new(o)
   setmetatable(o, self)
   self.__index = self

   assert(o.goal_id, "No goal ID set for handle")

   o.goalstatspec = roslua.get_msgspec("actionlib_msgs/GoalStatus")

   o.state = GoalHandle.WAIT_GOAL_ACK
   o.status = -1

   return o
end

function GoalHandle:update_status(status)
   if status == goalstatspec.constants.PENDING then
      self.state = self.PENDING
   elseif status == goalstatspec.constants.ACTIVE then
      self.state = self.ACTIVE
   elseif status == goalstatspec.constants.SUCCEEDED or
          status == goalstatspec.constants.ABORTED   or
          status == goalstatspec.constants.REJECTED  or
          status == goalstatspec.constants.RECALLED  or
          status == goalstatspec.constants.PREEMPTED then
      self.state = self.WAIT_RESULT
   elseif status == goalstatspec.constants.PREEMPTING then
      self.state = self.PREEMPTING
   elseif status == goalstatspec.constants.RECALLING then
      self.state = self.RECALLING
   end

   self.status = status
end



ActionClient = {}

--- Constructor.
-- @param o Object initializer, must contain the following fields:
-- name namespace for topics
-- type type of action with the string
-- representation of the action name.
function ActionClient:new(o)
   setmetatable(o, self)
   self.__index = self

   assert(o.name, "Action name is missing")
   assert(o.type, "Action type is missing")

   o.actspec      = actionlib_lua.action_spec.get_actionspec(o.type)
   o.cancelspec   = roslua.get_msgspec("actionlib_msgs/GoalID")
   o.statusspec   = roslua.get_msgspec("actionlib_msgs/GoalStatusArray")

   o.pub_goal     = roslua.publisher(o.name .. "/goal", o.actspec.act_goal_spec)
   o.pub_cancel   = roslua.publisher(o.name .. "/cancel", o.cancelspec)
   o.sub_status   = roslua.publisher(o.name .. "/status", o.statusspec)
   o.sub_result   = roslua.publisher(o.name .. "/result", o.actspec.act_result_spec)
   o.sub_feedback = roslua.publisher(o.name .. "/feedback", o.actspec.act_feedback_spec)

   if o.transition_cb then
      assert(type(o.transition_cb) == "function", "Transition callback is not a function")
   end
   if o.feedback_cb then
      assert(type(o.feedback_cb) == "function", "Transition callback is not a function")
   end

   o.sub_status.register_listener(function (message) o:status_received(message) end)
   o.sub_result.register_listener(function (message) o:result_received(message) end)
   o.sub_feedback.register_listener(function (message) o:feedback_received(message) end)

   o.listeners = {}
   o.goals = {}

   roslua.add_spinner(o)

   return o
end

function ActionClient:add_listener(goal_id, listener)
   assert(type(listener) == "function", "Listener is not a function")
   self.goals[goal_id].listeners[listener] = listener
end

function ActionClient:remove_listener(goal_id, listener)
   self.goals[goal_id].listeners[listener] = nil
end


function ActionClient:status_received(message)
   -- parse state, update all goal handles and update listeners
   for _, g in message.status_list do
      local status = g.status
      if self.goals[g.goal_id.id] then
	 self.goals[g.goal_id.id].handle:update_status(status)

	 -- notify listeners
	 for _, l in pairs(self.goals[g.goal_id.id].listeners) do
	    l(self.goals[g.goal_id.id].handle)
	 end
      end
   end

end

function ActionClient:result_received(message)
   if self.goals[message.goal_id.id] then
      self.goals[message.goal_id.id].handle.result = message
      self.goals[message.goal_id.id].handle.state = GoalHandle.DONE
      -- notify listeners
      for _, l in pairs(self.goals[g.goal_id.id].listeners) do
	 l(self.goals[g.goal_id.id].handle)
      end
   end
end

function ActionClient:feedback_received(message)
   if self.goals[message.goal_id.id] then
      self.goals[message.goal_id.id].handle.feedback = message
      -- notify listeners
      for _, l in pairs(self.goals[g.goal_id.id].listeners) do
	 l(self.goals[g.goal_id.id].handle)
      end
   end
end


function ActionClient:finalize()
   roslua.remove_spinner(self)
end


function ActionClient:wait_for_server()
end

function ActionClient:send_goal(goal, listener)
   assert(self.actspec.goal_spec:is_instance(goal),
	  "Goal is not an instance of " .. self.actspec.goalspec.type)
   
end

function ActionClient:cancel_all_goals()
   local m = self.cancelspec:instantiate()
   self.pub_cancel:publish(m)
end

function ActionClient:spin()
end
