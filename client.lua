#!/usr/bin/env lua5.1

local rmi = require 'rmi'

local client = rmi.client()
local a = client:lookup('account')

a:show("after creation")
a:deposit(1000.00)
a:show("after deposit")
a:withdraw(100.00)
a:show("after withdraw")

client:close()
