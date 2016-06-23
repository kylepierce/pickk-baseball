_ = require "underscore"
Match = require "mtr-match"
createMongoDB = require "./mongodb"
createLogger = require "./logger"
createFantasy = require "./fantasy"
createSportRadar = require "./sportRadar"

module.exports = (settings, handle) ->
  Match.check settings, Object
  Match.check handle, String
  settings.mongodb.url = settings.mongodb.url.replace("%database%", handle)
  dependencies = {settings: settings}
  _.extend dependencies,
    mongodb: createMongoDB dependencies.settings.mongodb
    logger: createLogger dependencies.settings.logger
    fantasy: createFantasy dependencies.settings.fantasy
    sportRadar: createSportRadar dependencies.settings.sportRadar
  dependencies
