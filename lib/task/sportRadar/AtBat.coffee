_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Task = require "../Task"
SportRadarGame = require "../../model/sportRadar/SportRadarGame"
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

  execute: (parms) ->
    #gameId, inning, inningDivision, oldPlayer, newPlayer, game, eventCount, pitchNumber, pitch
    # Requirements: gameId, player, inning, inningDivision, newPlayer, game, eventCount, pitchNumber, pitch
    if parms.oldPlayer['playerId'] isnt parms.newPlayer['playerId']
      console.log "---------------------------\n",  "New Player!!!!!", "---------------------------\n"

      Promise.bind @
        # .then -> @closeInactiveAtBats parms
        # .then -> @createAtBat parms

  closeInactiveAtBats: (parms) ->
    # Requirements: update, gameId, inning, inningDivision, currentEventCount, atBatId, updatedEventId

    Promise.bind @
    .then -> @Questions.find {commercial: false, gameId: parms.gameId, active: true, atBatQuestion: true, atBatId: {$ne: parms.atBatId}} #Find open at bats
    .map (question) ->
      # compareEventCount = eventCount - question['eventCount']
      # event = @gameParser.findSpecificEvent update, question['eventCount'] - 1
      outcome = @eventTitle event['pbpDetailId']
      map = _.invert _.mapObject question['options'], (option) -> option['title']
      outcomeOption = map[outcome] #could fail here

      Promise.bind @
        .then -> @resolveCommercialQuestions parms, false, event
        .then -> @Questions.update {_id: question._id}, $set: {active: false, outcome: outcomeOption, lastUpdated: new Date()}
        .then -> @Answers.update {questionId: question._id, answered: {$ne: outcomeOption}}, {$set: {outcome: "lose"}}, {multi: true}
        .then -> @Answers.find {questionId: question._id, answered: outcomeOption}
        .map (answer) ->
          reward = Math.floor answer['wager'] * answer['multiplier']
          Promise.bind @
          .then -> @Answers.update {_id: answer._id}, {$set: {outcome: "win"}}
          .then -> @GamePlayed.update {userId: answer['userId'], gameId: parms.gameId}, {$inc: {coins: reward}}
          .tap -> @logger.verbose "Awarding correct users!"
          .then ->
            notificationId = chance.guid()
            @Notifications.insert
              _id: notificationId
              userId: answer['userId']
              gameId: parms.gameId
              type: "coins"
              value: reward
              read: false
              notificationId: notificationId
              dateCreated: new Date()
              message: "Nice Pickk! You got #{reward} Coins!"
              sharable: false
              shareMessage: ""

  createAtBat: (parms) ->
    player = parms.newPlayer
    question = "End of #{player['firstName']} #{player['lastName']}'s at bat."

    Promise.bind @
    .then -> @getGenericMultipliersForPlay() #bases, playerId
    .then (multipliers) ->
      options =
        option1: {title: "Out", number: 1, multiplier: multipliers['out'] }
        option2: {title: "Walk", number: 2, multiplier: multipliers['walk'] }
        option3: {title: "Single", number: 3, multiplier: multipliers['single'] }
        option4: {title: "Double", number: 4, multiplier: multipliers['double'] }
        option5: {title: "Triple", number: 5, multiplier: multipliers['triple'] }
        option6: {title: "Home Run", number: 6, multiplier: multipliers['homerun'] }

      Promise.bind @
      .then -> @Questions.count {commercial: false, game_id: parms.gameId, player_id: player['playerId'], atBatQuestion: true, atBatId: parms.atBatId}
      .then (found) ->
        if not found
          Promise.bind @
          .then ->
            @Questions.insert
              _id: @Questions.db.ObjectId().toString()
              dateCreated: new Date()
              gameId: parms.gameId
              playerId: player['playerId']
              game_id: parms.gameId
              player_id: player['playerId']
              atBatQuestion: true
              inning: parms.inning
              eventCount: parms.eventCount
              period: 0
              type: "atBat"
              active: true
              background: "background: linear-gradient(rgba(34, 44, 49, .0), rgba(34, 44, 49, .5)), url('https://image.shutterstock.com/z/stock-photo-queens-ny-april-the-game-between-the-new-york-mets-and-florida-marlins-about-to-begin-at-57937108.jpg'); height: 75px; background-position-x: 46%; background-position-y: 0%; "
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
