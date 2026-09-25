-- Run from the repository root: lua bin/tests/page_runtime.lua
-- Mocked UI and MSP transport: no physical radio or flight controller required.
local function equal(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
KEY_ENTER_LONG,KEY_ENTER_BREAK=100,101
system={killEvents=function(key) equal(key,KEY_ENTER_BREAK) end}
local function fixture(multi, armedGate, prefetched)
  package.loaded['wfsuite.app.page_runtime']=nil
  local reads, writes, dialogs={},{},{}
  local wakeup,event,cleanup,headerOptions
  local focused,enabled,enableCalls=nil,nil,0
  local confirmations=true
  local noProgress=false
  local progress={SPEED={DEFAULT=1},open=function()
    if noProgress then return nil end
    return {value=function() end,close=function(self) self.closed=true end}
  end}
  local function readMessage(ok,err) return {kind='read',ok=ok,err=err} end
  local function writeMessage(data,ok,err) return {kind='write',data=data,ok=ok,err=err} end
  local codec={buildReadMessage=readMessage,buildWriteMessage=writeMessage}
  local modules={
    ['lib/bus.lua']={subscribe=function(_,fn) fn({pidProfile=1,isArmed=false}) end,unsubscribe=function() end,
      publish=function(_,msg)
        if msg.kind=='read' then reads[#reads+1]=msg
        else writes[#writes+1]=msg; msg.ok() end
      end},
    ['lib/msp_eeprom.lua']={buildWriteMessage=function(ok,err) return {kind='eeprom',ok=ok,err=err} end},
    ['lib/msp_reboot.lua']={},
    ['app/close_key.lua']={shouldHandleClose=function() return false end},
    ['app/header.lua']={build=function(_,options)
      headerOptions=options
      return {setTitle=function() end,setSaveEnabled=function(value) enabled=value; enableCalls=enableCalls+1 end,
        setReloadEnabled=function() end,focusMenu=function() focused='menu' end,
        focusSave=function() focused='save' end,focusReload=function() focused='reload' end}
    end},
    ['lib/memstats.lua']={print=function() end},['lib/debug_log.lua']={print=function() end},
    ['lib/settings_store.lua']={load=function() return {} end,
      saveConfirmEnabled=function() return confirmations end,reloadConfirmEnabled=function() return false end},
    ['app/progress_dialog.lua']=progress,
  }
  package.loaded['wfsuite.lib.require']=function(path) return assert(modules[path],path) end
  form={openDialog=function(spec)
    local dialog={spec=spec,close=function(self) self.closed=true; if spec.close then spec.close() end end}
    dialogs[#dialogs+1]=dialog; return dialog
  end}
  local Runtime=assert(loadfile('src/wfsuite/app/page_runtime.lua'))()
  local opts={setWakeupHandler=function(fn) wakeup=fn end,setEventHandler=function(fn) event=fn end,
    setCleanupHandler=function(fn) cleanup=fn end}
  local config={pageTitle='Test',mspModule=codec,opts=opts,isMspPage=armedGate,initialData=prefetched}
  if multi then config.sources={{key='a',mspModule=codec},{key='b',mspModule=codec}} end
  local rt=Runtime.new(config)
  rt:setBusy(true); equal(rt.busy,true) -- state must update even before chrome exists
  rt:setBusy(false)
  rt:buildChrome()
  local field={enable=function(self,value) self.enabled=value end}
  rt:registerField('test',field)
  return rt,{
    reads=reads,writes=writes,dialogs=dialogs,field=field,
    wake=function() wakeup() end,key=function() event(0,KEY_ENTER_LONG) end,
    save=function() headerOptions.onSave() end,reload=function() headerOptions.onReload() end,
    cleanup=function() cleanup() end,focus=function() return focused end,
    enabled=function() return enabled end,enableCalls=function() return enableCalls end,
    noConfirm=function() confirmations=false end,noProgress=function() noProgress=true end,
  }
end
local function finishRead(ui,data)
  local msg=table.remove(ui.reads,1); assert(msg); msg.ok(data or {value=10})
end
local function failRead(ui)
  local msg=table.remove(ui.reads,1); assert(msg); msg.err('timeout')
end
local function accept(dialog)
  dialog.spec.buttons[1].action(); dialog:close()
end

local rt,ui=fixture(false,true)
assert(not rt:canSave()); ui.key(); ui.wake(); equal(#ui.dialogs,0)
rt:performSave(); rt:confirmSave(); ui.save(); equal(#ui.writes,0)
rt:loadInitial(); assert(rt.busy and not rt.loaded and not ui.field.enabled)
rt:markDirty(); ui.key(); ui.save(); rt:performSave(); equal(#ui.writes,0)
finishRead(ui); ui.wake()
assert(rt.loaded and not rt.dirty and not rt.busy and ui.field.enabled)
ui.key(); ui.wake(); equal(#ui.dialogs,0) -- unchanged page is not savable
rt:markDirty(); assert(rt:canSave()); equal(ui.enabled(),true)
local count=ui.enableCalls()
for _=1,20 do rt:onSessionUpdate({pidProfile=1,isArmed=false}) end
equal(ui.enableCalls(),count) -- unchanged snapshots do not repeat enable calls
rt:onSessionUpdate({pidProfile=1,isArmed=true}); assert(not rt:canSave())
ui.key(); ui.wake(); ui.save(); rt:performSave(); equal(#ui.dialogs,0); equal(#ui.writes,0)
rt:onSessionUpdate({pidProfile=1,isArmed=false})
rt.activeDialog={}; assert(not rt:canSave()); rt.activeDialog=nil
rt:setBusy(true); assert(not rt:canSave()); rt:setBusy(false)
ui.key(); assert(rt.pendingSaveConfirm); equal(#ui.dialogs,0)
rt:setBusy(true); ui.wake(); equal(rt.pendingSaveConfirm,false); equal(#ui.dialogs,0)
rt:setBusy(false); ui.key(); ui.wake(); equal(#ui.dialogs,1)
-- Recheck at confirmation acceptance, not just when opening the prompt.
rt:onSessionUpdate({pidProfile=1,isArmed=true}); accept(ui.dialogs[1]); equal(#ui.writes,0)
rt:onSessionUpdate({pidProfile=1,isArmed=false}); ui.save(); accept(ui.dialogs[2]); ui.wake()
equal(#ui.writes,2); equal(ui.writes[2].kind,'eeprom'); assert(not rt.dirty)
ui.cleanup(); assert(not rt:canSave())

-- Partial multi-source failure cannot enable fields or save defaults.
rt,ui=fixture(true)
rt:loadInitial(); finishRead(ui,{a=1}); failRead(ui)
equal(#ui.dialogs,0) -- modal must be deferred to the page wakeup
ui.wake(); assert(not rt.loaded and not rt.busy and not ui.field.enabled)
equal(#ui.dialogs,1); assert(rt.loadErrorDialog)
ui.save(); rt:performSave(); ui.key(); ui.wake(); equal(#ui.writes,0)
ui.reload(); equal(#ui.reads,0) -- acknowledge error before manual retry
accept(ui.dialogs[1]); equal(ui.focus(),'reload'); equal(rt.loadErrorDialog,nil)
ui.reload(); finishRead(ui,{a=2}); finishRead(ui,{b=3}); ui.wake()
assert(rt.loaded and ui.field.enabled and not rt.dirty)
rt:markDirty(); assert(rt:canSave())
-- A failed reload after previous success must not restore loaded=true.
ui.reload(); finishRead(ui,{a=4}); failRead(ui); ui.wake()
assert(not rt.loaded and not ui.field.enabled and not rt:canSave())
assert(rt.dirty) -- existing edits do not make incomplete data savable
local dialog=ui.dialogs[#ui.dialogs]
ui.cleanup(); assert(dialog.closed)
-- Retained error callbacks cannot focus or revive a disposed runtime.
accept(dialog); assert(rt.disposed and not rt:canSave())

-- Failed first source, missing progress API, and clean retry.
rt,ui=fixture(false)
ui.noProgress(); rt:loadInitial(); failRead(ui); ui.wake()
assert(not rt.loaded and not ui.field.enabled); accept(ui.dialogs[1])
ui.reload(); finishRead(ui); ui.wake(); rt:markDirty()
ui.noConfirm(); ui.save(); ui.wake(); equal(#ui.writes,2)
ui.cleanup()

-- Prefetched pages still work, and armed gating remains explicit opt-in.
rt,ui=fixture(false,nil,{value=7})
rt:loadInitial(); ui.wake(); equal(#ui.reads,0); rt:markDirty()
rt:onSessionUpdate({pidProfile=1,isArmed=true}); assert(rt:canSave())
ui.cleanup()
print('Page runtime checks passed: save gates, keyboard/confirmation, partial/reload failures, retry, cleanup and prefetched pages')
