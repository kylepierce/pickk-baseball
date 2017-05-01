_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Task = require "../Task"
SportRadarGame = require "../../model/sportRadar/SportRadarGame"
dateFormat = require 'dateformat'

module.exports = class extends Task
  constructor: (dependencies) ->
    super

    Match.check dependencies, Match.ObjectIncluding
      sportRadar: Match.Any
      mongodb: Match.Any

    @api = @dependencies.sportRadar
    @logger = @dependencies.logger
    @Games = @dependencies.mongodb.collection("games")

    @registerEvents ['upserted']

  execute: ->
    Promise.bind @
    # .tap -> @logger.verbose "Fetching information about games for #{days}"
    .then -> @api.getScheduledGames 7
    .then (result) -> result.apiResults[0].league.season.eventType[0].events
    .map @upsertGame
    # .tap (results) -> @logger.warn "#{results.length} games have been upserted"
    .return true

  upsertGame: (data) ->
    game = new SportRadarGame data
    Promise.bind @
    .then -> @Games.findOne game.getSelector()
    .then (original) ->
      game['close_processed'] = false if @isClosing original, game

      @Games.update game.getSelector(), {$set: game}, {upsert: true}
      .then => @emit "upserted", game

  isClosing: (original, game) -> original and not original['completed'] and game['completed']
