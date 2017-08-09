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
    @Answers = dependencies.mongodb.collection("answers")
    @GamePlayed = dependencies.mongodb.collection("gamePlayed")
    @Users = dependencies.mongodb.collection("users")
    @Notifications = dependencies.mongodb.collection("notifications")
    @gameParser = new GameParser dependencies
    @multipliers = new Multipliers dependencies

  execute: (parms) ->
    pitchClosed = @didPitchClose parms
    if !parms.pitch
      return
    outcome = @getPitchOutcome parms.pitch

    if pitchClosed
      Promise.bind @
        .then -> @closeInactivePitches parms, outcome
        .then -> @createPitch parms, false, outcome

  didPitchClose: (parms) ->
    if (parms.diff.length > 0 || parms.pitchDiff > 0)
      if (parms.diff.indexOf "balls") > -1 || (parms.diff.indexOf "strikes") > -1
        return true
      else if parms.pitchDiff isnt 0
        return true

  closeInactivePitches: (parms, outcome) ->
    # Requirements: gameId, atBatId, pitchNumber, pitch
    pitchNumber = parms.pitchNumber + 1

    Promise.bind @
      # .then -> @getLastAtBat parms
      .then -> @Questions.find {
        commercial: false,
        gameId: parms.gameId,
        active: true,
        atBatQuestion: {$exists: false}, $or: [{atBatId: {$ne: parms.atBatId}}, {pitchNumber: {$ne: pitchNumber}}] # Find the open questions
      }
      .map (result) ->
        options = _.invert _.mapObject result['options'], (option) -> option['title']
        outcomeOption = options[outcome]
        Promise.bind @
          .then -> @Questions.update {_id: result._id}, $set: {active: false, outcome: outcomeOption, lastUpdated: new Date()} # Close and add outcome string
          .then -> @Answers.update {questionId: question._id, answered: {$ne: outcomeOption}}, {$set: {outcome: "lose"}}, {multi: true} # Losers
          .then -> @Answers.find {questionId: question._id, answered: outcomeOption} # Find the winners
          .map (answer) ->
            Promise.bind @
              .then -> @awardUsers answer, outcomeOption

  awardUsers: (question, outcomeOption) ->
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

  pitchTitle: (pitchTitle) ->
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
      if (item['outcomes'].indexOf pitchTitle) > -1
        return item['title']

  getPitchOutcome: (pitch) ->
    pitchOutcome = @pitchTitle pitch['result']

    strikes = pitch.strikes
    balls = pitch.balls
    result = pitch.result
    foulArray = ['F', 'G', 'R', 'V']
    strikesArray = ['S', 'T', 'J', 'U', 'O']
    ballArray = ['B', 'L', 'M', '#', 'P']
    hitArray = ['I', 'H']

    if strikes < 2 && (foulArray.indexOf result) > -1
      pitchOutcome = "Foul Ball"

    if strikes is 2 && (strikesArray.indexOf result) > -1
      pitchOutcome = "Strike Out"

    if balls is 3 && (ballArray.indexOf result) > -1
      pitchOutcome = "Walk"

    if (hitArray.indexOf result) > -1
      pitchOutcome = "Hit"

    return pitchOutcome

  createPitch: (parms, newBatter, outcome) ->
    ignoreList = ["Hit", "Walk", "Out", "Strike Out"]
    if (ignoreList.indexOf outcome) > -1
      return false

    # Requirements: gameId, player, inning, pitch, pitchNumber, atBatId
    count = @getCurrentCount parms.pitch, parms.pitchNumber
    strikes = count.strikes
    balls = count.balls
    pitchNumber = parms.pitchNumber + 1
    player = parms['newPlayer']

    # If there is a new batter we are going to set count to 0-0, pitchNumber to 1, change the AtBatId
    if newBatter
      strikes = 0
      balls = 0
      pitchNumber = 1
      player = parms['nextPlayer']

    question = "#{player['firstName']} #{player['lastName']}: " + balls + " - " + strikes + " (##{pitchNumber})"

    Promise.bind @
      # .then -> atBatId = @getLastAtBat parms
      # .then -> console.log atBatId
      .then -> @Questions.count {commercial: false, gameId: parms.gameId, playerId: player['playerId'], atBatQuestion: {$exists: false}, atBatId: parms.atBatId, pitchNumber: pitchNumber}
      .then (found) ->
        if not found
          Promise.bind @
            .then -> @createPitchOptions balls, strikes
            .then (options) ->
              @Questions.insert
                _id: @Questions.db.ObjectId().toString()
                dateCreated: new Date()
                gameId: parms.gameId
                playerId: player['playerId']
                atBatId: atBatId
                pitchNumber: pitchNumber
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
              {gameId: parms.gameId, playerId: player.playerId, atBatId: parms.atBatId, pitchNumber: pitchNumber}

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
