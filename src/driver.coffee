Bacon = require 'baconjs'
http = require('http')
net = require('net')
carrier = require('carrier')
ads = require('ads')
async = require('async')
_ = require('lodash')
cc = require('./colourConversion')
Rx = require('rx')

exit = (msg) ->
  console.log msg
  process.exit 1

houmioBridge = process.env.HOUMIO_BRIDGE || "localhost:3001"
houmioBeckhoffIp = process.env.HOUMIO_BECKHOFF_IP
houmioAmsSourceId = process.env.HOUMIO_BECKHOFF_AMS_SOURCE_ID
houmioAmsTargetId = process.env.HOUMIO_BECKHOFF_AMS_TARGET_ID
houmioBeckhoffDaliThrottle = process.env.HOUMIO_BECKHOFF_DALI_THROTTLE || 15

unless houmioBeckhoffIp then exit "HOUMIO_BECKHOFF_IP is not set"
unless houmioAmsSourceId then exit "HOUMIO_BECKHOFF_AMS_SOURCE_ID is not set"
unless houmioAmsTargetId then exit "HOUMIO_BECKHOFF_AMS_TARGET_ID is not set"
console.log "Using HOUMIO_BECKHOFF_IP=#{houmioBeckhoffIp}"
console.log "Using HOUMIO_BECKHOFF_AMS_SOURCE_ID=#{houmioAmsSourceId}"
console.log "Using HOUMIO_BECKHOFF_AMS_TARGET_ID=#{houmioAmsTargetId}"
console.log "Using HOUMIO_BECKHOFF_DALI_THROTTLE=#{houmioBeckhoffDaliThrottle}"

bridgeDaliSocket = new net.Socket()
bridgeDmxSocket = new net.Socket()
bridgeAcSocket = new net.Socket()
bridgeMotorSocket = new net.Socket()
bridgeWinchSocket = new net.Socket()

adsClient = null

# ADS write

doWriteToAds = (handle) ->
  adsClient.write handle, (err) ->
    if err then exit "Error while writing to ADS: #{err}"
# ADS messages

## DALI functions

symname = (universeAddress, protocolAddress) ->
  if /^g/.test protocolAddress
    groupAddress = protocolAddress.substring 1
    ".HMI_DaliGroupControls#{universeAddress}[#{groupAddress}]"
  else
    ".HMI_DaliControls#{universeAddress}[#{protocolAddress}]"

writeMessageToDaliMessage = (writeMessage) ->
  v = if writeMessage.data.bri is 255 then 254 else writeMessage.data.bri
  {
    symname: symname(writeMessage.data.universeAddress, writeMessage.data.protocolAddress),
    bytelength: 2,
    propname: 'value',
    value: new Buffer [0x01, v]
  }

## Motor control and AC functions

writeMessageToAcMessage = (writeMessage) ->
  if writeMessage.data.type is 'binary'
    return writeMessageToRelayMessage(writeMessage)
  if writeMessage.data.type is 'dimmable'
    return writeMessageToDimmerMessage(writeMessage)

writeMessageToMotorMessages = (writeMessage) ->
  [ addresses, delay ] = writeMessage.data.protocolAddress.split("/")
  cloneMessage = _.cloneDeep writeMessage
  cloneMessage.data.protocolAddress = addresses
  [ onRelayWriteMessage, offRelayWriteMessage ] = splitProtocolAddressOnComma cloneMessage
  delayedRelayWriteMessage = if writeMessage.data.on then _.cloneDeep onRelayWriteMessage else _.cloneDeep offRelayWriteMessage
  offRelayWriteMessage.data.on = !writeMessage.data.on
  delayedRelayWriteMessage.data.on = false
  if writeMessage.data.on
    onMessage = onRelayWriteMessage
    offMessage = offRelayWriteMessage
  else
    onMessage = offRelayWriteMessage
    offMessage = onRelayWriteMessage
  {
    on: onMessage,
    off: offMessage,
    delayed: delayedRelayWriteMessage,
    delay: parseInt delay
  }

