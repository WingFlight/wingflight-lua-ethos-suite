-- Run from the repository root with Lua 5.3+.
-- Exercise the session task with mocked telemetry/MSP and the real status decoder.
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local clock = os.clock
local function fixture(armed)
  local now, active, raw = 10, true, armed and 1 or 0
  local snapshots, handlers, counts, pending = {}, {}, {}, {}
  local clears, decodes, reject = 0, 0, nil
  os.clock=function() return now end
  system={getVersion=function() return {} end,getSource=function() return {state=function() return active end} end,
    playFile=function() end}
  local function builder(key)
    return function(ok,err) return {key=key,ok=ok,err=err} end
  end
  local noop=function() end
  local status=assert(loadfile('src/wfsuite/lib/system_status.lua'))()
  local modules={
    ['lib/msp_handshake.lua']={buildFcVersionReadMessage=builder('fcVariant'),buildUidReadMessage=builder('mcuId'),
      buildNameReadMessage=builder('craftName'),buildRtcSyncMessage=builder('clockSynced')},
    ['lib/msp_api_version.lua']={buildReadMessage=builder('apiVersion'),isSupported=function(major) return major==13 end},
    ['lib/msp_battery.lua']={buildBatteryConfigReadMessage=builder('batteryConfig'),buildSmartfuelConfigReadMessage=builder('smartfuelConfig')},
    ['lib/msp_rx_map.lua']={buildReadMessage=builder('rxMap')},
    ['lib/msp_telemetry_config.lua']={buildReadMessage=builder('telemetry')},
    ['lib/msp_dataflash_summary.lua']={buildReadMessage=builder('blackbox')},
    ['lib/msp_flight_stats.lua']={buildReadMessage=builder('stats')},
    ['lib/msp_eeprom.lua']={},['lib/smartfuel_reserve.lua']={},
    ['lib/smartfuel_calc.lua']={new=function() return {reset=noop,update=function() return nil end} end},
    ['lib/diy_sensor.lua']={new=function() return {reset=noop,set=noop} end},
    ['lib/model_preferences.lua']={load=function() return {} end,stats=function() return {} end,
      timerTarget=function() return 300 end,smartfuelModelType=function() return 0 end},
    ['tasks/flight_timer.lua']={reset=noop,update=function() return false end},
    ['tasks/elrs_sensors.lua']={wakeup=noop,reset=noop},
    ['lib/system_status.lua']={copy=status.copy,decodeConfig=status.decodeConfig,decodeStatus=function(value)
      decodes=decodes+1; return status.decodeStatus(value)
    end},
  }
  package.loaded['wfsuite.lib.require']=function(path) return assert(modules[path],path) end
  local queue={add=function(_,msg)
    counts[msg.key]=(counts[msg.key] or 0)+1
    if msg.key==reject then if msg.err then msg.err('queue_full') end; return false end
    assert(not pending[msg.key], 'duplicate '..msg.key); pending[msg.key]=msg; return true
  end,clear=function()
    clears=clears+1; local dropped=pending; pending={}
    for _,msg in pairs(dropped) do if msg.err then msg.err('cleared') end end
  end}
  local bus={subscribe=function(topic,fn) handlers[topic]=fn end,publish=function(topic,value)
    if topic=='session.update' then snapshots[#snapshots+1]=value
    elseif topic=='msp.request' then queue:add(value) end
  end}
  local task=assert(loadfile('src/wfsuite/tasks/session.lua'))(bus,
    {load=function() return {} end,syncNameEnabled=function() return false end},{print=noop})
  task.setTelemetrySensors({getValue=function(_,key) if key=='system_status' then return raw end end,reset=noop})
  return {
    wake=function(dt) now=now+(dt or 0.05); task.wakeup(queue,'crsf') end,
    arm=function(value) raw=value end,connect=function(value) active=value end,
    reply=function(key,data,reason)
      local msg=assert(pending[key],key); pending[key]=nil
      if reason then assert(msg.err)(reason) else msg.ok(data) end
    end,
    pending=function(key) return pending[key]~=nil end,count=function(key) return counts[key] or 0 end,
    snapshot=function() return snapshots[#snapshots] end,complete=task.isHandshakeComplete,
    clears=function() return clears end,decodes=function() return decodes end,
    reject=function(key) reject=key end,emit=function(topic) handlers[topic]() end,
  }
end
local f=fixture(false)
f.wake(); eq(f.count('apiVersion'),1)
f.reply('apiVersion',{major=13,minor=9}); f.wake()
local old=f.snapshot(); eq(old.handshake.apiVersion,true)
f.arm(1); f.wake(); eq(f.clears(),1); eq(f.pending('craftName'),false)
eq(f.snapshot().handshake.smartfuelConfig,false); eq(f.snapshot().handshake.clockSynced,false)
f.wake(3); eq(f.count('craftName'),1); eq(f.clears(),1)
f.arm(nil); f.wake(); eq(f.snapshot().isArmed,true)
f.arm(0); f.wake(); eq(f.count('apiVersion'),1); eq(f.count('craftName'),2)
f.wake(3); eq(f.count('craftName'),2) -- no duplicate while pending
f.reply('fcVariant',{fcVersion='1',rfVersion='2'})
f.reply('mcuId','uid'); f.reply('craftName','Plane'); f.reply('clockSynced',nil,'timeout')
f.reply('batteryConfig',{}); f.reply('smartfuelConfig',nil,'unsupported'); f.reply('rxMap',{throttle=2})
f.reply('telemetry',{}); f.wake(); eq(f.complete(),true)
eq(old.handshake.craftName,false) -- snapshots never expose the live flags
local decoded=f.decodes(); f.wake(); eq(f.decodes(),decoded)
f.arm(1); f.wake(); f.arm(0); f.wake(); eq(f.count('craftName'),2)
f.connect(false); f.wake(); eq(f.complete(),false); eq(f.snapshot().craftName,nil)
f.connect(true); f.wake(); eq(f.count('apiVersion'),2)
-- Connect while armed: no handshake/telemetry requests until disarm.
f=fixture(true); f.wake(); eq(f.count('apiVersion'),0); eq(f.count('telemetry'),0)
f.wake(3); eq(f.count('apiVersion'),0)
f.arm(0); f.wake(); eq(f.count('apiVersion'),1)
-- Genuine failures retry after two seconds, including a rejected queue insertion.
f.reply('apiVersion',nil,'timeout'); f.wake(); eq(f.count('apiVersion'),1)
f.wake(2); eq(f.count('apiVersion'),2)
f.reply('craftName',nil,'timeout'); f.reject('craftName'); f.wake(2)
f.reject(nil); f.wake(2); eq(f.count('craftName'),3)
-- A cleared post-save SmartFuel refresh must be retried, not choose mode-0 fallback.
f.reply('smartfuelConfig',{mode=2}); f.emit('smartfuel.config.saved')
f.arm(1); f.wake(); eq(f.snapshot().handshake.smartfuelConfig,false)
f.arm(0); f.wake(); eq(f.pending('smartfuelConfig'),true)
-- Queue pressure cannot prematurely complete optional handshake steps.
for _,key in ipairs({'clockSynced','smartfuelConfig'}) do
  f=fixture(false); f.reject(key); f.wake()
  eq(f.snapshot().handshake[key],false)
  f.reject(nil); f.wake(2); eq(f.pending(key),true)
end
-- A cancelled battery refresh also resumes after disarm.
f=fixture(false); f.wake(); f.reply('batteryConfig',{}); f.emit('battery.config.saved')
f.arm(1); f.wake(); eq(f.snapshot().handshake.batteryConfig,false)
f.arm(0); f.wake(); eq(f.pending('batteryConfig'),true)
-- Unsupported firmware doesn't start a perpetual retry loop.
f=fixture(false); f.wake(); f.reply('apiVersion',{major=12,minor=9})
f.reply('craftName',nil,'timeout'); f.wake(3); eq(f.count('craftName'),1)
-- Disconnect cancels outstanding requests before resetting metadata.
f.connect(false); f.wake(); eq(f.pending('mcuId'),false); eq(f.snapshot().mcuId,nil)
os.clock=clock
print('session handshake checks passed')
