Bacon = require 'baconjs'
http = require('http')
net = require('net')
carrier = require('carrier')
ads = require('ads')
#c = require('c-struct')
#iecstruct = require('iecstruct')
#uint8 = require('uint8')
async = require('async')



houmioBridge = process.env.HOUMIO_BRIDGE || "localhost:3001"
bridgeDaliSocket = new net.Socket()
bridgeDmxSocket = new net.Socket()


houmioBeckhoffIp = process.env.HORSELIGHTS_BECKHOFF_IP || "192.168.1.102"


console.log "Using HORSELIGHTS_BECKHOFF_IP=#{houmioBeckhoffIp}"

adsClient = null

#Beckhoff AMS connection

beckhoffOptions = {
  #The IP or hostname of the target machine
  host: houmioBeckhoffIp,
  #The NetId of the target machine
  amsNetIdTarget: "5.21.69.109.1.1",
  #amsNetIdTarget: "5.21.69.109.3.4",
  #The NetId of the source machine.
  #You can choose anything in the form of x.x.x.x.x.x,
  #but on the target machine this must be added as a route.
  amsNetIdSource: "192.168.1.103.1.1",
  amsPortTarget: 801
  #amsPortTarget: 27906
}



adsClient = ads.connect beckhoffOptions, ->
  console.log "Connected to Beckhoff ADS server"

  this.getSymbols (err, result) ->
    console.log "ERROR: ", err
    console.log "symbols", result

###
  dataHandle = {
    symname: '.HMI_DmxProcData[4]',
    bytelength: ads.BYTE,
    propname: 'value',
    value: 0xFF
  }

  this.write dataHandle, (err) ->
    console.log "WRITE ERR", err
###

adsClient.on 'error', (err) ->
  console.log "ERROR", err






isWriteMessage = (message) -> message.command is "write"



sendDaliMessageToAds = (message) ->
  #msg = JSON.parse message
  console.log "MESSAGE DALI", message

sendDmxMessageToAds = (message) ->
  console.log "MESSAGE DMX", message
  dataHandle = {
    symname: '.HMI_DmxProcData[4]',
    bytelength: ads.BYTE,
    propname: 'value',
    value: message.data.bri
  }
  if adsClient
    adsClient.write dataHandle, (err) ->
      console.log "WRITE ERR", err

bridgeMessagesToAds = (bridgeStream, sendMessageToAds) ->
  console.log "TAALLA TAAS!!!"
  bridgeStream
    .filter isWriteMessage
    .bufferingThrottle 10
    .onValue (message) ->
      sendMessageToAds message
      console.log "<-- Data To AMS:", message




toLines = (socket) ->
  Bacon.fromBinder (sink) ->
    carrier.carry socket, sink
    socket.on "close", -> sink new Bacon.End()
    socket.on "error", (err) -> sink new Bacon.Error(err)
    ( -> )


openBridgeMessageStream = (socket) -> (cb) ->
  socket.connect houmioBridge.split(":")[1], houmioBridge.split(":")[0], ->
    lineStream = toLines socket
    messageStream = lineStream.map JSON.parse
    cb null, messageStream

openStreams = [ openBridgeMessageStream(bridgeDaliSocket), openBridgeMessageStream(bridgeDmxSocket) ]

async.series openStreams, (err, [bridgeDaliStream, bridgeDmxStream]) ->
  if err then exit err
  bridgeDaliStream.onEnd -> exit "Bridge Dali stream ended"
  bridgeDmxStream.onEnd -> exit "Bridge DMX stream ended"
  bridgeDaliStream.onError (err) -> exit "Error from bridge Dali stream:", err
  bridgeDmxStream.onError (err) -> exit "Error from bridge DMX stream:", err
  bridgeMessagesToAds bridgeDaliStream, sendDaliMessageToAds
  bridgeMessagesToAds bridgeDmxStream, sendDmxMessageToAds
  console.log "TAALLA"
  #bridgeMessagesToSerial bridgeStream, enoceanSerial
  #enoceanMessagesToSocket enoceanStream, bridgeSocket
  bridgeDaliSocket.write (JSON.stringify { command: "driverReady", protocol: "beckhoff/dali"}) + "\n"
  bridgeDmxSocket.write (JSON.stringify { command: "driverReady", protocol: "beckhoff"}) + "\n"















