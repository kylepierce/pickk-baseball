_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Task = require "../Task"
SportRadarGame = require "../../model/sportRadar/SportRadarGame"
dateFormat = require 'dateformat'
moment = require "moment"

module.exports = class extends Task
  constructor: (dependencies) ->
    super

    Match.check dependencies, Match.ObjectIncluding
      sportRadar: Match.Any
      mongodb: Match.Any

    @api = @dependencies.sportRadar
    @logger = @dependencies.logger

    @registerEvents ['upserted']

  execute: (date = new Date()) ->
    # cast to EDT timezone
    EDT_OFFSET = 60 * 4
    date = moment(date).subtract(EDT_OFFSET + moment(date).utcOffset(), 'minutes').toDate()

    Promise.bind @
    .tap -> @logger.verbose "Fetching information about games for #{dateFormat(date, "yyyy/mm/dd")}"
    .then -> @api.getScheduledGames(date)
    .tap (result) -> @logger.verbose "#{result.league.games.length} results have been fetched"
    .then (result) -> result.league.games
    .map @upsertGame
    .tap (results) -> @logger.verbose "#{results.length} games have been upserted"
    .return true

  upsertGame: (game) ->
    sportRadarGame = new SportRadarGame game
    collection = @dependencies.mongodb.collection("games")
    collection.update sportRadarGame.getSelector(), {$set: sportRadarGame}, {upsert: true}
    .then => @emit "upserted", sportRadarGame
