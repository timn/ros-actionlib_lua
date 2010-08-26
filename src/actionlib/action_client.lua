
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
-- message specifications and opens the appropriate topics for communication.
-- It is recommended to use the <code>actionlib.action_client()</code>
-- function to acquire the client.
-- <br /><br />
-- The ActionClient will connect to an ActionServer via several topics (cf.
-- the actionlib documentation for details). The Lua implementation supports
-- sending an virtually arbitrary number of goals. Each goal is associated
-- with a ClientGoalHandle which provides information about the goal and its
-- current state. Additionally for a goal one or more listeners can be
-- registered to get notified if the state changes or feedback or result
-- messages are received.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("actionlib.action_client", package.seeall)

require("roslua")
require("actionlib.action_spec")

local ActionSpec = actionlib.action_spec.ActionSpec


ClientGoalHandle = { WAIT_GOAL_ACK   =  1,
		     PENDING         =  2,
		     ACTIVE          =  3,
		     WAIT_CANCEL_ACK =  4,
		     RECALLING       =  5,
		     PREEMPTING      =  6,
		     WAIT_RESULT     =  7,
		     ABORTED         =  8,
		     PREEMPTED       =  9,
		     RECALLED        = 10,
		     REJECTED        = 11,
		     SUCCEEDED       = 12,
		     STATE_TO_STRING = { "WAIT_GOAL_ACK", "PENDING", "ACTIVE", "WAIT_CANCEL_ACK", "RECALLING",
					 "PREEMPTING", "WAIT_RESULT", "ABORTED", "PREEMPTED", "RECALLED",
					 "REJECTED", "SUCCEEDED" }
		  }

--- Constructor.
-- Do not call this directly. Goal handles are generated by the ActionClient.
-- @param o table which is setup as the object instance and which must have at
-- least the following fields:
-- goal_id the ID of the goal this handle represents
-- client the action client this handle is associated to.
function ClientGoalHandle:new(o)
   setmetatable(o, self)
   self.__index = self

   assert(o.goal_id, "No goal ID set for handle")
   assert(o.client, "No associated action client set")

   o.goalstatspec = roslua.get_msgspec("actionlib_msgs/GoalStatus")

   o.state = ClientGoalHandle.WAIT_GOAL_ACK
   o.status = -1
   o.listeners = {}
   o.last_state = -1
   o.feedback = nil

   return o
end


--- Set the state of the state machine.
-- To be used only internally.
-- @param state new state
function ClientGoalHandle:set_state(state)
   self.last_state = self.state
   self.state = state
   if self.client.debug and self.last_state ~= self.state then
      printf("Goal (%s %s) state change %s -> %s", self.client.name, self.goal_id,
	     self.STATE_TO_STRING[self.last_state], self.STATE_TO_STRING[self.state])
   end

   self.feedback = nil
end

--- Update the status.
-- @param One of the GoalStatus constants
function ClientGoalHandle:update_status(status)
   if status == self.goalstatspec.constants.PENDING.value then
      return self:set_state(self.PENDING)
   elseif status == self.goalstatspec.constants.ACTIVE.value then
      if not self:terminal() then
	 return self:set_state(self.ACTIVE)
      end
   elseif status == self.goalstatspec.constants.SUCCEEDED.value then
      if self.result == nil then -- result can come in faster than status
	 return self:set_state(self.WAIT_RESULT)
      else
	 return self:set_state(self.SUCCEEDED)
      end
   elseif status == self.goalstatspec.constants.ABORTED.value then
      return self:set_state(self.ABORTED)
   elseif status == self.goalstatspec.constants.REJECTED.value then
      return self:set_state(self.REJECTED)
   elseif status == self.goalstatspec.constants.RECALLED.value then
      return self:set_state(self.RECALLED)
   elseif status == self.goalstatspec.constants.PREEMPTED.value then
      return self:set_state(self.PREEMPTED)
   elseif status == self.goalstatspec.constants.PREEMPTING.value then
      return self:set_state(self.PREEMPTING)
   elseif status == self.goalstatspec.constants.RECALLING.value then
      return self:set_state(self.RECALLING)
   end
end


--- Add a listener.
-- @param function which is called with two arguments, the handle and the
-- associated client, on future events.
function ClientGoalHandle:add_listener(listener)
   assert(type(listener) == "function", "Listener is not a function")
   table.insert(self.listeners, listener)
end

--- Remove listener.
-- @param listener The listener to remove.
function ClientGoalHandle:remove_listener(listener)
   for i, l in ipairs(self.listeners) do
      if l == listener then
	 table.remove(self.listeners, i)
	 break
      end
   end
end

