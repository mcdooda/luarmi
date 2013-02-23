-- from http://www.lua.org/cgi-bin/demo?account

-- account.lua
-- from PiL 1, Chapter 16

local Account = {balance = 0}

function Account:new (o, name)
  o = o or {name=name}
  setmetatable(o, self)
  self.__index = self
  return o
end

function Account:deposit (v)
  self.balance = self.balance + v
end

function Account:withdraw (v)
  if v > self.balance then error("insufficient funds on account "..self.name) end
  self.balance = self.balance - v
end

function Account:show (title)
  print(title or "", self.name, self.balance)
end

return Account
