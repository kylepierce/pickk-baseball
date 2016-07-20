_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Strategy = require "../Strategy"
ImportGames = require "../../task/sportRadar/ImportGames"
GetActiveGames = require "../../task/GetActiveGames"
ImportGameDetails = require "../../task/sportRadar/ImportGameDetails"
ProcessGame = require "../../task/sportRadar/ProcessGame"
promiseRetry = require 'promise-retry'

module.exports = class extends Strategy
  constructor: (dependencies) ->
    super

    @importGames = new ImportGames dependencies
    @getActiveGames = new GetActiveGames dependencies
    @importGameDetails = new ImportGameDetails dependencies
    @processGame = new ProcessGame dependencies
    
    @logger = dependencies.logger

  execute: ->
    # do not allow it to crash!
    promiseRetry {retries: 1000}, (retry) =>
      Promise.bind @
      .then -> @importGames.execute()
      .then -> @getActiveGames.execute()
      .then (games) -> _.sortBy games, (game) -> game['scheduled']
      .then (games) -> games.slice(0, 1)
      .map (game) ->
        Promise.bind @
        .then -> @importGameDetails.execute game['id']
        .then -> @processGame.execute game
      .catch (error) =>
        @logger.error error.message, _.extend({stack: error.stack}, error.details)
        retry error
