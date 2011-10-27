
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

roslua.init_node{node_name="actionservertest"}

print()
print("Action server tests")

print()

function goal_cb(gh, as)
   printf("Goal %s received", gh.goal_id)
   gh.vars.order = gh.goalmsg.values.goal.values.order
   gh.vars.i     = 2
   gh.vars.seq   = {0, 1}
   if math.random() > 0.8 then -- with a small probability reject
      gh:reject()
   end
end

function spin(gh, as)
   if gh.vars.i < gh.vars.order then
      table.insert(gh.vars.seq, gh.vars.seq[gh.vars.i] + gh.vars.seq[gh.vars.i-1])
      local feedback = as.actspec.feedback_spec:instantiate()
      feedback.values.sequence = gh.vars.seq

      as:publish_feedback(gh, feedback)
      gh.vars.i = gh.vars.i + 1
   elseif gh.vars.i > 40 then
      -- only to demonstrate aborting goals
      gh:abort()
   else
      printf("Sending result for goal %s", gh.goal_id)
      -- send result
      local result = as.actspec.result_spec:instantiate()
      result.values.sequence = gh.vars.seq
      gh:finish(result)
   end
end

function cancel_cb(gh, as)
   printf("Goal %s has been canceled", gh.goal_id)
end

as = actionlib.action_server("/fibonacci", "actionlib_tutorials/Fibonacci",
			     goal_cb, spin, cancel_cb)

roslua.run(10)
