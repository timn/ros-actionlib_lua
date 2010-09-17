
----------------------------------------------------------------------------
--  actionclienttest.lua - Action client test script
--
--  Created: Mon Aug 09 16:29:14 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

require("roslua")
require("actionlib")

roslua.init_node{master_uri=os.getenv("ROS_MASTER_URI"), node_name="/actionclienttest"}

print()
print("Action client tests")
print()

local acl = actionlib.action_client("/fibonacci", "actionlib_tutorials/Fibonacci")
acl.debug = true
--acl.actspec:print()
printf("Waiting for action server")
acl:wait_for_server()
printf("Connected")
--acl:cancel_all_goals()

GOAL_ORDER = 30

function listener(goal_handle, acl)
   if goal_handle:state_changed() then
      printf("State changed: %s -> %s", goal_handle.STATE_TO_STRING[goal_handle.last_state],
	     goal_handle.STATE_TO_STRING[goal_handle.state])
      if goal_handle:terminal() then
	 printf("Terminal state reached, issuing new goal")
	 local goal = acl.actspec.goal_spec:instantiate()
	 goal.values.order = GOAL_ORDER
	 acl:send_goal(goal, listener)
      end
   elseif goal_handle:feedback_received() then
      if #goal_handle.feedback.values.sequence == 15 and math.random() > 0.8 then
	 printf("Canceling")
	 goal_handle:cancel()
      else
	 printf("Feedback received: (%d) %s", #goal_handle.feedback.values.sequence,
		table.concat(goal_handle.feedback.values.sequence, ", "))
      end
   end
end

local goal = acl.actspec.goal_spec:instantiate()
goal.values.order = GOAL_ORDER
printf("Sending goal")
acl:send_goal(goal, listener)

roslua.run(0.5)
