fantasydataApi = require 'fantasydata-api'
Match = require "mtr-match"
Promise = require "bluebird"
_ = require "underscore"
dateFormat = require 'dateformat'

module.exports = (options) ->
  Match.check options, Object

  api = fantasydataApi(options)

  # add some sugar
  api.mlb.playByPlayDelta = _.wrap api.mlb.playByPlayDelta, (func, date, minutes, callback) ->
    dateString = dateFormat(date, "yyyy-mmm-dd").toUpperCase()
    func dateString, minutes, callback

  Promise.promisifyAll api.mlb
  
  api
