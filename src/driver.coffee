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
console.log "Using HOUMIO_BECKHOFF_THROTTLE=#{houmioBeckhoffThrottle}"

bridgeDaliSocket = new net.Socket()
bridgeDmxSocket = new net.Socket()
bridgeAcSocket = new net.Socket()
bridgeMotorSocket = new net.Socket()

adsClient = null

# ADS Messages

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

# Dali functions

writeMessageToDaliMessage = (writeMessage) ->
  v = if writeMessage.data.bri is 255 then 254 else writeMessage.data.bri
  {
    symname: ".HMI_LightControls[#{writeMessage.data.protocolAddress}]",
    bytelength: 2,
    propname: 'value',
    value: new Buffer [0x01, v]
  }

# DMX functions

dmxAddressAndValueToAdsHandle = (address, value) ->
  {
    symname: ".HMI_DMXPROCDATA[#{address}]"
    bytelength: ads.BYTE
    propname: 'value'
    value: value
  }

writeMessageToDmxMessages = (writeMessage) ->
  if writeMessage.data.type is 'color'
    rgbw = cc.hsvToRgbw writeMessage.data.hue, writeMessage.data.saturation, writeMessage.data.bri
    address = parseInt writeMessage.data.protocolAddress
    _.map rgbw, (channelValue, i) -> dmxAddressAndValueToAdsHandle(address + i, channelValue)
  else
    [ dmxAddressAndValueToAdsHandle(writeMessage.data.protocolAddress, writeMessage.data.bri)]

# Helpers

splitProtocolAddressOnComma = (writeMessage) ->
  _.map writeMessage.data.protocolAddress.split(","), (singleAddress) ->
    writeMessageForSingleAddress = _.cloneDeep writeMessage
    writeMessageForSingleAddress.data.protocolAddress = singleAddress
    writeMessageForSingleAddress

# Bridge sockets

isWriteMessage = (message) -> message.command is "write"

toLines = (socket) ->
  Bacon.fromBinder (sink) ->
    carrier.carry socket, sink
    socket.on "close", -> sink new Bacon.End()
    socket.on "error", (err) -> sink new Bacon.Error(err)
    ( -> )

openBridgeWriteMessageStream = (socket, protocolName) -> (cb) ->
  socket.connect houmioBridge.split(":")[1], houmioBridge.split(":")[0], ->
    lineStream = toLines socket
    messageStream = lineStream.map JSON.parse
    messageStream.onEnd -> exit "Bridge stream ended, protocol: #{protocolName}"
    messageStream.onError (err) -> exit "Error from bridge stream, protocol: #{protocolName}, error: #{err}"
    writeMessageStream = messageStream.filter isWriteMessage
    cb null, writeMessageStream

openStreams = [ openBridgeWriteMessageStream(bridgeDaliSocket, "DALI")
              , openBridgeWriteMessageStream(bridgeDmxSocket, "DMX")
              , openBridgeWriteMessageStream(bridgeAcSocket, "AC") ]

async.series openStreams, (err, [daliWriteMessages, dmxWriteMessages, acWriteMessages]) ->
  if err then exit err
  daliWriteMessages
    .flatMap (m) -> Bacon.fromArray splitProtocolAddressOnComma m
    .map writeMessageToDaliMessage
    .onValue doWriteToAds
  dmxWriteMessages
    .flatMap (m) -> Bacon.fromArray splitProtocolAddressOnComma m
    .flatMap (m) -> Bacon.fromArray writeMessageToDmxMessages m
    .onValue doWriteToAds
  acWriteMessages.onValue sendAcMessageToAds
  bridgeDaliSocket.write (JSON.stringify { command: "driverReady", protocol: "beckhoff/dali"}) + "\n"
  bridgeDmxSocket.write (JSON.stringify { command: "driverReady", protocol: "beckhoff/dmx"}) + "\n"
  bridgeAcSocket.write (JSON.stringify { command: "driverReady", protocol: "beckhoff/ac"}) + "\n"

# ADS client

doWriteToAds = (handle) ->
  adsClient.write handle, (err) ->
    if err then exit "Error while writing to ADS: #{err}"

timeServicesHandle =
  symname: ".SYSTEMSERVICE_TIMESERVICES"
  bytelength: ads.UDINT
  propname: 'value'

# Beckhoff AMS connection
# amsNetIdTarget: The NetId of the target machine
# amsNetIdSource:
#   The NetId of the source machine.
#   You can choose anything in the form of x.x.x.x.x.x,
#   but on the target machine this must be added as a route.
# amsPortTarget: Other possible ports: 27906, 300

beckhoffOptions =
  host: houmioBeckhoffIp
  amsNetIdTarget: houmioAmsTargetId
  amsNetIdSource: houmioAmsSourceId
  amsPortTarget: 801

readTimeServices = ->
  errorTimeout = setTimeout ( -> exit "Error: ADS server timeout" ), 10000
  adsClient.read timeServicesHandle, (err, handle) ->
    if err
      exit "Error from ADS heartbeat: #{err}"
    else
      clearTimeout errorTimeout
      console.log "Received heartbeat from ADS server"

if process.env.NODE_ENV is "dev"
  console.log "NODE_ENV=dev"
  adsClient =
    write: (handle, cb) ->
      console.log handle
      cb null
else
  adsClient = ads.connect beckhoffOptions, ->
    console.log "Connected to Beckhoff ADS server, setting up heartbeat check"
    adsClient.read timeServicesHandle, (err, handle) ->
      if err
        exit "Error: no connection to ADS server"
      else
        setInterval readTimeServices, 5000
  adsClient.on 'error', exit
