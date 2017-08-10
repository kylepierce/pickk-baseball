_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Task = require "../Task"
SportRadarGame = require "../../model/sportRadar/SportRadarGame"
Team = require "../../model/Team"
Player = require "../../model/Player"
GameParser = require "./helper/GameParser"
Multipliers = require "./Multiplier"
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

  execute: (parms) ->
    pitchClosed = @didPitchClose parms

    if pitchClosed
      Promise.bind @
        .then -> @getLastPitch parms.gameId
        .then (question) -> @closeInactivePitches parms.gameId, parms.pitchNumber
        .then -> @createPitch parms, false

  didPitchClose: (parms) ->
    if (parms.diff.length > 0 || parms.pitchDiff > 0)
      if (parms.diff.indexOf "balls") > -1 || (parms.diff.indexOf "strikes") > -1
        return true
      else if parms.pitchDiff isnt 0
        return true

  closeInactivePitches: (gameId, pitchNumber) ->
    Promise.bind @
      .then -> @getLastAtBat gameId
      .then (atBatId) -> @Questions.find {
        commercial: false,
        gameId: gameId,
        active: true,
        atBatQuestion: {$exists: false}, $or: [{atBatId: {$ne: atBatId}}, {pitchNumber: {$ne: pitchNumber}}] # Find the open questions
      }
      .map (question) -> @closeSinglePitch question

  closeSinglePitch: (question) ->
    pitchNumber = question.pitchNumber
    # Find the event
    Promise.bind @
      .then -> @gameParser.findAtBat question #Get the entire at bat
      .then (atBat) ->
        if atBat.pitchDetails && atBat.pitchDetails[pitchNumber]
          return @pitchTitle atBat.pitchDetails[pitchNumber].result # Get the specific pitch
        else
          @logger.verbose "Cant find specific question. It was probably mistakenly made."
        #   @deleteQuestion question._id
      .then (outcome) -> @getPitchOption question, outcome
      .then (option) -> @updateQuestion question._id, option
      .catch (e) ->
        console.log e

  getPitchOption: (question, outcome) ->
    Promise.bind @
      .then -> _.invert _.mapObject question['options'], (option) -> option['title']
      .then (options) -> return options[outcome]

  updateQuestion: (questionId, outcome) ->
    Promise.bind @
      .then -> @Questions.update {_id: questionId}, $set: {active: false, outcome: outcome, lastUpdated: new Date()} # Close and add outcome string
      .then -> @Answers.update {questionId: questionId, answered: {$ne: outcome}}, {$set: {outcome: "lose"}}, {multi: true} # Losers
      .then -> @Answers.find {questionId: questionId, answered: outcome} # Find the winners
      .map (answer) -> @awardUsers answer, outcome

  awardUsers: (question, outcomeOption) ->
    reward = Math.floor answer['wager'] * answer['multiplier']
    Promise.bind @
      .then -> @Answers.update {_id: answer._id}, {$set: {outcome: "win"}} #
      .then -> @GamePlayed.update {userId: answer['userId'], gameId: question.gameId}, {$inc: {coins: reward}}
      .tap -> @logger.verbose "Awarding correct users!"
      .then ->
        @Notifications.insert
          _id: @Notifications.db.ObjectId().toString()
          dateCreated: new Date()
          question: question._id
          userId: answer['userId']
          gameId: question.gameId
          type: "coins"
          value: reward
          read: false
          message: "Nice Pickk! You got #{reward} Coins!"
          sharable: false
          shareMessage: ""

  pitchTitle: (pitchId) ->
    results = [
      title: "Strike"
      outcomes: ['S', 'T', 'J', 'U', 'O']
    ,
      title: "Ball"
      outcomes: ['B', 'L', 'M', '#', 'P']
    ,
      title: "Hit"
      outcomes: ['I', 'H']
    ,
      title: "Foul Ball"
      outcomes: ['F', 'G', 'R', 'V']
    ]

    result = ""
    for item in results
      if (item['outcomes'].indexOf pitchId) > -1
        return item['title']

  deleteQuestion: (id) ->
    Promise.bind @
      .then -> @Questions.find {_id: id}
      .then (question) ->
        @Questions.remove {_id: id}
      .then -> @Questions.find {_id: id}

  # getPitchOutcome: (pitch) ->
  #   pitchOutcome = @pitchTitle pitch['result']
  #
  #   strikes = pitch.strikes
  #   balls = pitch.balls
  #   result = pitch.result
  #   foulArray = ['F', 'G', 'R', 'V']
  #   strikesArray = ['S', 'T', 'J', 'U', 'O']
  #   ballArray = ['B', 'L', 'M', '#', 'P']
  #   hitArray = ['I', 'H']
  #
  #   if strikes < 2 && (foulArray.indexOf result) > -1
  #     pitchOutcome = "Foul Ball"
  #
  #   if strikes is 2 && (strikesArray.indexOf result) > -1
  #     pitchOutcome = "Strike Out"
  #
  #   if balls is 3 && (ballArray.indexOf result) > -1
  #     pitchOutcome = "Walk"
  #
  #   if (hitArray.indexOf result) > -1
  #     pitchOutcome = "Hit"
  #
  #   return pitchOutcome

  createPitch: (parms) ->
    # Requirements: gameId, player, inning, pitch, pitchNumber, atBatId
    newBatter = @newBatter parms

    count = @getCurrentCount parms.pitch, parms.pitchNumber
    details =
      strikes: if newBatter then 0 else count.strikes
      balls: if newBatter then 0 else count.balls
      pitchNumber: if newBatter then 1 else parms.pitchNumber + 1
      player: if newBatter then parms['newPlayer'] else parms['newPlayer']

    question = "#{details.player['firstName']} #{details.player['lastName']}: " + details.balls + " - " + details.strikes + " (##{details.pitchNumber})"

    Promise.bind @
      .then -> @getLastAtBat parms.gameId
      .then (atBatId) -> @insertPitch parms, question, details, atBatId

  insertPitch: (parms, question, details, atBatId) ->
    Promise.bind @
      .then -> @createPitchOptions details.balls, details.strikes
      .then (options) ->
        @Questions.insert
          _id: @Questions.db.ObjectId().toString()
          dateCreated: new Date()
          gameId: parms.gameId
          playerId: details.player['playerId']
          atBatId: atBatId
          pitchNumber: details.pitchNumber
          eventCount: parms.eventCount
          inning: parms.inning
          type: "pitch"
          period: 0
          active: true
          commercial: false
          que: question
          options: options
          usersAnswered: []
      .tap (result) ->
        questionId = result.upserted?[0]?._id
        @logger.verbose "Create pitch question (#{question})"
        # {gameId: parms.gameId, playerId: details.player.playerId, atBatId: parms.atBatId, pitchNumber: details.pitchNumber}

  getCurrentCount: (pitch, pitchNumber) ->
    foulArray = ['F', 'G', 'R', 'V']
    strikesArray = ['S', 'T', 'J', 'U', 'O']
    ballArray = ['B', 'L', 'M', '#', 'P']
    hitArray = ['I', 'H']

    result =  if pitch then pitch.result else null
    balls = if pitch then pitch.balls else 0
    strikes = if pitch then pitch.strikes else 0

    if pitchNumber is 0
      balls = 0
      strikes = 0

    if strikes < 2 && (strikesArray.indexOf result) > -1
      strikes += 1

    else if strikes < 2 && (foulArray.indexOf result) > -1
      strikes += 1

    if balls < 3 && (ballArray.indexOf result) > -1
      balls += 1

    count =
      strikes: strikes
      balls: balls

    return count

  createPitchOptions: (balls, strikes) ->
   Promise.bind @
    .then -> @multipliers.getGenericMultipliersForPitch()
    .then (multipliers) ->
      option1 = {title: "Strike", number: 1, multiplier: multipliers['strike']}
      option2 = {title: "Ball", number: 2, multiplier: multipliers['ball']}
      option3 = {title: "Hit", number: 3, multiplier: multipliers['hit']}
      option4 = {title: "Out", number: 4, multiplier: multipliers['out']}
      option5 = undefined

      if balls is 3
        option2.title = "Walk"

      if strikes is 2
        option1.title = "Strike Out"
        option3 = {title: "Foul Ball", number: 3, multiplier: multipliers['foulball']}
        option4 = {title: "Hit", number: 4, multiplier: multipliers['hit']}
        option5 = {title: "Out", number: 5, multiplier: multipliers['out']}

      options = {option1, option2, option3, option4}
      options.option5 = option5 if option5
      return options

  # Cant call at bat file for some reason. Move these last three.
  newBatter: (parms) ->
    if (parms.diff.length > 0) && (parms.diff.indexOf "currentBatter") > -1
      if parms.oldPlayer isnt parms.newPlayer
        return true

  # Cant call at bat file for some reason. Move these last three.
  getLastAtBat: (gameId) ->
    Promise.bind @
      .then -> @AtBats.find({gameId: gameId}).sort({dateCreated: -1}).limit(1)
      .then (result) -> return result[0]._id

  # Cant call at bat file for some reason. Move these last three.
  getLastPitch: (gameId) ->
    Promise.bind @
      .then -> @Questions.find({gameId: gameId, type: "pitch"}).sort({dateCreated: -1}).limit(1)
      .then (result) ->
        if result
          return result[0]
        else
          throw new Error("No question?")
      .catch (e) ->
          return false
