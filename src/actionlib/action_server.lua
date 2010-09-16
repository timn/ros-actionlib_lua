
----------------------------------------------------------------------------
--  action_server.lua - Action server
--
--  Created: Mon Aug 16 17:10:44 2010 (at Intel Research, Pittsburgh)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

--- Action server.
-- This module contains the ActionServer class to provide actions which can
-- be executed by an ActionClient.
-- <br /><br />
-- The action server is initialized with at least two callbacks. One is the
-- goal callback. It is called on new incoming goals. The callback gets the
-- ServerGoalHandle for this goal and the associated ActionServer instance
-- as arguments. The callback can then accept or reject the goal by calling
-- the appropriate goal handle method. If the callback does call neither of
-- this method acceptance is assumed.
-- The second callback is the spin callback. It is called in each loop for
-- every goal to execute one step of the goal. Note that due to the nature
-- if Lua and the need for a central main loop your spin method must return
-- as soon as possible. For lengthy actions this means that you cannot run
-- a continuous method for your action, as you possibly would with roscpp
-- or rospy! Lua coroutines might be useful to meet this requirement.
-- The spin callback is optional in the case of short-duration actions.
-- In this case you must send the result in the goal callback!
-- Optionally a cancel callback can be given, which is called when a goal
-- is canceled. It could be used for example for safely stopping a goal.
-- After a goal has been canceled the spin function is no longer called for
-- this goal.
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("actionlib.action_server", package.seeall)

require("roslua")
require("actionlib.action_spec")

local ActionSpec = actionlib.action_spec.ActionSpec

ServerGoalHandle = { PENDING    = 0,
		     ACTIVE     = 1,
		     PREEMPTED  = 2,
		     SUCCEEDED  = 3,
		     ABORTED    = 4,
		     REJECTED   = 5,
		     PREEMPTING = 6,
		     RECALLING  = 7,
		     RECALLED   = 8
		  }

--- Constructor.
-- Do not call this directly. Goal handles are created by the ActionServer.
-- @param o table which is setup as the object instance and which must have at
-- least the following fields:
-- goal_id the goal ID of this handle
-- server the associated ActionServer instance
-- @param stamp the time stamp when the goal was started
function ServerGoalHandle:new(o)
   setmetatable(o, self)
   self.__index = self

   assert(o.goal_id, "No goal ID set for handle")
   assert(o.server, "No associated action server set")
   assert(o.stamp, "No timestamp set")

   o.state        = ServerGoalHandle.PENDING
   o.text         = o.text or ""
   o.expire       = roslua.Time.now() + o.server.timeout
   o.vars         = {}
   o.last_state   = -1

   return o
end

--- Update the expiration date.
-- The expiration date is reset to be now plus the timeout interval.
function ServerGoalHandle:update_expiration()
   self.expire = roslua.Time.now() + self.server.timeout
end

--- Set the state.
-- To be called only by the ActionServer.
-- @param state new staet
-- @param text explanatory text to set
function ServerGoalHandle:set_state(state, text)
   self.last_state = self.state
   self.state = state
   self.text  = text or ""
end

--- Check if the status has changed.
function ServerGoalHandle:state_changed()
   local rv = (self.last_state ~= self.state)
   self.last_state = self.state
   return rv
end

--- Check if goal is active
-- @return true if the goal is active, false otherwise
function ServerGoalHandle:is_active()
   return self.state == self.ACTIVE
end

--- Check if goal is in a terminal state
-- @return true if goal is preempted, recalled, aborted, rejected, or succeeded.
function ServerGoalHandle:is_terminal()
   return self.state == self.PREEMPTED
       or self.state == self.RECALLED
       or self.state == self.ABORTED
       or self.state == self.REJECTED
       or self.state == self.SUCCEEDED
end

--- Check if goal is pending
-- @return true if the goal is pending, false otherwise
function ServerGoalHandle:is_pending()
   return self.state == self.PENDING
end

--- Check if goal has been canceled
-- @return true if the goal has been canceled, false otherwise
function ServerGoalHandle:is_canceled()
   return self.state == self.PREEMPTED
       or self.state == self.RECALLED
end

--- Abort the given goal.
-- @param text explanatory text
function ServerGoalHandle:abort(result, text)
   assert(self.server.actspec.result_spec:is_instance(result),
	  "Result is not an instance of " .. self.server.actspec.result_spec.type)
   assert(self.state == self.PREEMPTING or self.state == self.ACTIVE,
	  "Only active or preempting goals can be aborted")
   self.text  = text or ""
   self.state = self.ABORTED
   self.server:publish_result(self, result)
end


--- Cancel the goal.
-- @param explanatory text
function ServerGoalHandle:cancel(result, text)
   assert(self.server.actspec.result_spec:is_instance(result),
	  "Result is not an instance of " .. self.server.actspec.result_spec.type)

   self.text  = text or self.text or ""
   if self.state == self.PENDING or self.state == self.RECALLING then
      self.state = self.RECALLED
   elseif self.state == self.ACTIVE or self.state == self.PENDING then
      self.state = self.PREEMPTED
   end
   self.server:publish_result(self, result)