###

onSocketMessage = (s) ->
  msg = JSON.parse s
  console.log s
  if msg.data.type == "binary"
    console.log "MESSAGE: ", msg
    data = {
      symname: msg.data.devaddr,
      bytelength: ads.BIT,
      value: msg.data.on
    }
    adsClient.write data, (err) ->
      console.log "Written data"
  else
    console.log "MESSAGE: ", msg
    if msg.data.bri is 255 then msg.data.bri = 254
    #powerLevel: c.type.u16
    #powerLevel = 0x0001 | msg.data.bri << 8
    #console.log "BRI ", powerLevel.toString 16, ads.INT

    powerLevel = new iecstruct.ARRAY iecstruct.BYTE, 2
    powerLevel[0] = 0x01
    powerLevel[1] = 0x01

    dataHandle = {
      symname: msg.data.devaddr,
      bytelength: 2,
      propname: 'value',
      value: new Buffer [0x01, msg.data.bri]
    }
    #console.log "DATA_HANDLE", dataHandle
    try
      adsClient.write dataHandle, (err) ->
        console.log err
    catch error
      console.log error


###




#Beckhoff AMS connection

beckhoffOptions = {
  #The IP or hostname of the target machine
  host: houmioBeckhoffIp,
  #The NetId of the target machine
  amsNetIdTarget: "5.21.69.109.1.1",
  #amsNetIdTarget: "5.21.69.109.3.4",
  #The NetId of the source machine.
  #You can choose anything in the form of x.x.x.x.x.x,
  #but on the target machine this must be added as a route.
  amsNetIdSource: "192.168.1.103.1.1",
  amsPortTarget: 801
  #amsPortTarget: 27906
}



adsClient = ads.connect beckhoffOptions, ->
  console.log "Connected to Beckhoff ADS server"

  this.getSymbols (err, result) ->
    console.log "ERROR: ", err
    console.log "symbols", result

###
  dataHandle = {
    symname: '.HMI_DmxProcData[4]',
    bytelength: ads.BYTE,
    propname: 'value',
    value: 0xFF
  }

  this.write dataHandle, (err) ->
    console.log "WRITE ERR", err
###

adsClient.on 'error', (err) ->
  console.log "ERROR", err











#OLD STUFFF
###
notificationHandle = {
  symname: 'TERM 2 (EL6851).DMX CHANNEL 1-64',
  bytelength: ads.INT,
  transmissionMode: ads.NOTIFY.ONCHANGE
}
###
###
writeStartHandle = {
  symname: 'FastTask.bStart',
  bytelength: ads.BOOL,
  value: 1

}
###

###
TYPE DALI_HMI_CTRL:
    (
        bStart:=false,
        powerLevel:=0
    );
END_TYPE

DALI_HMI_CTRL test
###

###
daliData = new c.Schema {
  bStart: c.type.uint8,
  pwrLevel: c.type.uint8
}
###

###
tempVal = new iecstruct.ENUM {
  bstart: true,
  power: 0,
}
console.log "TEMP VAL ", tempVal
console.log "VALVAL ", tenp
###

#array = new iecstruct.ARRAY iecstruct.BYTE, 2



#console.log "ARRAY ", array
###
testHandle = {
  symname: '.HMI_LightControls[0]',
  bytelength: 2,
  propname: 'array'
}
###

###
testHandle = {
  symname: 'BOX 3 (BK1250).TERM 5 (KL2641).CHANNEL 1.OUTPUT',
  bytelength: ads.BI000000000,
  value: 0
}
###





