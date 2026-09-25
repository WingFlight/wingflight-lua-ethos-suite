-- Run from the repository root: lua bin/tests/elrs_sync.lua
-- Mock transports only; never writes to a radio or FC.
local function equal(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local function str(data,text)
  for i=1,#text do data[#data+1]=text:byte(i) end
  data[#data+1]=0
end
local function info(name,serial,address)
  local data={0xEA,address or 0xEE}; str(data,name)
  for _,b in ipairs(serial or {0x45,0x4C,0x52,0x53}) do data[#data+1]=b end
  for _=1,8 do data[#data+1]=0 end
  data[#data+1]=2; data[#data+1]=0
  return {0x29,data}
end
local function field(id,name,options)
  local data={0xEA,0xEE,id,0,0,9}; str(data,name); str(data,options)
  data[#data+1]=0
  return {0x2B,data}
end
local function setup()
  package.loaded['wfsuite.lib.elrslink_task']=nil
  local handlers,frames,sent,requests={},{},{},{}
  local bus={
    subscribe=function(_,fn) handlers[#handlers+1]=fn; return fn end,
    publish=function(_,message)
      if message.kind=='read' then
        message.ok({crsf_telemetry_mode=1,crsf_telemetry_link_rate=250,crsf_telemetry_link_ratio=64})
      else requests[#requests+1]=message end
    end,
  }
  local modules={
    ['lib/bus.lua']=bus,
    ['lib/debug_log.lua']={print=function() end},
    ['lib/msp_telemetry_config.lua']={
      buildReadConfigMessage=function(ok,err) return {kind='read',ok=ok,err=err} end,
      buildWriteMessage=function(data,ok,err) return {kind='write',ok=ok,err=err} end,
    },
    ['lib/msp_eeprom.lua']={buildWriteMessage=function(ok,err) return {kind='eeprom',ok=ok,err=err} end},
  }
  package.loaded['wfsuite.lib.require']=function(path) return assert(modules[path],path) end
  system={getVersion=function() return {simulation=false} end}
  local sensor={
    popFrame=function() local f=table.remove(frames,1); if f then return f[1],f[2] end end,
    pushFrame=function(_,command,data) sent[#sent+1]={command,data} end,
  }
  crsf={getSensor=function() return sensor end}
  local task=assert(loadfile('src/wfsuite/lib/elrslink_task.lua'))()
  local function session(armed,connected)
    for _,fn in ipairs(handlers) do fn({connected=connected~=false,isArmed=armed,mspTransport='crsf'}) end
  end
  session(false)
  return task,frames,sent,requests,session
end
local function discover(task,frames,mode,device)
  assert(task.start(mode)); task.wakeup()
  frames[#frames+1]=device or info('TX')
  task.wakeup()
end
local function parameters(task,frames)
  frames[#frames+1]=field(1,'Packet Rate','100Hz;250Hz')
  frames[#frames+1]=field(2,'Telemetry Ratio','1:32;1:64')
  task.wakeup()
end

-- A Crossfire response must stop discovery before any parameter frames.
local task,frames,sent,requests,session=setup()
discover(task,frames,task.MODE_FC_TO_ELRS,info('TBS Crossfire',{0,0,0,1}))
assert(not task.isRunning() and not task.isVerified())
equal(#sent,0); equal(#requests,0)
assert(task.getStatus():find('status_not_elrs',1,true))
-- A queued second response cannot revive the failed operation.
frames[#frames+1]=info('ExpressLRS'); task.wakeup(); assert(not task.isVerified())

for _,device in ipairs({info('TX'),info('ExpressLRS TX',{0,0,0,1}),info('ELRS TX',{0,0,0,1})}) do
  task,frames,sent,requests,session=setup()
  discover(task,frames,task.MODE_PROBE,device)
  assert(task.isVerified()); equal(sent[1][1],0x2C)
  parameters(task,frames)
  assert(not task.isRunning()); equal(#requests,0)
  for _,frame in ipairs(sent) do assert(frame[1]~=0x2D) end
end

task,frames,sent,requests,session=setup()
assert(task.start(task.MODE_PROBE)); task.wakeup()
frames[#frames+1]=info('RX',nil,0xEC); task.wakeup(); assert(not task.isVerified())
frames[#frames+1]={0x29,{0xEA,0xEE,69,76,82,83,0}}; task.wakeup(); assert(not task.isVerified())
session(true); assert(not task.start(task.MODE_FC_TO_ELRS))

task,frames,sent,requests,session=setup()
discover(task,frames,task.MODE_FC_TO_ELRS)
parameters(task,frames)
assert(task.isRunning()) -- two writes queued, only the first sent
local before=#sent
session(true); task.wakeup(); assert(not task.isRunning())
session(false); task.wakeup(); equal(#sent,before)
assert(task.getStatus():find('status_unavailable_armed',1,true))

-- FC callback arriving after arming/reset/disconnect must not queue EEPROM.
for _,abort in ipairs({'armed','reset','disconnect'}) do
  task,frames,sent,requests,session=setup()
  discover(task,frames,task.MODE_ELRS_TO_FC); parameters(task,frames)
  equal(#requests,1); equal(requests[1].kind,'write')
  if abort=='armed' then session(true)
  elseif abort=='reset' then task.reset()
  else session(false,false) end
  local status=task.getStatus()
  requests[1].ok(); equal(#requests,1); equal(task.getStatus(),status)
end
-- Normal disarmed sync still commits and completes.
task,frames,sent,requests,session=setup()
discover(task,frames,task.MODE_ELRS_TO_FC); parameters(task,frames)
requests[1].ok(); equal(requests[2].kind,'eeprom')
requests[2].ok(); assert(not task.isRunning())

-- Page confirmation and retained-session initial button state.
local function pageSetup(armed)
  local handler,cleanup,wakeup,dialog,lastDialog
  local buttons,starts={},{}
  local running=false
  local mockTask={MODE_PROBE=0,MODE_FC_TO_ELRS=1,MODE_ELRS_TO_FC=2,
    reset=function() running=false end, refreshFcConfig=function() end,
    isRunning=function() return running end, start=function(mode) starts[#starts+1]=mode; running=true end,
    getStatus=function() return 'status' end, getModeLabel=function() return 'mode' end,
    getFcSummary=function() end, getLinkSummary=function() end, wakeup=function() end}
  local modules={['lib/elrslink_task.lua']=mockTask,
    ['lib/bus.lua']={subscribe=function(_,fn) handler=fn; fn({connected=true,isArmed=armed,mspTransport='crsf'}); return fn end,unsubscribe=function() handler=nil end},
    ['app/close_key.lua']={shouldHandleClose=function() return false end},
    ['app/header.lua']={build=function() return {} end}}
  package.loaded['wfsuite.lib.require']=function(path) return assert(modules[path]) end
  FONT_S,CENTERED,TEXT_LEFT=1,2,3
  form={clear=function() end,addLine=function() return {} end,
    addStaticText=function() return {value=function() end} end,
    getFieldSlots=function() return {{},{},{},{}} end,
    addButton=function(_,_,spec)
      local b={press=spec.press,enable=function(self,value) self.enabled=value end}
      buttons[#buttons+1]=b; return b
    end,
    openDialog=function(spec)
      dialog={spec=spec,close=function(self) self.closed=true; spec.close() end}
      lastDialog=dialog; return dialog
    end}
  assert(loadfile('src/wfsuite/app/pages/diagnostics_elrs_link.lua'))().open({
    setCleanupHandler=function(fn) cleanup=fn end,setWakeupHandler=function(fn) wakeup=fn end})
  return buttons,starts,function() return lastDialog end,function(value) handler({connected=true,isArmed=value,mspTransport='crsf'}) end,function() cleanup() end,mockTask
end
local buttons,starts,getDialog,update,close,mockTask=pageSetup(true)
for _,b in ipairs(buttons) do equal(b.enabled,false); b.press() end
equal(#starts,0); equal(getDialog(),nil)
update(false); buttons[2].press(); equal(#starts,0)
local dialog=getDialog(); dialog.spec.buttons[2].action(); dialog:close(); equal(#starts,0)
buttons[2].press(); dialog=getDialog(); dialog.spec.buttons[1].action(); dialog:close()
equal(starts[1],1)
buttons[3].press(); equal(#starts,1) -- running guard
mockTask.reset(); update(false); buttons[3].press(); dialog=getDialog()
update(true); assert(dialog.closed); dialog.spec.buttons[1].action(); equal(#starts,1)
update(false); buttons[3].press(); dialog=getDialog(); close()
assert(dialog.closed); dialog.spec.buttons[1].action(); equal(#starts,1)
buttons,starts,getDialog,update,close=pageSetup(false)
buttons[1].press(); equal(starts[1],0); equal(getDialog(),nil); close()
buttons,starts,getDialog,update,close=pageSetup(false)
form.openDialog=nil; buttons[2].press(); equal(#starts,0); close()
print('ELRS checks passed: verification, probe/sync, armed aborts, late callbacks, confirmation and cleanup')
