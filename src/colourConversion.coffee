hsvToRgbw = (hue, saturation, value) ->
  hue /= 255
  saturation /= 255
  value /= 255
  i = Math.floor(hue * 6)
  f = hue * 6 - i
  p = value * (1 - saturation)
  q = value * (1 - f * saturation)
  t = value * (1 - (1 - f) * saturation)
  switch i % 6
    when 0 then rgb = [value, t, p]
    when 1 then rgb = [q, value, p]
    when 2 then rgb = [p, value, t]
    when 3 then rgb = [p, q, value]
    when 4 then rgb = [t, p, value]
    when 5 then rgb = [value, p, q]
  _.map rgb, (val) -> Math.floor(val*255)

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
  [Math.round(r * 255), Math.round(g * 255), Math.round(b * 255), Math.round(lightness / saturation)]

exports.hslToRgbw = hslToRgbw
exports.hsvToRgbw = hsvToRgbw
