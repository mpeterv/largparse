local argparse = {}

local class = require "30log"

local Declarative = {}

function Declarative:__init(...)
   local cl = getmetatable(self)

   for _, field in ipairs(self._fields) do
      if not cl[field] then
         cl[field] = function(s, value)
            s["_" .. field] = value
            return s
         end
      end
   end

   self(...)
end

function Declarative:__call(...)
   local name_or_options

   for i=1, select("#", ...) do
      name_or_options = select(i, ...)

      if type(name_or_options) == "string" then
         if self._aliases then
            table.insert(self._aliases, name_or_options)
         end

         if not self._name then
            self._name = name_or_options
         end
      elseif type(name_or_options) == "table" then
         for _, field in ipairs(self._fields) do
            if name_or_options[field] ~= nil then
               self["_" .. field] = name_or_options[field]
            end
         end
      end
   end

   return self
end

local Parser = class {
   __name = "Parser",
   _arguments = {},
   _options = {},
   _commands = {},
   _require_command = false,
   _add_help = true,
   _fields = {
      "name", "description", "target", "require_command",
      "action", "usage", "help", "add_help"
   }
}:include(Declarative)

local Command = Parser:extends {
   __name = "Command",
   _aliases = {}
}

local Argument = class {
   __name = "Argument",
   _args = 1,
   _count = 1,
   _fields = {
      "name", "description", "target", "args",
      "minargs", "maxargs", "default", "convert",
      "action", "usage", "argname"
   }
}:include(Declarative)

local Option = Argument:extends {
   __name = "Option",
   _aliases = {},
   _count = "?",
   _overwrite = true,
   _fields = {
      "name", "aliases", "description", "target", 
      "args", "minargs", "maxargs", "count",
      "mincount", "maxcount", "default", "convert",
      "overwrite", "action", "usage", "argname"
   }
}

local Flag = Option:extends {
   __name = "Flag",
   _args = 0
}

function Argument:get_arg_usage(argname)
   argname = self._argname or argname
   local buf = {}
   local i = 1

   while i <= math.min(self._minargs, 3) do
      table.insert(buf, argname)
      i = i+1
   end

   while i <= math.min(self._maxargs, 3) do
      table.insert(buf, "[" .. argname .. "]")
      i = i+1

      if self._maxargs == math.huge then
         break
      end
   end

   if i < self._maxargs then
      table.insert(buf, "...")
   end

   return buf
end

function Argument:get_usage()
   if not self._usage then
      self._usage = table.concat(self:get_arg_usage("<" .. self._name .. ">"), " ")
   end

   return self._usage
end

function Argument:make_target()
   if not self._target then
      self._target = self._name
   end
end

function Argument:make_type()
   if self._maxcount == 1 then
      if self._maxargs == 0 then
         self.flag = true
      elseif self._maxargs == 1 and (self._minargs == 1 or self._mincount == 1) then
         self.arg = true
      else
         self.multiarg = true
      end
   else
      if self._maxargs == 0 then
         self.counter = true
      elseif self._maxargs == 1 and self._minargs == 1 then
         self.multicount = true
      else
         self.twodimensional = true
      end
   end
end

local function parse_boundaries(boundaries)
   if tonumber(boundaries) then
      return tonumber(boundaries), tonumber(boundaries)
   end

   if boundaries == "*" then
      return 0, math.huge
   end

   if boundaries == "+" then
      return 1, math.huge
   end

   if boundaries == "?" then
      return 0, 1
   end

   if boundaries:match "^%d+%-%d+$" then
      local min, max = boundaries:match "^(%d+)%-(%d+)$"
      return tonumber(min), tonumber(max)
   end

   if boundaries:match "^%d+%+$" then
      local min = boundaries:match "^(%d+)%+$"
      return tonumber(min), math.huge
   end
end

function Argument:make_boundaries()
   if not self._minargs or not self._maxargs then
      self._minargs, self._maxargs = parse_boundaries(self._args)
   end

   if not self._mincount or not self._maxcount then
      self._mincount, self._maxcount = parse_boundaries(self._count)
   end
end

