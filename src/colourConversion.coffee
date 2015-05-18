_ = require('lodash')

hsvToRgbw = (hue, saturation, value) ->
  #calculate white and
  w = ((255 - saturation) * value) / 255
  #Normalize values
  w /= 255
  hue /= 255
  saturation /= 255
  value /= 255
  #Calculate amounts of different colours
  i = Math.floor(hue * 6)
  f = hue * 6 - i
  p = value * (1 - saturation)
  q = value * (1 - f * saturation)
  t = value * (1 - (1 - f) * saturation)
  #Saturation 0 -> only white is used
  value *= saturation
  p *= saturation
  q *= saturation
  t *= saturation
  #Create RGBW
  switch i % 6
    when 0 then rgbw = [value, t, p, w]
    when 1 then rgbw = [q, value, p, w]
    when 2 then rgbw = [p, value, t, w]
    when 3 then rgbw = [p, q, value, w]
    when 4 then rgbw = [t, p, value, w]
    when 5 then rgbw = [value, p, q, w]
  #RGBW values back from normalized
  _.map rgbw, (val) -> Math.floor(val*255)

hslToRgbw = (hue, saturation, lightness) ->
  if saturation is 0 then return [0, 0, 0, lightness]
  hueToRgb = (p, q, t) ->
    if t < 0 then t += 1
    if t > 1 then t -= 1
    if t < 1/6 then return p + (q - p) * 6 * t
    if t < 1/2 then return q
    if t < 2/3 then return p + (q - p) * (2/3 - t) * 6
    return p
  lightness /= 255
  saturation /= 255
  hue /= 255
  q = if lightness < 0.5 then lightness * (1 + saturation) else lightness + saturation - lightness * saturation
  p = 2 * lightness - q
  r = hueToRgb p, q, hue + 1/3
  g = hueToRgb p, q, hue
  b = hueToRgb p, q, hue - 1/3
  [Math.round(r * 255), Math.round(g * 255), Math.round(b * 255), Math.round((lightness - saturation) * 255)]

exports.hslToRgbw = hslToRgbw
exports.hsvToRgbw = hsvToRgbw