end

--- Accept this goal.
function ServerGoalHandle:accept()
   if self.state == self.PENDING then
      self.state = self.ACTIVE
   elseif self.state == self.RECALLING then
      self.state = self.RECALLED
   end
end

--- Reject this goal.
function ServerGoalHandle:reject()
   assert(self.state == self.PENDING, "Only pending goals can be rejected")
   self.state = self.REJECTED
end

--- Finish this goal successfully.
function ServerGoalHandle:finish(result)
   assert(self.server.actspec.result_spec:is_instance(result),
	  "Result is not an instance of " .. self.server.actspec.result_spec.type)
   self:set_state(ServerGoalHandle.SUCCEEDED)
   self.server:publish_result(self, result)
end

ActionServer = {}

--- Constructor.
-- @param o Object initializer, must contain the following fields:
-- name namespace for topics
-- type type of action with the string representation of the action name.
-- goal_cb goal callback
-- spin_cb spin callback (optional)
-- cancel_cb cancel callback (optional)
function ActionServer:new(o)
   setmetatable(o, self)
   self.__index = self

   assert(o.name, "Action name is missing")
   assert(o.type, "Action type is missing")
   assert(not o.goal_cb   or type(o.goal_cb) == "function", "Goal handler is not a function")
   assert(not o.spin_cb   or type(o.spin_cb) == "function", "Spin is not a function")
   assert(not o.cancel_cb or type(o.cancel_cb) == "function", "Cancel handler is not a function")

   o.actspec       = actionlib.action_spec.get_actionspec(o.type)
   o.goalidspec    = roslua.get_msgspec("actionlib_msgs/GoalID")
   o.statusarrspec = roslua.get_msgspec("actionlib_msgs/GoalStatusArray")
   o.statusspec    = roslua.get_msgspec("actionlib_msgs/GoalStatus")

   o.sub_goal      = roslua.subscriber(o.name .. "/goal", o.actspec.act_goal_spec)
   o.sub_cancel    = roslua.subscriber(o.name .. "/cancel", o.goalidspec)
   o.pub_status    = roslua.publisher(o.name .. "/status", o.statusarrspec)
   o.pub_result    = roslua.publisher(o.name .. "/result", o.actspec.act_result_spec)
   o.pub_feedback  = roslua.publisher(o.name .. "/feedback", o.actspec.act_feedback_spec)

   o.sub_goal:add_listener(function (message) return o:process_goal(message) end)
   o.sub_cancel:add_listener(function (message) return o:process_cancel(message) end)

   o.goals = {}
   o.status_update_interval = o.status_update_interval or 1
   o.last_status_update = roslua.Time:new()
   o.timeout = o.timeout or 5

   o.feedback_seqnum = 1
   o.result_seqnum   = 1
   o.status_seqnum   = 1

   o.next_goal_id = 1
   roslua.add_spinner(function () return o:spin() end)
   roslua.add_finalizer(function () return o:finalize() end)

   return o
end

--- Finalize instance.
function ActionServer:finalize()
   roslua.remove_spinner(self)
   roslua.remove_finalizer(self)
end

--- Generate a unique goal ID.
-- @return unique goal ID
function ActionServer:generate_goal_id()
   local goal_id = self.next_goal_id
   self.next_goal_id = self.next_goal_id + 1
   local now = roslua.Time.now()
   return string.format("%s-%i-%i.%i", roslua.node_name, goal_id, now.sec, now.nsec)
end

--- Process incoming goal.
-- @param message appropriately typed goal message
function ActionServer:process_goal(message)
   local goal_id = message.values.goal_id.values.id
   if goal_id == "" then
      goal_id = generate_goal_id()
   end
   if message.values.header.values.stamp:is_zero() then
      message.values.header.values.stamp = roslua.Time.now()
   end

   local gh = ServerGoalHandle:new{server=self, goal_id=goal_id,goalmsg=message,
				   stamp=message.values.header.values.stamp}

   -- if a goal with the given goal ID already exists we simply overwrite it
   self.goals[goal_id] = gh
   if self.goal_cb then
      self.goal_cb(gh, self)
      if gh:is_pending() then
	 -- The goal call back did not explicitly reject, so we assume acceptance
	 gh:accept()
      end
   end
end

--- Process incoming cancel message.
-- @param message cancel message
function ActionServer:process_cancel(message)
   if message.values.id ~= "" then
      -- cancel specific goal
      local goal_id = message.values.id
      print_debug("Cancel specific goal %s", goal_id)
      if self.goals[goal_id] then
	 if self.cancel_cb then
	    self.cancel_cb(self.goals[goal_id], self)
	 end
	 local result = self.actspec.result_spec:instantiate()
	 self.goals[goal_id]:cancel(result)
      end
   end
   if not message.values.stamp:is_zero() then
      self:cancel_goals_before(message.values.stamp)
   end
   if message.values.id == "" and message.values.stamp:is_zero() then
      self:cancel_all_goals()
   end
end