function Argument:prepare()
   self:make_target()
   self:make_boundaries()
   self:make_type()
   return self
end

function Option:get_usage()
   if not self._usage then
      self._usage = self:get_arg_usage("<" .. self._target .. ">")
      table.insert(self._usage, 1, self._name)
      self._usage = table.concat(self._usage, " ")

      if self._mincount == 0 then
         self._usage = "[" .. self._usage .. "]"
      end
   end

   return self._usage
end

function Option:make_target()
   if not self._target then
      for _, alias in ipairs(self._aliases) do
         if alias:sub(1, 1) == alias:sub(2, 2) then
            self._target = alias:sub(3)
            break
         end
      end
   end

   self._target = self._target or self._aliases[1]:sub(2)
end

function Parser:argument(...)
   local argument = Argument:new(...)
   table.insert(self._arguments, argument)
   return argument
end

function Parser:option(...)
   local option = Option:new(...)
   table.insert(self._options, option)
   return option
end

function Parser:flag(...)
   local flag = Flag:new(...)
   table.insert(self._options, flag)
   return flag
end

function Parser:command(...)
   local command = Command:new(...)
   table.insert(self._commands, command)
   return command
end

function Parser:prepare()
   if self._add_help then
      self:flag "-h" "--help"
         :description "Show this help message and exit. "
         :action(function()
            io.stdout:write(self:get_help() .. "\r\n")
            os.exit(0)
         end)
   end

   for _, elements in ipairs{self._arguments, self._options} do
      for _, element in ipairs(elements) do
         element:prepare()
      end
   end

   for _, command in ipairs(self._commands) do
      command._target =command._target or command._name
      command._name = self._name .. " " .. command._name
   end

   return self
end

function Parser:error(fmt, ...)
   local msg = fmt:format(...)

   if _TEST then
      error(msg)
   else
      io.stderr:write(("%s\r\n\r\nError: %s\r\n"):format(self:get_usage(), msg))
      os.exit(1)
   end
end

function Parser:assert(assertion, ...)
   return assertion or self:error(...)
end

function Parser:update_charset(charset)
   charset = charset or {}

   for _, command in ipairs(self._commands) do
      command:update_charset(charset)
   end

   for _, option in ipairs(self._options) do
      for _, alias in ipairs(option._aliases) do
         charset[alias:sub(1, 1)] = true
      end
   end

   return charset
end

function Parser:get_usage()
   if not self._usage then
      local buf = {"Usage:", self._name}

      for _, elements in ipairs{self._options, self._arguments} do
         for _, element in ipairs(elements) do
            table.insert(buf, element:get_usage())
         end
      end

      if #self._commands > 0 then
         if self._require_command then
            table.insert(buf, "<command>")
         else
            table.insert(buf, "[<command>]")
         end

         table.insert(buf, "...")
      end

      -- TODO: prettify
      self._usage = table.concat(buf, " ")
   end

   return self._usage
end

local margin_len = 3
local margin_len2 = 25
local margin = (" "):rep(margin_len)
local margin2 = (" "):rep(margin_len2)

