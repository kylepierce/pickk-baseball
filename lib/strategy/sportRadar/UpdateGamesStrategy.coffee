_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Strategy = require "../Strategy"
ImportGames = require "../../task/sportRadar/ImportGames"
GetActiveGames = require "../../task/GetActiveGames"
ImportGameDetails = require "../../task/sportRadar/ImportGameDetails"
CloseInactiveAtBats = require "../../task/CloseInactiveAtBats"
CloseInactiveQuestions = require "../../task/CloseInactiveQuestions"
ProcessGame = require "../../task/sportRadar/ProcessGame"
promiseRetry = require 'promise-retry'

module.exports = class extends Strategy
  constructor: (dependencies) ->
    super

    @importGames = new ImportGames dependencies
    @getActiveGames = new GetActiveGames dependencies
    @importGameDetails = new ImportGameDetails dependencies
    @closeInactiveAtBats = new CloseInactiveAtBats dependencies
    @closeInactiveQuestions = new CloseInactiveQuestions dependencies
    @processGame = new ProcessGame dependencies

    @logger = dependencies.logger

  execute: ->
    # promiseRetry {retries: 1000, factor: 1}, (retry) =>
      Promise.bind @
      .then -> @importGames.execute()
      .then -> @getActiveGames.execute()
      .map (game) ->
        Promise.bind @
        .then -> @importGameDetails.execute game['eventId']
        .then (result) -> @processGame.execute game, result[0]
      , {concurrency: 1}
      .catch (error) =>
        @logger.verbose error.message, _.extend({stack: error.stack}, error.details)
        # retry error