--- Set the result.
-- This is to be called only by the ActionClient.
-- @param result result message
function ClientGoalHandle:set_result(result)
   self.result = result
   if self.state == self.ACTIVE or self.state == self.WAIT_RESULT then
      self:set_state(self.SUCCEEDED)
   end
end

--- Check if the state has changed.
-- @return true if the state has changed in the last spin, false otherwise.
function ClientGoalHandle:state_changed()
   return (self.last_state ~= self.state)
end

--- Check if feedback has been received.
-- @return true if feedback has been received in the last spin, false otherwise.
function ClientGoalHandle:feedback_received()
   return (self.feedback ~= nil)
end

--- Check if goal is in a terminal state.
-- @return true if the goal has succeeded, failed, or canceled
function ClientGoalHandle:terminal()
   return self:canceled() or self:failed() or self:succeeded()
end

--- Check if goal has been canceled.
-- @return true if goal has been canceled, i.e. been preempted or recalled, false otherwise
function ClientGoalHandle:canceled()
   return self.state == self.CANCELED
end

--- Check if goal has failed.
-- @return true if goal was aborted, preempted, recalled, or rejected, false otherwise
function ClientGoalHandle:failed()
   return self.state == self.ABORTED
       or self.state == self.PREEMPTED
       or self.state == self.RECALLED
       or self.state == self.REJECTED
end

--- Check if goal succeeded
-- @return true if goal succeeded, false otherwise
function ClientGoalHandle:succeeded()
   return self.state == self.SUCCEEDED
end

--- Check if goal was preempted
-- @return true if goal was preempted, false otherwise
function ClientGoalHandle:preempted()
   return self.state == self.PREEMPTED
end

--- Check if goal is active
-- @return true if goal is active, false otherwise
function ClientGoalHandle:running()
   return self.state == self.ACTIVE
end

--- Check if goal is pending
-- @return true if goal is pending, false otherwise
function ClientGoalHandle:waiting_for_start_ack()
   return self.state == self.PENDING
end

--- Check if goal is awaiting cancellation.
-- @return true if goal is preempting or recalling, false otherwise.
function ClientGoalHandle:waiting_for_cancel_ack()
   return self.state == self.WAIT_CANCEL_ACK
end

--- Check if goal is awaiting result.
-- @return true if the goal has succeeded but the result has not been
-- received, yet, false otherwise.
function ClientGoalHandle:waiting_for_result()
   return self.state == self.WAIT_RESULT
end

--- Cancel this goal.
function ClientGoalHandle:cancel()
   local m = self.client.goalidspec:instantiate()
   m.values.id = self.goal_id
   self.client.pub_cancel:publish(m)
   self.last_state = self.state
   self:set_state(self.WAIT_CANCEL_ACK)
end

--- Set feedback.
-- To be called only by ActionClient.
-- @param feedback received feedback message
function ClientGoalHandle:set_feedback(feedback)
   self.last_state = self.state
   self.full_feedback = feedback
   self.feedback = feedback.values.feedback
end

--- Notify listeners of new event.
-- To be called only by ActionClient.
function ClientGoalHandle:notify_listeners()
   if self.last_state ~= self.state or self.feedback ~= nil then
      for _, l in pairs(self.listeners) do
	 l(self, self.client)
      end
      self.last_state = self.state
      self.feedback   = nil
   end
end

ActionClient = {}

--- Constructor.
-- @param o Object initializer, must contain the following fields:
-- name namespace for topics
-- type type of action with the string representation of the action name
function ActionClient:new(o)
   setmetatable(o, self)
   self.__index = self

   assert(o.name, "Action name is missing")
   assert(o.type, "Action type is missing")

   o.actspec      = actionlib.action_spec.get_actionspec(o.type)
   o.goalidspec   = roslua.get_msgspec("actionlib_msgs/GoalID")
   o.statusspec   = roslua.get_msgspec("actionlib_msgs/GoalStatusArray")

   o.sub_status   = roslua.subscriber(o.name .. "/status", o.statusspec)
   o.sub_result   = roslua.subscriber(o.name .. "/result", o.actspec.act_result_spec)
   o.sub_feedback = roslua.subscriber(o.name .. "/feedback", o.actspec.act_feedback_spec)
   o.pub_goal     = roslua.publisher(o.name .. "/goal", o.actspec.act_goal_spec)
   o.pub_cancel   = roslua.publisher(o.name .. "/cancel", o.goalidspec)

   o.sub_status:add_listener(function (message) return o:process_status(message) end)
   o.sub_result:add_listener(function (message) return o:process_result(message) end)
   o.sub_feedback:add_listener(function (message) return o:process_feedback(message) end)

   o.listeners = {}
   o.goals = {}
   o.next_goal_id = 1
   o.debug = o.debug or false

   return o
