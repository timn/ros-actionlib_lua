
----------------------------------------------------------------------------
--  actionspectest.lua - Action specification test script
--
--  Created: Fri Aug 06 10:21:04 2010 (at Intel Research, Pittsburgh)
--  Copyright  2010  Tim Niemueller [www.niemueller.de]
--
----------------------------------------------------------------------------

-- Licensed under BSD license

require("roslua")
require("actionlib")

roslua.init_node{node_name="actionspectest"}

print()
print("Action spec tests")

print()
local actionspec = actionlib.get_actionspec("actionlib/Test")
actionspec:print()

