Bacon = require 'baconjs'
http = require('http')
net = require('net')
carrier = require('carrier')
ads = require('ads')
async = require('async')
_ = require('lodash')
cc = require('./colourConversion')

exit = (msg) ->
  console.log msg
  process.exit 1

houmioBridge = process.env.HOUMIO_BRIDGE || "localhost:3001"
houmioBeckhoffIp = process.env.HOUMIO_BECKHOFF_IP
houmioAmsSourceId = process.env.HOUMIO_BECKHOFF_AMS_SOURCE_ID
houmioAmsTargetId = process.env.HOUMIO_BECKHOFF_AMS_TARGET_ID
houmioBeckhoffThrottle = process.env.HOUMIO_BECKHOFF_THROTTLE || 15

unless houmioBeckhoffIp then exit "HOUMIO_BECKHOFF_IP is not set"
unless houmioAmsSourceId then exit "HOUMIO_BECKHOFF_AMS_SOURCE_ID is not set"
unless houmioAmsTargetId then exit "HOUMIO_BECKHOFF_AMS_TARGET_ID is not set"
console.log "Using HOUMIO_BECKHOFF_IP=#{houmioBeckhoffIp}"
console.log "Using HOUMIO_BECKHOFF_AMS_SOURCE_ID=#{houmioAmsSourceId}"
console.log "Using HOUMIO_BECKHOFF_AMS_TARGET_ID=#{houmioAmsTargetId}"

bridgeDaliSocket = new net.Socket()
bridgeDmxSocket = new net.Socket()
bridgeAcSocket = new net.Socket()
bridgeMotorSocket = new net.Socket()

adsClient = null

#ADS Messages

#RELAY AND DIMMER FUNCTIONS
relayToAds = (address, onBool, relayToAdsCb) ->
  if onBool is true then onOff = 1 else onOff = 0
  dataHandle = {
    symname: ".HMI_RelayControls[#{address}]",
    bytelength: ads.BYTE,
    value: onOff
  }
  if adsClient
    adsClient.write dataHandle, relayToAdsCb

dimmerToAds = (address, bri, dimmerToAdsCb) ->
  dataHandle = {
    symname: ".HMI_DimmerControls[#{address}]"
    bytelength: ads.INT,
    value: bri
  }
  if adsClient
    adsClient.write dataHandle, dimmerToAdsCb

sendAcMessageToAds = (message) ->
  #console.log "AC Message", message
  if message.data.type is 'binary'
    relayToAds message.data.protocolAddress, message.data.on, (err) ->
      if err then console.log "AC Relay Write Error", err
  if message.data.type is 'dimmable'
    dimmerToAds message.data.protocolAddress, message.data.bri, (err) ->
      if err then console.log "Dimmer write error"

#MOTOR CONTROL
sendMotorMessageToAds = (message) ->
  addrTime = message.data.protocolAddress.split("/")
  addresses = _.object ['start', 'stop'], addrTime[0].split(",")
  time = parseInt(addrTime[1])
  console.log "ADDRESSES", addresses



#DALI WRITE
daliToAds = (address, value, daliToAdsCb) ->
  dataHandle = {
    symname: ".HMI_LightControls[#{address}]",
    bytelength: 2,
    propname: 'value',
    value: new Buffer [0x01, value]
  }
  if adsClient
    adsClient.write dataHandle, daliToAdsCb

sendDaliMessageToAds = (message) ->
  if message.data.bri is 255 then message.data.bri = 254
  addresses = message.data.protocolAddress.split(",")
  async.eachSeries addresses, (addr, cb) ->
      daliToAds addr, message.data.bri, cb
    , (err) ->
      if err then console.log "Dali Write error", err

#DMX WRITE
dmxToAds = (address, value, dmxToAdsCb) ->
  dataHandle = {
    symname: ".HMI_DMXPROCDATA[#{address}]",
    bytelength: ads.BYTE,
    propname: 'value',
    value: value
  }
  if adsClient
    adsClient.write dataHandle, dmxToAdsCb

