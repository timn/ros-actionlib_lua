
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
--acl.actspec:print()
acl:wait_for_server()
--acl:cancel_all_goals()

local goal = acl.actspec.goal_spec:instantiate()
goal.values.order = 5
acl:send_goal(goal, function (gh) print("Event", gh.state) end)

roslua.run()
