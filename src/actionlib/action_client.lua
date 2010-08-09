
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
	       FAILED = 7,
	       SUCCEEDED = 8
	      }


function GoalHandle:new(o)
   setmetatable(o, self)
   self.__index = self

   assert(o.goal_id, "No goal ID set for handle")
   assert(o.client, "No associated action client set")

   o.goalstatspec = roslua.get_msgspec("actionlib_msgs/GoalStatus")

   o.state = GoalHandle.WAIT_GOAL_ACK
   o.status = -1
   o.listeners = {}

   return o
end

function GoalHandle:update_status(status)
   if status == self.goalstatspec.constants.PENDING.value then
      self.state = self.PENDING
   elseif status == self.goalstatspec.constants.ACTIVE.value then
      self.state = self.ACTIVE
   elseif status == self.goalstatspec.constants.SUCCEEDED.value or
          status == self.goalstatspec.constants.ABORTED.value   or
          status == self.goalstatspec.constants.REJECTED.value  or
          status == self.goalstatspec.constants.RECALLED.value  or
          status == self.goalstatspec.constants.PREEMPTED.value then
      if self.result == nil then -- result can come in faster than status
	 self.state = self.WAIT_RESULT
      end
   elseif status == self.goalstatspec.constants.PREEMPTING.value then
      self.state = self.PREEMPTING
   elseif status == self.goalstatspec.constants.RECALLING.value then
      self.state = self.RECALLING
   end

   self.status = status
end


function GoalHandle:add_listener(listener)
   table.insert(self.listeners, listener)
end

function GoalHandle:remove_listener(listener)
   for i, l in ipairs(self.listeners) do
      if l == listener then
	 table.remove(self.listeners, i)
	 break
      end
   end
end

function GoalHandle:set_result(result)
   self.result = result
   if self.status == self.goalstatspec.constants.REJECTED
      or self.status == self.goalstatspec.constants.ABORTED
   then
      self.state = self.FAILED
   elseif self.status == self.goalstatspec.constants.RECALLED
       or self.status == self.goalstatspec.constants.PREEMPTED
   then
      self.state = self.CANCELED
   else
      self.state = self.SUCCEEDED
   end
end

function GoalHandle:cancelled()
end

function GoalHandle:failed()
   return self.state == self.FAILED 
end

function GoalHandle:succeeded()
   return self.state == self.SUCCEEDED
end

function GoalHandle:running()
   return self.state == self.ACTIVE
end

function GoalHandle:waiting_for_start_ack()
   return self.state == self.PENDING
end

function GoalHandle:waiting_for_cancel_ack()
   return self.state == self.PREEMPTING
       or self.state == self.RECALLING
end

function GoalHandle:waiting_for_result()
   return self.state == self.WAIT_RESULT
end

function GoalHandle:cancel()
   local m = self.client.cancelspec:instantiate()
   m.fields.id = goal_id
   self.client.pub_cancel:publish(m)
end

function GoalHandle:feedback_received()
   local rv = self._feedback_received or false
   self._feedback_received = false
   return rv
end

function GoalHandle:set_feedback(feedback)
   self.feedback = feedback
   self._feedback_received = true
end

function GoalHandle:notify_listeners()
   for _, l in pairs(self.listeners) do
      l(self)
   end
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

   o.actspec      = actionlib.action_spec.get_actionspec(o.type)
   o.goalidspec   = roslua.get_msgspec("actionlib_msgs/GoalID")
   o.statusspec   = roslua.get_msgspec("actionlib_msgs/GoalStatusArray")

   o.pub_goal     = roslua.publisher(o.name .. "/goal", o.actspec.act_goal_spec)
   o.pub_cancel   = roslua.publisher(o.name .. "/cancel", o.goalidspec)
   o.sub_status   = roslua.subscriber(o.name .. "/status", o.statusspec)
   o.sub_result   = roslua.subscriber(o.name .. "/result", o.actspec.act_result_spec)
   o.sub_feedback = roslua.subscriber(o.name .. "/feedback", o.actspec.act_feedback_spec)

   if o.transition_cb then
      assert(type(o.transition_cb) == "function", "Transition callback is not a function")
   end
   if o.feedback_cb then
      assert(type(o.feedback_cb) == "function", "Transition callback is not a function")
   end

   o.sub_status:add_listener(function (message) o:status_received(message) end)
   o.sub_result:add_listener(function (message) o:result_received(message) end)
   o.sub_feedback:add_listener(function (message) o:feedback_received(message) end)

   o.listeners = {}
   o.goals = {}
   o.next_goal_id = 1

   roslua.add_spinner(function () o:spin() end)

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
   for _, g in ipairs(message.values.status_list) do
      local status = g.values.status
      local goal_id = g.values.goal_id.values.id
      if self.goals[goal_id] then
	 self.goals[goal_id]:update_status(status)
	 self.goals[goal_id]:notify_listeners()
      end
   end

end

function ActionClient:result_received(message)
   local goal_id = message.values.status.values.goal_id.values.id
   if self.goals[goal_id] then
      self.goals[goal_id]:set_result(message)
      self.goals[goal_id]:notify_listeners()
   end
end

function ActionClient:feedback_received(message)
   local goal_id = message.values.status.values.goal_id.values.id
   if self.goals[goal_id] then
      self.goals[goal_id].feedback = message
      self.goals[goal_id]:notify_listeners()
   end
end


function ActionClient:finalize()
   roslua.remove_spinner(self)
end


function ActionClient:wait_for_server()
   local has_server = false
   while not has_server do
      -- keep spinning...
      assert(not roslua.quit, "Aborted while waiting for server")
      roslua.spin()

      local callerid = nil
      -- we just want any publisher, assuming that in useful scenarios there
      -- is only one. Oh my, not the double writer problem, again...
      for uri, p in pairs(self.sub_status.publishers) do
	 if p.connection then
	    local callerid = p.connection.header.callerid
	    if self.pub_goal.subscribers[callerid] then
	       -- We got a subscriber with the matching caller id
	       has_server = true
	    end
	 end
      end
   end
end

function ActionClient:generate_goal_id()
   local goal_id = self.next_goal_id
   self.next_goal_id = self.next_goal_id + 1
   return string.format("%s-%i-%i", roslua.node_name, goal_id, os.time())
end

function ActionClient:send_goal(goal, listener)
   assert(self.actspec.goal_spec:is_instance(goal),
	  "Goal is not an instance of " .. self.actspec.goal_spec.type)
   local goal_id = self:generate_goal_id()
   local handle = GoalHandle:new{client=self, goal_id=goal_id}
   handle:add_listener(listener)
   local actgoal = self.actspec.act_goal_spec:instantiate()
   actgoal.values.header.stamp = roslua.Time.now()
   actgoal.values.goal_id = self.goalidspec:instantiate()
   actgoal.values.goal_id.values.stamp = actgoal.values.header.stamp
   actgoal.values.goal_id.values.id    = goal_id
   actgoal.values.goal = goal
   self.pub_goal:publish(actgoal)
   self.goals[goal_id] = handle
end

function ActionClient:cancel_all_goals()
   local m = self.goalidspec:instantiate()
   self.pub_cancel:publish(m)
end

function ActionClient:spin()
end
