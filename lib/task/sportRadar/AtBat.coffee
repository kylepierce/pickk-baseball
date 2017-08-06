_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Task = require "../Task"
SportRadarGame = require "../../model/sportRadar/SportRadarGame"
Team = require "../../model/Team"
Player = require "../../model/Player"
GameParser = require "./helper/GameParser"
Multipliers = require "./Multiplier"
Pitches = require "./Pitches"
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
    @multipliers = new Multipliers dependencies
    @pitches = new Pitches dependencies

  execute: (parms) ->
    # Requirements: gameId, player, inning, inningDivision, newPlayer, game, eventCount, pitchNumber, pitch
    newBatter = @newBatter parms

    if newBatter
      Promise.bind @
        .then -> @closeInactiveAtBats parms
        .then -> @createAtBat parms
        # .then -> @pitches.createPitch parms, true

  newBatter: (parms) ->
    if (parms.diff.length > 0) && (parms.diff.indexOf "currentBatter") > -1
      if parms.oldPlayer isnt parms.newPlayer
        console.log "---------------------------\n", ">>> New Player"
        console.log "New", parms.newPlayer.firstName, parms.newPlayer.lastName
        console.log "Next", parms.nextPlayer.firstName, parms.nextPlayer.lastName
        return parms.nextPlayer

  closeInactiveAtBats: (parms) ->
    # Requirements: update, gameId, inning, inningDivision, currentEventCount, atBatId, updatedEventId
    Promise.bind @
      .then -> @getLastAtBat parms.gameId
      .then (atBatId) -> @Questions.find {commercial: false, gameId: parms.gameId, active: true, atBatQuestion: true, atBatId: {$ne: atBatId}}
      .map (question) ->
        Promise.bind @
          .then -> @closeAtBat parms, question
          .then (result) ->
            @awardUsers question, result['option']
            @pitches.closeInactivePitches parms, result['title']

  closeAtBat: (parms, question) ->
    map = _.invert _.mapObject question['options'], (option) -> option['title']

    Promise.bind @
      .then -> @gameParser.findSpecificEvent parms, question['eventCount'] - 1
      .then (event) -> @eventTitle event['pbpDetailId']
      .then (eventTitle) ->
        outcome =
          option: map[eventTitle]
          title: eventTitle
        return outcome

  awardUsers: (question, outcomeOption) ->
    Promise.bind @
      .then -> @Questions.update {_id: question._id}, $set: {active: false, outcome: outcomeOption, lastUpdated: new Date()}
      .then -> @Answers.update {questionId: question._id, answered: {$ne: outcomeOption}}, {$set: {outcome: "lose"}}, {multi: true} # Losers
      .then -> @Answers.find {questionId: question._id, answered: outcomeOption} # Find the winners
      .map (answer) ->
        reward = Math.floor answer['wager'] * answer['multiplier']
        Promise.bind @
          .then -> @Answers.update {_id: answer._id}, {$set: {outcome: "win"}} #
          .then -> @GamePlayed.update {userId: answer['userId'], gameId: question.gameId}, {$inc: {coins: reward}}
          .tap -> @logger.verbose "Awarding correct users!"
          .then ->
            notificationId = chance.guid()
            @Notifications.insert
              _id: notificationId
              dateCreated: new Date()
              question: question._id
              userId: answer['userId']
              gameId: question.gameId
              type: "coins"
              value: reward
              read: false
              notificationId: notificationId
              message: "Nice Pickk! You got #{reward} Coins!"
              sharable: false
              shareMessage: ""

  createAtBat: (parms) ->
    player = parms.nextPlayer
    # if parms['newPlayer'] then parms.atBatId = parms.gameId + "-" + parms.inning + "-" + parms.eventCount + "-" + parms['newPlayer']['playerId']
    question = "End of #{player['firstName']} #{player['lastName']}'s at bat."

    Promise.bind @
      .then -> @multipliers.getGenericMultipliersForPlay() #bases, playerId
      .then (multipliers) ->
        options =
          option1: {title: "Out", number: 1, multiplier: multipliers['out'] }
          option2: {title: "Walk", number: 2, multiplier: multipliers['walk'] }
          option3: {title: "Single", number: 3, multiplier: multipliers['single'] }
          option4: {title: "Double", number: 4, multiplier: multipliers['double'] }
          option5: {title: "Triple", number: 5, multiplier: multipliers['triple'] }
          option6: {title: "Home Run", number: 6, multiplier: multipliers['homerun'] }

        Promise.bind @
          .then -> @insertAtBat(parms)
          .then (atBat) -> @Questions.count {commercial: false, game_id: parms.gameId, player_id: player['playerId'], atBatQuestion: true, atBatId: atBat._id}
          .then (found) ->
            if not found
              Promise.bind @
              .then -> @getLastAtBat parms.gameId
              .then (atBatId) ->
                @Questions.insert
                  _id: @Questions.db.ObjectId().toString()
                  dateCreated: new Date()
                  gameId: parms.gameId
                  atBatId: atBatId
                  playerId: player['playerId']
                  atBatQuestion: true
                  inning: parms.inning
                  eventCount: parms.eventCount
                  period: 0
                  type: "atBat"
                  active: true
                  # background: "background: linear-gradient(rgba(34, 44, 49, .0), rgba(34, 44, 49, .5)), url('https://image.shutterstock.com/z/stock-photo-queens-ny-april-the-game-between-the-new-york-mets-and-florida-marlins-about-to-begin-at-57937108.jpg'); height: 75px; background-position-x: 46%; background-position-y: 0%; "
                  commercial: false
                  que: question
                  options: options
                  usersAnswered: []
              .tap (result) ->
                questionId = result.upserted?[0]?._id
                @logger.verbose "Create atBat question (#{question})"

  eventTitle: (eventStatusId) ->
    results = [
      title: "Single"
      outcomes: [1, 2, 3, 4, 5, 6, 122]
    ,
      title: "Double"
      outcomes: [7, 8, 9, 10, 11, 123]
    ,
      title: "Triple"
      outcomes: [12, 13, 124]
    ,
      title: "Home Run"
      outcomes: [15, 16, 17, 18]
    ,
      title: "Out"
      outcomes: [15, 16, 17, 18, 26, 27, 28, 30, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 56, 57, 59, 65, 67, 68, 69, 70, 71, 72, 73, 77, 78, 82, 85, 91, 92, 93, 94, 126, 127, 136]
    ,
      title: "Walk"
      outcomes: [61, 106]
    ]
    # Loop over each object in array
    result = ""
    for item in results
      if (item['outcomes'].indexOf eventStatusId) > -1
        result = item['title']
    return result

  insertAtBat: (parms) ->
    Promise.bind @
      .then -> @AtBats.insert
        _id:  @AtBats.db.ObjectId().toString()
        dateCreated: new Date()
        gameId: parms.gameId
        playerId: parms.nextPlayer.playerId
        inning: parms.inning
        eventCount: parms.eventCount

  getLastAtBat: (gameId) ->
    Promise.bind @
      .then -> @AtBats.find({gameId: gameId}).sort({dateCreated: -1}).limit(1)
      .then (result) -> return result[0]._id
