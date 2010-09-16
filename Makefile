include $(shell rospack find mk)/cmake.mk

ROSLUA_PATH=$(shell rospack find roslua)

.PHONY: doc
doc:
	LUA_PATH="./?.lua;$(ROSLUA_PATH)/?.lua;/usr/share/lua/5.1/?.lua;/usr/share/lua/5.1/?/init.lua" \
	luadoc --nofiles -d doc/ -t etc/luadoc src/actionlib/*.lua
	sed -i '/<!-- README -->/ r README' doc/index.html