selectAndSendToDmx = (address, message, cb) ->
  if message.data.type is 'color'
    rgbw = cc.hsvToRgbw message.data.hue, message.data.saturation, message.data.bri
    index = address
    async.eachSeries rgbw, (val, cb) ->
      dmxToAds index, val, cb
      index++
    , cb
  else
    dmxToAds address, message.data.bri, cb

sendDmxMessageToAds = (message) ->
  addresses = message.data.protocolAddress.split(",")
  async.eachSeries addresses, (addr, cb) ->
    selectAndSendToDmx addr, message, cb
  , (err) ->
    if err then console.log "Dmx Write error", err

#Socket IO

isWriteMessage = (message) -> message.command is "write"

bridgeMessagesToAds = (bridgeStream, sendMessageToAds) ->
  bridgeStream
    .filter isWriteMessage
    .bufferingThrottle houmioBeckhoffThrottle
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

openStreams = [ openBridgeMessageStream(bridgeDaliSocket), openBridgeMessageStream(bridgeDmxSocket), openBridgeMessageStream(bridgeAcSocket), openBridgeMessageStream(bridgeMotorSocket)]

async.series openStreams, (err, [bridgeDaliStream, bridgeDmxStream, bridgeAcStream, bridgeMotorStream]) ->
  if err then exit err
  bridgeDaliStream.onEnd -> exit "Bridge Dali stream ended"
  bridgeDmxStream.onEnd -> exit "Bridge DMX stream ended"
  bridgeAcStream.onEnd -> exit "Bridge AC stream ended"
  bridgeMotorStream.onEnd -> exit "Bridge Motor stream ended"
  bridgeDaliStream.onError (err) -> exit "Error from bridge Dali stream:", err
  bridgeDmxStream.onError (err) -> exit "Error from bridge DMX stream:", err
  bridgeAcStream.onError (err) -> exit "Error from bridge AC stream:", err
  bridgeMotorStream.onError (err) -> exit "Error from bridge Motor stream:", err
  bridgeMessagesToAds bridgeDaliStream, sendDaliMessageToAds
  bridgeMessagesToAds bridgeDmxStream, sendDmxMessageToAds
  bridgeMessagesToAds bridgeAcStream, sendAcMessageToAds
  bridgeMessagesToAds bridgeMotorStream, sendMotorMessageToAds
  bridgeDaliSocket.write (JSON.stringify { command: "driverReady", protocol: "beckhoff/dali"}) + "\n"
  bridgeDmxSocket.write (JSON.stringify { command: "driverReady", protocol: "beckhoff/dmx"}) + "\n"
  bridgeAcSocket.write (JSON.stringify { command: "driverReady", protocol: "beckhoff/ac"}) + "\n"
  bridgeMotorSocket.write (JSON.stringify { command: "driverReady", protocol: "beckhoff/motor"}) + "\n"

readCheckDataFromAds = ->
  dataHandle = {
    symname: ".SYSTEMSERVICE_TIMESERVICES",
    bytelength: ads.UDINT,
    propname: 'value'
  }
  errorTimeout = setTimeout exit, 10000
  adsClient.read dataHandle, (err, handle) ->
    unless err
      clearTimeout errorTimeout
      console.log "Heartbeat"

#Beckhoff AMS connection

beckhoffOptions = {
  #The IP or hostname of the target machine
  host: houmioBeckhoffIp,
  #The NetId of the target machine
  amsNetIdTarget: houmioAmsTargetId,
  #amsNetIdTarget: "5.21.69.109.3.4",
  #The NetId of the source machine.
  #You can choose anything in the form of x.x.x.x.x.x,
  #but on the target machine this must be added as a route.
  amsNetIdSource: houmioAmsSourceId,
  amsPortTarget: 801
  #amsPortTarget: 27906
  #amsPortTarget: 300
}

adsClient = ads.connect beckhoffOptions, ->
  console.log "Connected to Beckhoff ADS server"
  this.getSymbols (err, result) ->
  #  console.log "ERROR: ", err
  #  console.log "symbols", result
  dataHandle = {
    symname: ".SYSTEMSERVICE_TIMESERVICES",
    bytelength: ads.UDINT,
    propname: 'value'
  }
  adsClient.read dataHandle, (err, handle) ->
    unless err
      setInterval readCheckDataFromAds, 5000
    else
      exit


adsClient.on 'error', exit
