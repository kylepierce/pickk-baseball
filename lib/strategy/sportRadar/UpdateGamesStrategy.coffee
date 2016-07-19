_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Strategy = require "../Strategy"
ImportGames = require "../../task/sportRadar/ImportGames"
GetActiveGames = require "../../task/GetActiveGames"
ImportGameDetails = require "../../task/sportRadar/ImportGameDetails"
ProcessGame = require "../../task/sportRadar/ProcessGame"

module.exports = class extends Strategy
  constructor: (dependencies) ->
    super

    @importGames = new ImportGames dependencies
    @getActiveGames = new GetActiveGames dependencies
    @importGameDetails = new ImportGameDetails dependencies
    @processGame = new ProcessGame dependencies
    
    @logger = dependencies.logger

  execute: ->
    Promise.bind @
    .then -> @importGames.execute()
    .then -> @getActiveGames.execute()
    .map (game) ->
      @importGameDetails.execute game
      .then -> @processGame.execute game
