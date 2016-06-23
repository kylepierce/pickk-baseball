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

  execute: (date = new Date()) ->
    api = @dependencies.sportRadar

    Promise.bind @
    .then -> api.getScheduledGames(date)
    .then (result) -> result.league.games
    .map @upsertGame

  upsertGame: (game) ->
    sportRadarGame = new SportRadarGame game
    collection = @dependencies.mongodb.collection("SportRadarGames")
    collection.update sportRadarGame.getSelector(), {$set: sportRadarGame}, {upsert: true}