local function make_two_columns(s1, s2)
   if s2 == "" then
      return margin .. s1
   end

   s2 = s2:gsub("[\r\n][\r\n]?", function(sub)
      if #sub == 1 or sub == "\r\n" then
         return "\r\n" .. margin2
      else
         return "\r\n\r\n" .. margin2
      end
   end)

   if #s1 < (margin_len2-margin_len) then
      return margin .. s1 .. (" "):rep(margin_len2-margin_len-#s1) .. s2
   else
      return margin .. s1 .. "\r\n" .. margin2 .. s2
   end
end

local function make_description(element)
   if element._default then
      if element._description then
         return ("%s (default: %s)"):format(element._description, element._default)
      else
         return ("default: %s"):format(element._default)
      end
   else
      return element._description or ""
   end
end

local function make_name(option)
   local variants = {}
   local variant

   for _, alias in ipairs(option._aliases) do
      variant = option:get_arg_usage("<" .. option._target .. ">")
      table.insert(variant, 1, alias)
      variant = table.concat(variant, " ")
      table.insert(variants, variant)
   end

   return table.concat(variants, ", ")
end

function Parser:get_help()
   if not self._help then
      local blocks = {self:get_usage()}
      
      if self._description then
         table.insert(blocks, self._description)
      end

      if #self._arguments > 0 then
         local buf = {"Arguments: "}

         for _, argument in ipairs(self._arguments) do
            table.insert(buf, make_two_columns(argument._name, make_description(argument)))
         end

         table.insert(blocks, table.concat(buf, "\r\n"))
      end

      if #self._options > 0 then
         local buf = {"Options: "}

         for _, option in ipairs(self._options) do
            table.insert(buf, make_two_columns(make_name(option), make_description(option)))
         end

         table.insert(blocks, table.concat(buf, "\r\n"))
      end

      if #self._commands > 0 then
         local buf = {"Commands: "}

         for _, command in ipairs(self._commands) do
            table.insert(buf, make_two_columns(table.concat(command._aliases, ", "), command._description or ""))
         end

         table.insert(blocks, table.concat(buf, "\r\n"))
      end

      self._help = table.concat(blocks, "\r\n\r\n")
   end

   return self._help
end

local function get_tip(context, wrong_name)
   local context_pool = {}
   local possible_name
   local possible_names = {}

   for name in pairs(context) do
      for i=1, #name do
         possible_name = name:sub(1, i-1) .. name:sub(i+1)

         if not context_pool[possible_name] then
            context_pool[possible_name] = {}
         end

         table.insert(context_pool[possible_name], name)
      end
   end

   for i=1, #wrong_name+1 do
      possible_name = wrong_name:sub(1, i-1) .. wrong_name:sub(i+1)

      if context[possible_name] then
         possible_names[possible_name] = true
      elseif context_pool[possible_name] then
         for _, name in ipairs(context_pool[possible_name]) do
            possible_names[name] = true
         end
      end
   end

   local first = next(possible_names)
   if first then
      if next(possible_names, first) then
         local possible_names_arr = {}

         for name in pairs(possible_names) do
            table.insert(possible_names_arr, "'" .. name .. "'")
         end

         table.sort(possible_names_arr)
         return "\r\nDid you mean one of these: " .. table.concat(possible_names_arr, " ") .. "?"
      else
         return "\r\nDid you mean '" .. first .. "'?"
      end
   else
      return ""
   end
end

function Parser:parse(args)
   args = args or arg
   self._name = self._name or args[0]

   local parser
   local charset
   local options = {}
   local arguments = {}
   local commands
   local opt_context = {}
   local com_context
   local result = {}
   local invocations = {}
   local passed = {}
   local com_callbacks = {}
   local cur_option
   local cur_arg_i = 1
   local cur_arg

   local function convert(element, data)
      if element._convert then
         local ok, err = element._convert(data)

         return parser:assert(ok, "%s", err or "malformed argument '" .. data .. "'")
      else
         return data
      end
   end

   local invoke, pass, close

   function invoke(element)
      local overwrite = false

      if invocations[element] == element._maxcount then
         if element._overwrite then
            overwrite = true
         else
            parser:error("option '%s' must be used at most %d times", element._name, element._maxcount)
         end
      else
         invocations[element] = invocations[element]+1
      end

      passed[element] = 0

      if element.flag then
         result[element._target] = true
      elseif element.multiarg then
         result[element._target] = {}
      elseif element.counter then
         if not overwrite then
            result[element._target] = result[element._target]+1
         end
      elseif element.multicount then
         if overwrite then
            table.remove(result[element._target], 1)
         end
      elseif element.twodimensional then
         table.insert(result[element._target], {})

         if overwrite then
            table.remove(result[element._target], 1)
         end
      end

      if element._maxargs == 0 then
         close(element)
      end
   end

   function pass(element, data)
      passed[element] = passed[element]+1
      data = convert(element, data)

      if element.arg then
         result[element._target] = data
      elseif element.multiarg or element.multicount then
         table.insert(result[element._target], data)
      elseif element.twodimensional then
         table.insert(result[element._target][#result[element._target]], data)
      end

      if passed[element] == element._maxargs then
         close(element)
      end
   end

   function close(element)
      if passed[element] < element._minargs then
         if element._default then
            while passed[element] < element._minargs do
               pass(element, element._default)
            end
         else
            parser:error("too few arguments")
         end
      else
         if element == cur_option then
            cur_option = nil
         elseif element == cur_arg then
            cur_arg_i = cur_arg_i+1
            cur_arg = arguments[cur_arg_i]
         end

         if element._action then
            if element.multicount or element.twodimensional then
               element._action(result[element._target][#result[element._target]])
            else
               element._action(result[element._target])
            end
         end
      end
   end

   local function switch(p)
      parser = p:prepare()

      if parser._action then
         table.insert(com_callbacks, parser._action)
      end

      for _, option in ipairs(parser._options) do
         table.insert(options, option)

         for _, alias in ipairs(option._aliases) do
            opt_context[alias] = option
         end

         if option.counter then
            result[option._target] = 0
         elseif option.multicount or option.twodimensional then
            result[option._target] = {}
         end

         invocations[option] = 0
      end

      for _, argument in ipairs(parser._arguments) do
         table.insert(arguments, argument)
         invocations[argument] = 0
         invoke(argument)
      end

      cur_arg = arguments[cur_arg_i]
      commands = parser._commands
      com_context = {}

      for _, command in ipairs(commands) do
         for _, alias in ipairs(command._aliases) do
            com_context[alias] = command
         end
      end
   end

   local function get_option(name)
      if opt_context[name] then
         return opt_context[name]
      else
         parser:error("unknown option '%s'%s", name, get_tip(opt_context, name))
      end
   end

   local function handle_argument(data)
      if cur_option then
         pass(cur_option, data)
      elseif cur_arg then
         pass(cur_arg, data)
      else
         local com = com_context[data]

         if not com then
            if #commands > 0 then
               parser:error("unknown command '%s'%s", data, get_tip(com_context, data))
            else
               parser:error("too many arguments")
            end
         else
            result[com._target] = true
            switch(com)
         end
      end
   end

   local function handle_option(data)
      if cur_option then
         close(cur_option)
      end

      cur_option = opt_context[data]
      invoke(cur_option)
   end

   local function mainloop()
      local handle_options = true

      for _, data in ipairs(args) do
         local plain = true
         local first, name, option

         if handle_options then
            first = data:sub(1, 1)
            if charset[first] then
               if #data > 1 then
                  if data:sub(2, 2):match "[a-zA-Z]" then
                     plain = false

                     for i = 2, #data do
                        name = first .. data:sub(i, i)
                        option = get_option(name)
                        handle_option(name)

                        if i ~= #data and option._minargs > 0 then
                           handle_argument(data:sub(i+1))
                           break
                        end
                     end
                  elseif data:sub(2, 2) == first then
                     if #data == 2 then
                        plain = false
                        handle_options = false
                     elseif data:sub(3, 3):match "[a-zA-Z]" then
                        plain = false

                        local equal = data:find "="
                        if equal then
                           name = data:sub(1, equal-1)
                           option = get_option(name)
                           parser:assert(option._maxargs > 0, "option '%s' does not take arguments", name)

                           handle_option(data:sub(1, equal-1))
                           handle_argument(data:sub(equal+1))
                        else
                           get_option(data)
                           handle_option(data)
                        end
                     end
                  end
               end
            end
         end

         if plain then
            handle_argument(data)
         end
      end
   end

   switch(self)
   charset = parser:update_charset()
   mainloop()

   if cur_option then
      close(cur_option)
   end

   while cur_arg do
      close(cur_arg)
   end

   if parser._require_command and #commands > 0 then
      parser:error("command is required")
   end

   for _, option in ipairs(options) do
      parser:assert(invocations[option] >= option._mincount,
         "option '%s' must be used at least %d times", option._name, option._mincount
      )
   end

   for _, callback in ipairs(com_callbacks) do
      callback(result)
   end

   return result
end

argparse.parser = Parser

return argparse
