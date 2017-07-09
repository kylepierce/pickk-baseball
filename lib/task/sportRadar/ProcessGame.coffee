_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Task = require "../Task"
SportRadarGame = require "../../model/sportRadar/SportRadarGame"
EndOfGame = require "./EndOfGame"
Inning = require "./Inning"
AtBat = require "./AtBat"
Pitches = require "./Pitches"
Team = require "../../model/Team"
Player = require "../../model/Player"
GameParser = require "./helper/GameParser"
moment = require "moment"
promiseRetry = require 'promise-retry'
chance = new (require 'chance')

module.exports = class extends Task
  constructor: (dependencies) ->
    super

    Match.check dependencies, Match.ObjectIncluding
      mongodb: Match.Any

    @logger = @dependencies.logger
    @SportRadarGames = dependencies.mongodb.collection("games")
    @Teams = dependencies.mongodb.collection("teams")
    @Players = dependencies.mongodb.collection("players")
    @Questions = dependencies.mongodb.collection("questions")
    @AtBats = dependencies.mongodb.collection("atBat")
    @Answers = dependencies.mongodb.collection("answers")
    @GamePlayed = dependencies.mongodb.collection("gamePlayed")
    @Users = dependencies.mongodb.collection("users")
    @Notifications = dependencies.mongodb.collection("notifications")
    @gameParser = new GameParser dependencies
    @endOfGame = new EndOfGame dependencies
    @inning = new Inning dependencies
    @Commercial = new Commercial dependencies
    @AtBat = new AtBat dependencies
    @Pitches = new Pitches dependencies

  execute: (old, update) ->
    Promise.bind @
      .then -> @checkGameStatus old, update
      .then -> @handleGame old, update
      .return true
      .catch (error) =>
        @logger.error error.message, _.extend({stack: error.stack}, error.details)

  handleGame: (old, update) ->
    result = @gameParser.getPlay update

    if result
      Promise.bind @
        .then -> @detectChange old, result

  checkGameStatus: (old, update) ->
    # If there is no old. Got to update that.

    # If there is an old, but no old property.

    # If there is an update but no old.

    # If there is no update. Close the game.

    @logger.verbose old
    @logger.verbose update

    # if !update['old']
    #   console.log "No old or update????????"
    #   update = update[0]
    #
    # if !update['old']['inning']
    #   console.log "No inning?? : ", update['old']
    #

    # if !pitch
    #   console.log "No Pitch"
    #
    # if pitchCount.length is 0
    #   event = @gameParser.findSpecificEvent update, questionEventCount - 1
    #   pitchCount = event['pitchDetails']

    # if !old['old']
    #   @SportRadarGames.update {_id: update.eventId}, {$set: update}
    # else if !update['old'] || !old['old']
    #   console.log "[Global] No old or update????????"
    #   return
    # else if update['eventStatus']['eventStatusId'] isnt 2
    #   console.log "Something is wrong. Shutting this whole thing down..."
    #   return
    #
    # if update['eventStatus']['eventStatusId'] is 4
    #   #This should be a method!
    #   @logger.verbose "This game is completed"
    #   update['status'] = "completed"
    #   update['close_processed'] = true
    #   update['live'] = false
    #   @SportRadarGames.update {_id: old['_id']}, {$set: update}
    #   return
    # else if update['eventStatus']['eventStatusId'] isnt 2
    #   @logger.verbose "Game is over"

  detectChange: (old, result) ->
    ignoreList =  [35, 42, 89, 96, 97, 98]

    parms =
      gameId: old['id']
      gameName: old['name']
      commerical: result['commerical'] #Not sure about this
      inning: result['eventStatus']['inning']
      inningDivision: result['eventStatus']['inningDivision']
      lastCount: update['old']['lastCount']
      atBatId: old['_id'] + "-" + result['eventStatus']['inning'] + "-" + result['old']["eventCount"] + "-" + oldPlayer
      oldStuff: old['eventStatus']
      oldInning: if old['old'] then old['old']['inningDivision'] else "Top"
      oldPlayer: if old['old'] then old["old"]['eventStatus']['currentBatter'] else 0
      oldEventId: if old['old'] then old['old']['eventId'] else 0
      oldPitch: if old['old'] then old["old"]['lastCount'].length else 0
      newStuff: result['eventStatus']
      newInning: result['old']['inningDivision']
      newPlayer: result['eventStatus']['currentBatter']
      newEventId: result['old']['eventId']
      newPitch: result["old"]['lastCount'].length
      onIgnoreList: ignoreList.indexOf result['old']['eventId']
      # team:
      pitch: _.last result["old"]['lastCount']
      pitchNumber: result['old']['lastCount'].length #Make this zero if its a new batter or inning.

    diff = []
    list = ["strikes", "balls", "outs", "currentBatter", "eventStatusId", "innings", "inningDivision", "runnersOnBase"]

    _.map list, (key) ->
      compare = _.isEqual parms.oldStuff[key], parms.newStuff[key]
      if not compare
        diff.push key

    parms.diff = diff
    parms.pitchDiff = parms.newPitch - parms.oldPitch

    Promise.bind @
      .then -> @SportRadarGames.find {eventId: old['eventId'] }
      .then (result) -> @checkCommericalStatus result[0], old, result, parms.newPlayer
      .then -> @inning.execute parms
      .then -> @atBat.execute checkPlayer parms
      .then -> @pitches.execute parms
      .then -> @endOfGame.execute gameId

  checkCommericalStatus: (game, old, update, newPlayer) ->
    # Add something to kick out of commerical if a play is active.
    if not game.commercialStartedAt
      return

    now = moment()
    timeout = now.diff(game.commercialStartedAt, 'minute')
    commercialTime = @dependencies.settings['common']['commercialTime']
    if timeout >= commercialTime
      Promise.bind @
        .then -> @SportRadarGames.update {_id: game._id}, {$set: {commercial: false}, $unset: {commercialStartedAt: 1}}
        .then -> @inning.closeActiveCommercialQuestions game.id, game.name
        # .tap -> @logger.verbose "Creating first player questions."
        # .then -> @createPitch old, update[0], newPlayer, 0
        # .tap -> @logger.verbose "Created 0-0"
        # .then -> @createAtBat old, update[0], newPlayer
        # gameId, atBatId, player, inning, eventCount
        # .tap -> @logger.verbose "Created New At Bat After Commercial"
