_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Task = require "../Task"
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
    @Questions = dependencies.mongodb.collection("questions")
    @AtBats = dependencies.mongodb.collection("atBat")
    @Answers = dependencies.mongodb.collection("answers")
    @GamePlayed = dependencies.mongodb.collection("gamePlayed")
    @Notifications = dependencies.mongodb.collection("notifications")
    @gameParser = new GameParser dependencies
    @multipliers = new Multipliers dependencies
    @pitches = new Pitches dependencies

  execute: (gameId, inning, oldPlayer, newPlayer, eventCount, diff) ->
    newBatter = @newBatter diff, oldPlayer, newPlayer

    if newBatter
      Promise.bind @
        .then -> @createAtBat newPlayer, gameId, inning, eventCount
        .then -> @closeInactiveAtBats gameId

  newBatter: (diff, oldPlayer, newPlayer) ->
    if (diff.length > 0) && (diff.indexOf "currentBatter") > -1
      if oldPlayer isnt newPlayer
        return true

  closeInactiveAtBats: (gameId) ->
    Promise.bind @
      .then -> @getLastAtBat gameId
      .then (atBatId) -> @Questions.find {commercial: false, gameId: gameId, active: true, atBatQuestion: true, atBatId: {$ne: atBatId}}
      .map (question) -> @closeSingleAtBat question

  closeSingleAtBat: (question) ->
    Promise.bind @
      .then -> @getAtBatOutcome question
      .then (result) ->
        @awardUsers question, result['option']

  getAtBatOutcome: (question) ->
    map = _.invert _.mapObject question['options'], (option) -> option['title']

    Promise.bind @
      .then -> @gameParser.findAtBat question
      .then (event) -> @eventTitle event.pbpDetailId
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
      .map (answer) -> @notifyWinners question, answer

  notifyWinners: (question, answer) ->
    reward = Math.floor answer['wager'] * answer['multiplier']
    Promise.bind @
      .then -> @Answers.update {_id: answer._id}, {$set: {outcome: "win"}} #
      .then -> @GamePlayed.update {userId: answer['userId'], gameId: question.gameId}, {$inc: {coins: reward}}
      .tap -> @logger.verbose "Awarding correct users!"
      .then ->
        @Notifications.insert
          _id: @Notifications.db.ObjectId().toString()
          dateCreated: new Date()
          questionId: question._id
          userId: answer['userId']
          gameId: question.gameId
          type: "coins"
          value: reward
          read: false
          message: "Nice Pickk! You got #{reward} Coins!"
          sharable: false
          shareMessage: ""

  createAtBat: (player, gameId, inning, eventCount) ->
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
        return options
      .then (options) -> @insertAtBat player, gameId, inning, eventCount, options

  insertAtBat: (player, gameId, inning, eventCount, options) ->
    Promise.bind @
      .then ->
        @AtBats.insert
          _id:  @AtBats.db.ObjectId().toString()
          dateCreated: new Date()
          gameId: gameId
          player: player
          playerId: player.playerId
          inning: inning
          eventCount: eventCount
      .then (atBat) -> @insertAtBatQuestion atBat, options

  insertAtBatQuestion: (atBat, options) ->
    question = "End of #{atBat.player.firstName} #{atBat.player.lastName}'s at bat."
    Promise.bind @
      .then ->
        @Questions.insert
          _id: @Questions.db.ObjectId().toString()
          dateCreated: new Date()
          gameId: atBat.gameId
          atBatId: atBat._id
          playerId: atBat.playerId
          atBatQuestion: true
          inning: atBat.inning
          eventCount: atBat.eventCount
          period: 0
          type: "atBat"
          active: true
          commercial: false
          que: question
          options: options
          usersAnswered: []
      .tap (result) ->
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

  getLastAtBat: (gameId) ->
    Promise.bind @
      .then -> @AtBats.find({gameId: gameId}).sort({dateCreated: -1}).limit(1)
      .then (result) -> return result[0]._id
