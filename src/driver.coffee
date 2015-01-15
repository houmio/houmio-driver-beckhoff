Bacon = require 'baconjs'
http = require('http')
net = require('net')
carrier = require('carrier')
ads = require('ads')
async = require('async')



houmioBridge = process.env.HOUMIO_BRIDGE || "localhost:3001"
bridgeDaliSocket = new net.Socket()
bridgeDmxSocket = new net.Socket()


houmioBeckhoffIp = process.env.HORSELIGHTS_BECKHOFF_IP || "192.168.1.104"


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

adsClient.on 'error', (err) ->
  console.log "ADS ERROR", err
  process.exit 1


#Socket IO

isWriteMessage = (message) -> message.command is "write"

sendDaliMessageToAds = (message) ->
  if message.data.bri is 255 then message.data.bri = 254

  dataHandle = {
    symname: ".HMI_LightControls[#{message.data.protocolAddress}]",
    bytelength: 2,
    propname: 'value',
    value: new Buffer [0x01, message.data.bri]
  }

  try
    adsClient.write dataHandle, (err) ->
      console.log err
  catch error
    console.log error




sendDmxMessageToAds = (message) ->
  dataHandle = {
    symname: ".HMI_DmxProcData[#{message.data.protocolAddress}]",
    bytelength: ads.BYTE,
    propname: 'value',
    value: message.data.bri
  }
  console.log dataHandle.symname
  if adsClient
    adsClient.write dataHandle, (err) ->
      console.log "WRITE ERR", err

bridgeMessagesToAds = (bridgeStream, sendMessageToAds) ->
  bridgeStream
    .filter isWriteMessage
    .bufferingThrottle 10
    .onValue (message) ->
      sendMessageToAds message
      console.log "<-- Data To ADS:", message

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
  if err
    console.log "Error:", err
    process.exit 1
  bridgeDaliStream.onEnd -> exit "Bridge Dali stream ended"
  bridgeDmxStream.onEnd -> exit "Bridge DMX stream ended"
  bridgeDaliStream.onError (err) -> exit "Error from bridge Dali stream:", err
  bridgeDmxStream.onError (err) -> exit "Error from bridge DMX stream:", err
  bridgeMessagesToAds bridgeDaliStream, sendDaliMessageToAds
  bridgeMessagesToAds bridgeDmxStream, sendDmxMessageToAds
  #bridgeMessagesToSerial bridgeStream, enoceanSerial
  #enoceanMessagesToSocket enoceanStream, bridgeSocket
  bridgeDaliSocket.write (JSON.stringify { command: "driverReady", protocol: "beckhoff/dali"}) + "\n"
  bridgeDmxSocket.write (JSON.stringify { command: "driverReady", protocol: "beckhoff/dmx"}) + "\n"


























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





