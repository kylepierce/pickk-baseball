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
UpdateTeam = require "../../task/sportRadar/UpdateTeam"
promiseRetry = require 'promise-retry'

module.exports = class extends Strategy
  constructor: (dependencies) ->
    super

    @importGames = new ImportGames dependencies
    @getActiveGames = new GetActiveGames dependencies
    @importGameDetails = new ImportGameDetails dependencies
    @closeInactiveAtBats = new CloseInactiveAtBats dependencies
    @closeInactiveQuestions = new CloseInactiveQuestions dependencies
    @updateTeam = new UpdateTeam dependencies
    @processGame = new ProcessGame dependencies

    @logger = dependencies.logger

  execute: ->
    # do not allow it to crash!
    promiseRetry {retries: 1000, factor: 1}, (retry) =>
      Promise.bind @
      # .then -> console.log "I am important"
      .then -> @importGames.execute()
      .then -> @closeInactiveQuestions.execute()
      .then -> @closeInactiveAtBats.execute()
      .then -> @getActiveGames.execute()
      .map (game) ->
        Promise.bind @
        .then -> @importGameDetails.execute game['eventId']
        .then -> @updateTeam.execute game['home_team']
        .then -> @updateTeam.execute game['away_team']
        .then -> @processGame.execute game
      , {concurrency: 1}
      .catch (error) =>
        @logger.error error.message, _.extend({stack: error.stack}, error.details)
        retry error
