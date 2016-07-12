Match = require "mtr-match"
request = require "request-promise"
dateFormat = require 'dateformat'
_ = require "underscore"
Promise = require "bluebird"
promiseRetry = require 'promise-retry'

HOST = "http://api.sportradar.us/"
MLB = "mlb-t5/"

formatPattern = Match.Where (format) -> format in ["json", "xml"]

module.exports = class
  constructor: (options) ->
    Match.check options, Match.ObjectIncluding
      apiKey: String

    @host = HOST
    @mlb = MLB
    @key = options.apiKey

  _mlbRequest: (path, options = {}) ->
    @_request @mlb + path, options

  _request: (path, options = {}) ->
    Match.check path, String
    
    uri = @host + path

    _.defaults options,
      uri: uri
      json: true

    options.qs ?= {}
    _.defaults options.qs,
      api_key: @key


    promiseRetry (retry, number) =>
      Promise.bind @
      .then -> request options
      .catch (error) ->
        # TODO @logger
        console.log error.message #, _.extend({stack: error.stack}, error.details)
        retry(error)

  getScheduledGames: (date, format = "json") ->
    Match.check date, Date
    Match.check format, formatPattern

    formattedDate = dateFormat(date, "yyyy/mm/dd")
    path = "games/#{formattedDate}/schedule.#{format}"
    @_mlbRequest path

  # game -> innings -> halfs -> events -> {at_bat} -> events
  getPlayByPlay: (gameId, format = "json") ->
    Match.check gameId, String
    Match.check format, formatPattern

    path = "games/#{gameId}/pbp.#{format}"
    @_mlbRequest path
