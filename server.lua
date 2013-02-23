#!/usr/bin/env lua5.1

local rmi = require 'rmi'
local Account = require 'account'

local a = Account:new(nil, "demo")

local server = rmi.server()
server:bind('account', a)
server:serve()
