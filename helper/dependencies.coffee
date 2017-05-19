_ = require "underscore"
Match = require "mtr-match"
createMongoDB = require "./mongodb"
createLogger = require "./logger"
createSportRadar = require "./sportRadar"

module.exports = (settings, handle) ->
  Match.check settings, Object
  Match.check handle, String
  console.log handle
  settings.mongodb.url = settings.mongodb.url.replace("%database%", handle)
  console.log settings.mongodb.url 
  dependencies = {settings: settings}
  _.extend dependencies,
    mongodb: createMongoDB dependencies.settings.mongodb
    logger: createLogger dependencies.settings.logger
    sportRadar: createSportRadar dependencies.settings.sportRadar
  dependencies
