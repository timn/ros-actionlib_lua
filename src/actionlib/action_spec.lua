
----------------------------------------------------------------------------
--  action_spec.lua - Action specification wrapper
--
--  Created: Fri Aug 06 11:41:07 2010 (at Intel Research, Pittsburgh)
--  License: BSD, cf. LICENSE file of roslua
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

--- action specification.
-- This module contains the ActionSpec class to read and represent ROS action
-- specification (YAML files). Action specifications should be obtained by
-- using the <code>get_actionspec()</code> function, which is aliased for
-- convenience as <code>actionlib.get_actionspec()</code>.
-- <br /><br />
-- The service files are read on the fly, no offline code generation is
-- necessary. This avoids the need to write yet another code generator. After
-- reading the service specifications contains three fields, the ...
-- @copyright Tim Niemueller, Carnegie Mellon University, Intel Research Pittsburgh
-- @release Released under BSD license
module("actionlib.action_spec", package.seeall)

require("roslua.msg_spec")

local MsgSpec = roslua.msg_spec.MsgSpec

local actionspec_cache = {}

--- Get service specification.
-- It is recommended to use the aliased version <code>roslua.get_actionspec()</code>.
-- @param action_type service type (e.g. std_msgs/String). The name must include
-- the package.
function get_actionspec(action_type)
   roslua.utils.assert_rospack()

   if not actionspec_cache[action_type] then
      actionspec_cache[action_type] = ActionSpec:new{type=action_type}
   end

   return actionspec_cache[action_type]
end


ActionSpec = { request = nil, response = nil }

--- Constructor.
-- @param o Object initializer, must contain a field type with the string
-- representation of the type name.
function ActionSpec:new(o)
   setmetatable(o, self)
   self.__index = self

   assert(o.type, "Action type is missing")

   o.package    = "roslib"
   o.short_type = o.type

   local slashpos = o.type:find("/")
   if slashpos then
      o.package    = o.type:sub(1, slashpos - 1)
      o.short_type = o.type:sub(slashpos + 1)
   end

   o.action_spec       = roslua.get_msgspec(o.type .. "Action")
   o.goal_spec         = roslua.get_msgspec(o.type .. "Goal")
   o.result_spec       = roslua.get_msgspec(o.type .. "Result")
   o.feedback_spec     = roslua.get_msgspec(o.type .. "Feedback")

   o.act_goal_spec     = roslua.get_msgspec(o.type .. "ActionGoal")
   o.act_feedback_spec = roslua.get_msgspec(o.type .. "ActionFeedback")
   o.act_result_spec   = roslua.get_msgspec(o.type .. "ActionResult")

   --[[ This code could be used to create messages directly from .action files,
   but since the msgs are built as files anyway, it's safer to just read them
   o:load()
   --]]

   return o
end

-- (internal) load from iterator
-- @param iterator iterator that returns one line of the specification at a time
function ActionSpec:load_from_iterator(iterator)
   self.fields = {}
   self.constants = {}

   local messages = {"", "", ""}
   local msgidx = 1

   -- extract the request and response message descriptions
   for line in iterator do
      if line == "---" then
	 msgidx = msgidx + 1
      else
	 messages[msgidx] = messages[msgidx] .. line .. "\n"
      end
   end

   local action_specstr = string.format("%sActionGoal action_goal\n"..
					"%sActionResult action_result\n"..
					"%sActionFeedback action_feedback\n",
				        self.type, self.type, self.type)

   local act_goal_specstr = string.format("Header header\n" ..
					  "actionlib_msgs/GoalID goal_id\n" ..
					  "%sGoal goal\n", self.type)

   local act_feedb_specstr = string.format("Header header\n" ..
					   "actionlib_msgs/GoalStatus status\n" ..
					   "%sFeedback feedback\n", self.type)

   local act_res_specstr = string.format("Header header\n" ..
					 "actionlib_msgs/GoalStatus status\n" ..
					 "%sResult result\n", self.type)

   self.action_spec   = roslua.get_msgspec(self.type .. "Action", action_specstr);
   self.goal_spec     = roslua.get_msgspec(self.type .. "Goal", messages[1]);
   self.result_spec   = roslua.get_msgspec(self.type .. "Result", messages[2]);
   self.feedback_spec = roslua.get_msgspec(self.type .. "Feedback", messages[3]);

   self.act_goal_spec  =
      roslua.get_msgspec(self.type .. "ActionGoal", act_goal_specstr);
   self.act_feedback_spec =
      roslua.get_msgspec(self.type .. "ActionFeedback", act_feedb_specstr);
   self.act_result_spec =
      roslua.get_msgspec(self.type .. "ActionResult", act_res_specstr);

end

--- Load specification from string.
-- @param s string containing the service specification
function ActionSpec:load_from_string(s)
   return self:load_from_iterator(s:gmatch("(.-)\n"))
end

--- Load service specification from file.
-- Will search for the appropriate service specification file (using rospack)
-- and will then read and parse the file.
function ActionSpec:load()
   local package_path = roslua.utils.find_rospack(self.package)
   self.file = package_path .. "/action/" .. self.short_type .. ".action"

   return self:load_from_iterator(io.lines(self.file))
end

--- Print specification.
-- @param indent string (normally spaces) to put before every line of output
function ActionSpec:print()
   print("Action " .. self.type)
   print("Messages:")
   print("\n*** GOAL")
   self.act_goal_spec:print("  ")
   print("\n*** RESULT")
   self.act_result_spec:print("  ")
   print("\n*** FEEDBACK")
   self.act_feedback_spec:print("  ")
end
