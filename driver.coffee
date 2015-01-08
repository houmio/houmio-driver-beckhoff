WebSocket = require('ws')
winston = require('winston')
http = require('http')
net = require('net')
carrier = require('carrier')
ads = require('ads')
c = require('c-struct')
iecstruct = require('iecstruct')
uint8 = require('uint8')


#mb = require('modbus').create()
#modbus = require('modbus-tcp')

winston.remove(winston.transports.Console)
winston.add(winston.transports.Console, { timestamp: ( -> new Date() ) })
console.log = winston.info

houmioServer = process.env.HORSELIGHTS_SERVER || "ws://localhost:3000"
houmioSitekey = process.env.HORSELIGHTS_SITEKEY || "devsite"
houmioBeckhoffIp = process.env.HORSELIGHTS_BECKHOFF_IP || "192.168.1.101"

console.log "Using HORSELIGHTS_SERVER=#{houmioServer}"
console.log "Using HORSELIGHTS_SITEKEY=#{houmioSitekey}"
console.log "Using HORSELIGHTS_BECKHOFF_IP=#{houmioBeckhoffIp}"

exit = (msg) ->
  console.log msg
  process.exit 1

socket = null
pingId = null
adsClient = null

onSocketOpen = ->
  console.log "Connected to #{houmioServer}"
  pingId = setInterval ( -> socket.ping(null, {}, false) ), 3000
  publish = JSON.stringify { command: "publish", data: { sitekey: houmioSitekey, vendor: "beckhoff" } }
  socket.send(publish)
  console.log "Sent message:", publish

onSocketClose = ->
  clearInterval pingId
  exit "Disconnected from #{houmioServer}"


###
testHandle = {
  symname: 'BOX 3 (BK1250).TERM 5 (KL2641).CHANNEL 1.OUTPUT',
  bytelength: ads.BI000000000,
  value: 0
}
###



writeToDali = (msg) ->








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


transmitToServer = (data) ->
	socket.send JSON.stringify { command: "generaldata", data: data }

socketPong = () ->
	socket.pong()

beckhoffOptions = {
  #The IP or hostname of the target machine
  host: "192.168.1.102",
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


notificationHandle = {
  symname: 'TERM 2 (EL6851).DMX CHANNEL 1-64',
  bytelength: ads.INT,
  transmissionMode: ads.NOTIFY.ONCHANGE
}


writeStartHandle = {
  symname: 'FastTask.bStart',
  bytelength: ads.BOOL,
  value: 1

}
###
TYPE DALI_HMI_CTRL:
    (
        bStart:=false,
        powerLevel:=0
    );
END_TYPE

DALI_HMI_CTRL test
###


daliData = new c.Schema {
  bStart: c.type.uint8,
  pwrLevel: c.type.uint8
}


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

testHandle = {
  symname: '.HMI_LightControls[0]',
  bytelength: 2,
  propname: 'array'
}



adsClient = ads.connect beckhoffOptions, ->
  console.log "Connected to Beckhoff ADS server"


  #this.notify notificationHandle




  socket = new WebSocket(houmioServer)
  socket.on 'open', onSocketOpen
  socket.on 'close', onSocketClose
  socket.on 'error', exit
  socket.on 'ping', socketPong
  socket.on 'message', onSocketMessage


  dataHandle = {
    symname: '.HMI_DmxProcData[4]',
    bytelength: ads.BYTE,
    propname: 'value',
    value: 0xFF
  }

  this.write dataHandle, (err) ->
    console.log "WRITE ERR", err



adsClient.on 'error', (err) ->
  console.log "ERROR", err

adsClient.on 'notification', (handle) ->
  console.log "Beckhoff notification", handle.value


process.on 'exit', () ->
  console.log 'exit'

process.on 'SIGINT', ->
  client.end () ->
    prcess.exit












