fantasydataApi = require 'fantasydata-api'
Match = require "mtr-match"
Promise = require "bluebird"
_ = require "underscore"
dateFormat = require 'dateformat'

formatFantasyDate = (date) -> dateFormat(date, "yyyy-mmm-dd").toUpperCase()
  

module.exports = (options) ->
  Match.check options, Object

  api = fantasydataApi(options)

  # add some sugar
  api.mlb.playByPlayDelta = _.wrap api.mlb.playByPlayDelta, (func, date, minutes, callback) ->
    dateString = formatFantasyDate date
    func dateString, minutes, callback
  api.mlb.boxScores = _.wrap api.mlb.boxScores, (func, date, callback) ->
    dateString = formatFantasyDate date
    func dateString, callback

  Promise.promisifyAll api.mlb
  
  api
