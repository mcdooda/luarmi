local socket = require 'socket'

local function print() end

local function send(s, value)
  print('->\''..value..'\'')
  s:send(value..'\n')
end

local function receive(s)
  local received = {}
  local data, status, partial
  while true do
    data, status, partial = s:receive('*l')
   -- print('received', data, status, partial)
    received[#received + 1] = data or partial
    if data then
      break
    elseif status == 'closed' then
      return nil, 'closed'
    elseif not partial then
      return nil, status
    end
  end
  local line = table.concat(received)
  print('<-\''..line..'\'')
  return line, status
end

local function serialize(value)
  local t = type(value)
  local serialized
  if t == 'string' then
    t = 's'
    serialized = value:gsub('\n', '\\n')
  elseif t == 'number' then
    t = 'n'
    serialized = tostring(value)
  elseif t == 'boolean' then
    t = 'b'
    serialized = value and 't' or 'f'
  elseif getmetatable(value) == Remote then
    t = 'r'
    serialized = tostring(value.id)
  else
    return nil, value..' not serializable'
  end
  return t, serialized
end

local function unserialize(t, value)
  if t == 's' then
    return value:gsub('\\n', '\n')
  elseif t == 'n' then
    return tonumber(value)
  elseif t == 'b' then
    return value == 't'
  elseif t == 'r' then
    return nil, 'not done yet'
  else
    return nil, value..' not unserializable'
  end
end

local function serialize_send(s, value)
  local t, serialized = assert(serialize(value))
  print('->t')
  send(s, t)
  print('->serialized')
  send(s, serialized)
end

local function receive_unserialize(s)
  print('<-t')
  local t = receive(s)
  print('<-serialized')
  local serialized = receive(s)
  local value = assert(unserialize(t, serialized))
  return value
end

local LOOKUP_CODE = 'l' -- client:lookup
local CALL_CODE = 'c'   -- remote method call
local FIELD_CODE = 'f'  -- remote field access

------------
-- Remote --
------------
local Remote = {}

function Remote.__index(self, methodname)
  local s = self.socket
  local id = self.id
  print('->FIELD_CODE')
  send(s, FIELD_CODE)
  print('->id')
  send(s, id)
  print('->methodname')
  send(s, methodname)
  print('<-t')
  local t = receive(s)
  if t == 'm' then -- let's assume the field won't change into a non function type
    return function(self, ...)
      print('->CALL_CODE')
      send(s, CALL_CODE)
      print('->id')
      send(s, id)
      print('->methodname')
      send(s, methodname)
      local numargs = select('#', ...)
      print('->numargs')
      send(s, numargs)
      for i = 1, numargs do -- useless to send self
        serialize_send(s, select(i, ...))
      end
      print('<-numresults')
      local numresults = tonumber(receive(s), nil)
      local results = {}
      for i = 1, numresults do
        results[i] = receive_unserialize(s)
      end
      return unpack(results)
    end
  elseif t == 'f' then
    return receive_unserialize(s)
  else
    error('unknown field type '..t)
  end
end

function Remote:new(id, s)
  return setmetatable({
    id = id,
    socket = s
  }, Remote)
end


------------
-- Server --
------------

local Server = {}
Server.__index = Server

function Server:new(port)
  port = port or 4044
  return setmetatable({
    objects = {},
    nameids = {},
    port = port
  }, Server)
end

function Server:bind(name, object)
  local id = #self.objects + 1
  self.objects[id] = object
  self.nameids[name] = id
end

function Server:serve()
  local server = assert(socket.bind("*", self.port))
  while true do
    local client = server:accept()
    client:settimeout(0)
    while true do
      print('<-code')
      local code, status = receive(client)
      if status == 'closed' then break end
      
      if code == LOOKUP_CODE then
        -- lookup
        print('<-name')
        local name = receive(client)
        local id = self.nameids[name]
        print('->id')
        send(client, id)
      elseif code == FIELD_CODE then
        print('<-id')
        local id = tonumber(receive(client), nil)
        local object = self.objects[id]
        print('<-methodname')
        local methodname = receive(client)
        local fieldvalue = object[methodname]
        if type(fieldvalue) == 'function' then
          print('->t')
          send(client, 'm')
        else
          print('->t')
          send(client, 'f')
          serialize_send(client, fieldvalue)
        end
      elseif code == CALL_CODE then
        -- method call
        print('<-id')
        local id = tonumber(receive(client), nil)
        local object = self.objects[id]
        print('<-methodname')
        local methodname = receive(client)
        print('<-numargs')
        local numargs = tonumber(receive(client), nil)
        local results
        if numargs > 0 then
          local args = {}
          for i = 1, numargs do
            args[i] = receive_unserialize(client)
          end
          results = { object[methodname](object, unpack(args)) }
        else
          results = { object[methodname](object) }
        end
        local numresults = #results
        print('->numresults')
        send(client, numresults)
        for i = 1, numresults do
          serialize_send(s, results[i])
        end
      else
        error('unknown code command '..code)
      end
    end
  end
end

------------
-- Client --
------------

local Client = {}
Client.__index = Client

function Client:new(host, port)
  host = host or 'localhost'
  port = port or 4044
  local s = assert(socket.connect(host, port))
  s:settimeout(0)
  return setmetatable({
    socket = s
  }, self)
end

function Client:close()
  self.socket:close()
end

function Client:lookup(name)
  local s = self.socket
  send(s, LOOKUP_CODE)
  send(s, name)
  local id = receive(s)
  return Remote:new(id, s)
end

---------
-- Rmi --
---------

local rmi = {}
rmi.version = '0.1'

function rmi.server(port)
  return Server:new(port)
end

function rmi.client(host, port)
  return Client:new(host, port)
end

return rmi
