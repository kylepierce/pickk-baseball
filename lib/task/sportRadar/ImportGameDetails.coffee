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
    .then (result) -> result.apiResults[0].league.season.eventType[0].events[0]
    .then @upsertGame

  upsertGame: (game) ->
    sportRadarGame = new SportRadarGame game
    @logger.verbose "First import #{sportRadarGame.old}"
    collection = @dependencies.mongodb.collection("games")
    collection.update sportRadarGame.getSelector(), {$set: sportRadarGame}, {upsert: true}
