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
    # do not allow it to crash!
    promiseRetry {retries: 1000, factor: 1}, (retry) =>
      Promise.bind @
      # .then -> @importGames.execute()
      # .then -> @closeInactiveQuestions.execute() # This just closes the questions. It does not award the users.
      # .then -> @closeInactiveAtBats.execute() # This just closes the questions. It does not award the users.
      .then -> @getActiveGames.execute()
      .map (game) ->
        Promise.bind @
        # Old data is game
        .then -> @importGameDetails.execute game['eventId']
        .then (result) -> @processGame.execute game, result
      # , {concurrency: 1} #❗️ This is probably causing the issue. Its updating the file after starting the process. Game is the new data.
      .catch (error) =>
        @logger.error error.message, _.extend({stack: error.stack}, error.details)
        retry error