--- Cancel all goals.
function ActionServer:cancel_all_goals()
      -- cancel all goals
      print_debug("Cancelling all goals")
      for goal_id, goal_handle in pairs(self.goals) do
	 if not goal_handle:is_terminal() then
	    if self.cancel_cb then
	       self.cancel_cb(goal_handle, self)
	    end
	    local result = self.actspec.result_spec:instantiate()
	    goal_handle:cancel(result)
	 end
      end
end

--- Cancel all before the given time
function ActionServer:cancel_goals_before(stamp)
   -- cancel all goals before timestamp
   print_debug("Cancelling goals before %s", tostring(stamp))
   local remove_goals = {}
   for goal_id, goal_handle in pairs(self.goals) do
      if not goal_handle:is_terminal() and goal_handle.stamp < stamp then
	 if self.cancel_cb then
	    self.cancel_cb(goal_handle, self)
	 end
	 local result = self.actspec.result_spec:instantiate()
	 goal_handle:cancel(result)
      end
   end
end



--- Get pending goals.
-- This will filter pending goals from all goals and return them in a list.
-- This function is most useful for implementing a polling goal processing.
-- @return list of pending goal (handles)
function ActionServer:get_pending_goals()
   local rv = {}
   for _, goal_handle in pairs(self.goals) do
      if goal_handle:pending() then
	 table.insert(rv, goal_handle)
      end
   end
   return rv
end

--- Publish result.
-- It is recommended to use the ServerGoalHandle methods abort(), cancel() or
-- finish() to send the result.
-- @param goal_handle goal handle for which to publish a result
-- @param result appropriately typed result message. Note that this is not the
-- type ending in ActionResult (e.g. TestActionResult), but the message specified
-- in the action file (e.g. TestResult). The surrounding message is generated
-- automatically from information stored in the goal handle.
function ActionServer:publish_result(goal_handle, result)
   assert(goal_handle, "No goal handle passed")
   assert(result, "No result passed")

   if goal_handle.result_published then
      print_warn("Result already published for goal %s", goal_handle.goal_id)
   end

   local m = self.actspec.act_result_spec:instantiate()
   m.values.header.values.stamp = roslua.Time.now()
   m.values.header.values.seq   = self.result_seqnum
   self.result_seqnum = self.result_seqnum + 1
   m.values.status.values.goal_id.values.id = goal_handle.goal_id
   m.values.status.values.status = goal_handle.state
   m.values.result = result
   self.pub_result:publish(m)
   goal_handle.result_published = true
end

--- Publish feedback.
-- @param goal_handle goal handle for which to publish a result
-- @param result appropriately typed feedback message. Note that this is not the
-- type ending in ActionFeedback (e.g. TestActionFeedback), but the message
-- specified in the action file (e.g. TestFeedback). The surrounding message is
-- generated automatically from information stored in the goal handle.
function ActionServer:publish_feedback(goal_handle, feedback)
   assert(goal_handle, "No goal handle passed")
   assert(feedback, "No result passed")

   local m = self.actspec.act_feedback_spec:instantiate()
   m.values.header.values.seq   = self.feedback_seqnum
   self.feedback_seqnum = self.feedback_seqnum + 1
   m.values.header.values.stamp = roslua.Time.now()
   m.values.status.values.goal_id.values.id = goal_handle.goal_id
   m.values.status.values.status = goal_handle.state
   m.values.feedback = feedback
   self.pub_feedback:publish(m)
end

--- Publish status.
-- To be called only internally.
-- This checks all current goals for their status. If a goal expired it is
-- removed, if any goal has changed its state or the status_update_interval
-- has elapsed a GoalStatusArray message is published.
function ActionServer:publish_status()
   local status_updated = false

   local m = self.statusarrspec:instantiate()
   m.values.header.values.stamp = roslua.Time.now()
   local expired = {}
   local now = roslua.Time.now()
   for goal_id, gh in pairs(self.goals) do
      if gh.expire < now then
	 print_debug("Goal %s expired", goal_id)
	 table.insert(expired, goal_id)
      else
	 local gsm = self.statusspec:instantiate()
	 gsm.values.goal_id.values.id    = gh.goal_id
	 gsm.values.goal_id.values.stamp = gh.stamp
	 gsm.values.status = gh.state
	 gsm.values.text   = gh.text
	 table.insert(m.values.status_list, gsm)
	 if gh:state_changed() then status_updated = true end
      end
   end
   for _, goal_id in ipairs(expired) do
      status_updated = true
      self.goals[goal_id] = nil
   end
   local now = roslua.Time.now()
   if status_updated or self.last_status_update + self.status_update_interval <= now then
      m.values.header.values.seq   = self.status_seqnum
      self.status_seqnum = self.status_seqnum + 1
      self.pub_status:publish(m)
      self.last_status_update = now
   end
end

--- Spin the goals.
-- Calls the spin callback for all active goals.
function ActionServer:spin_goals()
   for goal_id, gh in pairs(self.goals) do
      if gh:is_active() then
	 gh:update_expiration()
	 if self.spin_cb then
	    self.spin_cb(gh, self)
	 end
      end
   end
end

--- Spin the action server.
-- Spins goals and publishes status as needed.
function ActionServer:spin()
   self:spin_goals()
   self:publish_status()
end
