_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Task = require "../Task"
SportRadarGame = require "../../model/sportRadar/SportRadarGame"

module.exports = class extends Task
  constructor: (dependencies) ->
    super

    Match.check dependencies, Match.ObjectIncluding
      sportRadar: Match.Any
      mongodb: Match.Any

  execute: (gameId) ->
    Match.check gameId, Number

    api = @dependencies.sportRadar
    @logger = @dependencies.logger

    Promise.bind @
    .then -> api.getPlayByPlay gameId
    .then (result) -> result.apiResults[0].league.season.eventType[0].events
    # .tap (result) -> @logger.verbose result
    # .tap (result) -> @logger.verbose "Batter: #{result[0]['eventStatus']['currentBatter']['playerId']} - #{result[0]['eventStatus']['balls']} - #{result[0]['eventStatus']['strikes']}"
    .map @upsertGame

  upsertGame: (game) ->
    sportRadarGame = new SportRadarGame game
    collection = @dependencies.mongodb.collection("games")
    collection.update sportRadarGame.getSelector(), {$set: sportRadarGame}, {upsert: true}
    return sportRadarGame
