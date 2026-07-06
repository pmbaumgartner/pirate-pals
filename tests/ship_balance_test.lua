package.path = './?.lua;' .. package.path
local sim = require 'src.dev.balance_sim'

local success = sim.runAll(1000)
if not success then
  print("FAIL: Ship combat balance check failed!")
  os.exit(1)
else
  print("ship_balance_test OK")
  os.exit(0)
end