end


--- Add listener.
-- A listener is a function which is called on events like state changes
-- or incoming feedback with two arguments, the goal handle and the
-- associated action client.
-- @param goal_id the goal ID to register the listener or
-- @param listener listener to add
function ActionClient:add_listener(goal_id, listener)
   self.goals[goal_id]:add_listeners(listener)
end

--- Remove listener.
-- @param listener listener to remove
function ActionClient:remove_listener(goal_id, listener)
   self.goals[goal_id]:remove_listeners(listener)
end


--- Process status message.
-- @param message GoalStatusArray message to process
function ActionClient:process_status(message)
   -- parse state, update all goal handles and update listeners
   --printf("Received %d stati", #message.values.status_list)
   for _, g in ipairs(message.values.status_list) do
      local status = g.values.status
      local goal_id = g.values.goal_id.values.id
      if self.goals[goal_id] then
	 self.goals[goal_id]:update_status(status)
	 self.goals[goal_id]:notify_listeners()
      end
   end
end

--- Process result.
-- @param message Appropriately typed result message
function ActionClient:process_result(message)
   self.received_result = true
   self.result = message
   local goal_id = message.values.status.values.goal_id.values.id
   if self.goals[goal_id] then
      self.goals[goal_id]:set_result(message)
      self.goals[goal_id]:notify_listeners()
   end
end

--- Process feedback.
-- @param message Appropriately typed feedback message
function ActionClient:process_feedback(message)
   local goal_id = message.values.status.values.goal_id.values.id
   if self.goals[goal_id] then
      self.goals[goal_id]:set_feedback(message)
      self.goals[goal_id]:notify_listeners()
   end
end

--- Check if there is a server for this action client.
-- @return true if an action server exists, false otherwise
function ActionClient:has_server()
   -- we just want any publisher, assuming that in useful scenarios there
   -- is only one. Oh my, not the double writer problem, again...
   for uri, p in pairs(self.sub_status.publishers) do
      if p.connection then
	 local callerid = p.connection.header.callerid
	 if self.pub_goal.subscribers[callerid] then
	    -- We got a subscriber with the matching caller id
	    return true
	 end
      end
   end
   return false
end

--- Wait for server to appear.
-- To avoids ending goals while there is no server to process them this
-- method can be used to wait until a server appears. Note that this
-- method will block and spin the main loop until this happens, there
-- is no way to interrupt this.
function ActionClient:wait_for_server()
   while not self:has_server() do
      -- keep spinning...
      assert(not roslua.quit, "Aborted while waiting for server")
      roslua.spin(0.05)
   end
end

--- Wait for result.
-- This method will block and spin the main loop until a result message has
-- been received from the server. Warning, this method may stall if the
-- server dies.
-- @todo improve by adding a timeout
function ActionClient:wait_for_result()
   self.received_result = false
   while not self.received_result do
      roslua.spin()
   end
end

--- Generate a unique goal ID.
-- @return unique goal ID
function ActionClient:generate_goal_id()
   local goal_id = self.next_goal_id
   self.next_goal_id = self.next_goal_id + 1
   local now = roslua.Time.now()
   return string.format("%s-%i-%i.%i", roslua.node_name, goal_id, now.sec, now.nsec)
end

--- Send and order execution of a goal.
-- @param goal appropriately typed goal message
-- @param listener listener function for this goal (optional)
-- @return goal handle for the issued goal
function ActionClient:send_goal(goal, listener)
   assert(self.actspec.goal_spec:is_instance(goal),
	  "Goal is not an instance of " .. self.actspec.goal_spec.type)
   local goal_id = self:generate_goal_id()
   local handle = ClientGoalHandle:new{client=self, goal_id=goal_id}
   if listener then
      handle:add_listener(listener)
   end
   local actgoal = self.actspec.act_goal_spec:instantiate()
   actgoal.values.header.stamp = roslua.Time.now()
   actgoal.values.goal_id = self.goalidspec:instantiate()
   actgoal.values.goal_id.values.stamp = actgoal.values.header.stamp
   actgoal.values.goal_id.values.id    = goal_id
   actgoal.values.goal = goal
   self.pub_goal:publish(actgoal)
   self.goals[goal_id] = handle
   return handle
end

--- Cancel all current goals.
function ActionClient:cancel_all_goals()
   local m = self.goalidspec:instantiate()
   self.pub_cancel:publish(m)
end

--- Cancel all goals before a specific time.
-- @param time time before which all goals shall be canceled
function ActionClient:cancel_goals_before(time)
   local m = self.goalidspec:instantiate()
   m.values.stamp = time
   self.pub_cancel:publish(m)
end

