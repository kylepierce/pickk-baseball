fantasydataApi = require 'fantasydata-api'
Match = require "mtr-match"
Promise = require "bluebird"

module.exports = (options) ->
  Match.check options, Object

  api = fantasydataApi(options)
  Promise.promisifyAll api.mlb

  api