writeMessageToRelayMessage = (writeMessage) ->
  if writeMessage.data.on is true then onOff = 1 else onOff = 0
  {
    symname: ".HMI_RelayControls[#{writeMessage.data.protocolAddress}]",
    bytelength: ads.BYTE,
    value: onOff
  }

writeMessageToDimmerMessage = (writeMessage) ->
  brightness = Math.floor (writeMessage.data.bri / 0xFF) * 0x7FFF
  {
    symname: ".HMI_DimmerControls[#{writeMessage.data.protocolAddress}]"
    bytelength: ads.INT,
    value: brightness
  }

## DMX functions
dmxAddressAndValueToAdsHandle = (universeAddress, address, value) ->
  {
    symname: ".HMI_DmxProcData#{universeAddress}[#{address}]"
    bytelength: ads.BYTE
    propname: 'value'
    value: value
  }

writeMessageToDmxMessages = (writeMessage) ->
  if writeMessage.data.type is 'color'
    rgbw = cc.hsvToRgbw writeMessage.data.hue, writeMessage.data.saturation, writeMessage.data.bri
    address = parseInt writeMessage.data.protocolAddress
    _.map rgbw, (channelValue, i) -> dmxAddressAndValueToAdsHandle(writeMessage.data.universeAddress, address + i, channelValue)
  else
    [ dmxAddressAndValueToAdsHandle( writeMessage.data.universeAddress, writeMessage.data.protocolAddress, writeMessage.data.bri)]
# Winch functions

putWinchParamsToWriteMessage = (posRough, posFine, speed, maxPosTop, maxPosBottom, findUp, findDown) ->
  writeMessage.data.speed = 0
  writeMessage.data.maxPos = 0
  writeMessage.data.minPos = 0
  writeMessage.data.position = 0


calculateWinchPosition = (writeMessage) ->
  top = 255 - writeMessage.data.maxPos
  bottom = writeMessage.data.minPos
  length = top - bottom
  Math.floor(length/255*(255-writeMessage.data.bri)) + bottom

parseWinchParamsFromWriteMessage = (writeMessage) ->
  writeMessage.data.universeAddress = writeMessage.data.protocolAddress.split('/')[0]
  writeMessage.data.speed = parseInt writeMessage.data.protocolAddress.split('/')[2]
  writeMessage.data.maxPos = parseInt writeMessage.data.protocolAddress.split('/')[3]
  writeMessage.data.minPos = parseInt writeMessage.data.protocolAddress.split('/')[4]
  writeMessage.data.position = calculateWinchPosition writeMessage
  writeMessage.data.protocolAddress = writeMessage.data.protocolAddress.split('/')[1]
  writeMessage.data.findDown = 0
  writeMessage.data.finePosition = 0
  writeMessage.data.findUp = 0
  if writeMessage.data.type is 'binary'
    writeMessage.data.position = 0
    writeMessage.data.speed = 0
    writeMessage.data.maxPos = 0
    writeMessage.data.minPos = 0
    if writeMessage.data.on then writeMessage.data.findUp = 100 else writeMessage.data.findUp = 0
  writeMessage

writeMessageToWinchMessages = (writeMessage) ->
  positionAddress = parseInt(writeMessage.data.protocolAddress) + 1
  dmxAddressAndValueToDmxUniverse = _.partial dmxAddressAndValueToAdsHandle, writeMessage.data.universeAddress
  _.map [writeMessage.data.speed,
    writeMessage.data.finePosition,
    writeMessage.data.maxPos,
    writeMessage.data.minPos,
    writeMessage.data.position,
    writeMessage.data.findUp,
    writeMessage.data.findDown], (data, i) ->
      dmxAddressAndValueToDmxUniverse positionAddress + i, data

splitProtocolAddressOnComma = (writeMessage) ->
  _.map writeMessage.data.protocolAddress.split(","), (singleAddress) ->
    writeMessageForSingleAddress = _.cloneDeep writeMessage
    writeMessageForSingleAddress.data.protocolAddress = singleAddress
    writeMessageForSingleAddress

