_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Strategy = require "../Strategy"
ImportGames = require "../../task/sportRadar/ImportGames"
ImportGameDetails = require "../../task/sportRadar/ImportGameDetails"

module.exports = class extends Strategy
  constructor: (dependencies) ->
    super

    @importGames = new ImportGames dependencies
    @importGameDetails = new ImportGameDetails dependencies

    @logger = dependencies.logger

  execute: ->
    @importGames.observe "upserted", (game) =>
      if game.status is "inprogress"
        @importGameDetails.execute game.id
      
    @importGames.execute()
