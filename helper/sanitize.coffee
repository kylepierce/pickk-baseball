_ = require "underscore"

sanitize = (object, sanitizedProperties = ["credentials", "token", "accessToken", "refreshToken"]) ->
  object = _.clone(object)
  if _.isObject(object)
    for key, value of object
      if key in sanitizedProperties
        delete object[key]
      else
        object[key] = sanitize(value, sanitizedProperties)
  else if _.isArray(object)
    for element, i in object
      object[i] = sanitize(element)
  object

module.exports = sanitize