splitUniverseAddressOnDash = (writeMessage) ->
  writeMessage.data.universeAddress = writeMessage.data.protocolAddress.split('/')[0]
  writeMessage.data.protocolAddress = writeMessage.data.protocolAddress.split('/')[1]
  writeMessage

# Bridge sockets

isWriteMessage = (message) -> message.command is "write"

toLines = (socket) ->
  Bacon.fromBinder (sink) ->
    carrier.carry socket, sink
    socket.on "close", -> sink new Bacon.End()
    socket.on "error", (err) -> sink new Bacon.Error(err)
    ( -> )

openBridgeWriteMotorMessageStream = (socket, protocolName) -> (cb) ->
  socket.connect houmioBridge.split(":")[1], houmioBridge.split(":")[0], ->
    lineStream = Rx.Observable.create (observer) ->
      carrier.carry socket, (data) ->
        observer.onNext data
    messageStream = lineStream.map JSON.parse
    writeMessageStream = messageStream.filter isWriteMessage
    cb null, writeMessageStream


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
              , openBridgeWriteMessageStream(bridgeAcSocket, "AC")
              , openBridgeWriteMotorMessageStream(bridgeMotorSocket, "MOTOR")
              , openBridgeWriteMessageStream(bridgeWinchSocket, "WINCH")]

async.series openStreams, (err, [daliWriteMessages, dmxWriteMessages, acWriteMessages, motorWriteMessages, winchWriteMessages]) ->
  if err then exit err
  daliWriteMessages
    .flatMap (m) -> Bacon.fromArray splitProtocolAddressOnComma (splitUniverseAddressOnDash m)
    .map writeMessageToDaliMessage
    .bufferingThrottle houmioBeckhoffDaliThrottle
    .onValue doWriteToAds
  dmxWriteMessages
    .flatMap (m) -> Bacon.fromArray splitProtocolAddressOnComma (splitUniverseAddressOnDash m)
    .flatMap (m) -> Bacon.fromArray writeMessageToDmxMessages m
    .onValue doWriteToAds
  acWriteMessages
    .flatMap (m) -> Bacon.fromArray splitProtocolAddressOnComma m
    .map writeMessageToAcMessage
    .onValue doWriteToAds
  winchWriteMessages
    .flatMap (m) -> Bacon.fromArray splitProtocolAddressOnComma (parseWinchParamsFromWriteMessage m)
    .flatMap (m) -> Bacon.fromArray writeMessageToWinchMessages m
    .onValue doWriteToAds
  motorWriteMessages
    .groupBy (m) -> m.data._id
    .subscribe (s) ->
      s.flatMapLatest (m) ->
        motorMessages = writeMessageToMotorMessages m
        onObservable = Rx.Observable.return(motorMessages.on)
          .delay 200
        delayedObservable = Rx.Observable.return(motorMessages.delayed)
          .delay motorMessages.delay
        Rx.Observable.return(motorMessages.off).concat(onObservable, delayedObservable)
      .map writeMessageToAcMessage
      .subscribe (m) ->
        doWriteToAds m

  bridgeDaliSocket.write (JSON.stringify { command: "driverReady", protocol: "beckhoff/dali"}) + "\n"
  bridgeDmxSocket.write (JSON.stringify { command: "driverReady", protocol: "beckhoff/dmx"}) + "\n"
  bridgeAcSocket.write (JSON.stringify { command: "driverReady", protocol: "beckhoff/ac"}) + "\n"
  bridgeMotorSocket.write (JSON.stringify { command: "driverReady", protocol: "beckhoff/motor"}) + "\n"
  bridgeWinchSocket.write (JSON.stringify { command: "driverReady", protocol: "beckhoff/winch"}) + "\n"

# ADS client

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

timeServicesHandle =
  symname: ".SYSTEMSERVICE_TIMESERVICES"
  bytelength: ads.UDINT
  propname: 'value'

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
