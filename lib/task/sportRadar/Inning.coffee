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
    # Requirements: gameId, gameName, inning, inningDivision, oldPlayer, oldInning, newInning, atBatId, team
    # if parms.oldInning isnt parms.newInning
    if (parms.diff.length > 0) && (parms.diff.indexOf "inningDivision") > -1
      console.log "---------------------------\n", "New inning!!!!!!", "---------------------------\n"

      Promise.bind @
        .then -> @SportRadarGames.update {_id: parms.gameId}, {$set: {commercial: true, commercialStartedAt: new Date()}}
        .then -> @resolveCommercialQuestions parms.gameId, parms.inning, parms.inningDivision, true
        .then -> @createCommercialQuestions parms.gameId, parms.inning, parms.inningDivision

  # handleCommercialBreak: (gameId, commercial) ->
  #   if not commercial
  #     Promise.bind @
  #       .then ->

  resolveCommercialQuestions: (gameId, inning, inningDivision, inningCompleted) ->
    Promise.bind @
      .then -> @Questions.find {
        gameId: gameId,
        commercial: true,
        processed: false,
        active: null,
        inning: inning,
        inningDivision: inningDivision
      }
      .map (question) ->
        if inningCompleted is true
          @rewardForCommercialQuestion gameId, question, false
        else
          list = question['outcomes']
          onList = list.indexOf event['pbpDetailId']
          if (onList) > -1
            @rewardForCommercialQuestion gameId, question, true

  rewardForCommercialQuestion: (gameId, question, correct) ->
    # Requirements: gameId, question Object, correct
    if correct
      outcome = "option1"
    else if !correct
      outcome = "option2"

    Promise.bind @
      .then -> @Questions.update {_id: question._id}, {$set: {active: false, outcome: outcome, processed: true, lastUpdated: new Date()}}
      .then -> @Answers.update {questionId: question._id, answered: {$ne: outcome}}, {$set: {outcome: "lose"}}, {multi: true}
      .then -> @Answers.find {questionId: question._id, answered: outcome}
      .map (answer) -> @notifyWinners answer, gameId

  notifyWinners: (answer, gameId) ->
    reward = @dependencies.settings['common']['commercialReward']

    Promise.bind @
      .then -> @Answers.update {_id: answer._id}, {$set: {outcome: "win"}}
      .then -> @GamePlayed.update {userId: answer['userId'], gameId: gameId}, {$inc: {coins: reward}}
      .then ->
        @Notifications.insert
          _id: @Notifications.db.ObjectId().toString()
          questionId: answer.questionId
          userId: answer['userId']
          gameId: gameId
          type: "coins"
          value: reward
          read: false
          dateCreated: new Date()
          message: "Nice Pickk! You got #{reward} Coins!"
          sharable: false
          shareMessage: ""

  createCommercialQuestions: (gameId, inning, inningDivision) ->
    if inningDivision is "Top"
      team = @SportRadarGames.find {_id: gameId}.away
    else
      team = @SportRadarGames.find {_id: gameId}.away

    Promise.bind @
      .then -> @createTemplate
      # .map (template) -> @insertCommericalQuestion team, gameId, inning, inningDivision

  createTemplate: () ->
    console.log "Hello"
    templates = [
      title: "Hit a Single"
      outcomes: [1, 2, 3, 4, 5, 6, 122]
    ,
      title: "Hit a Double"
      outcomes: [7, 8, 9, 10, 11, 123]
    ,
      title: "Hit a Triple"
      outcomes: [12, 13, 124]
    ,
      title: "Hit a Home Run"
      outcomes: [15, 16, 17, 18]
    ,
      title: "Steal a Base"
      outcomes: [15, 16, 17, 18]
    ,
      title: "Get Hit by a Pitch"
      outcomes: ["61"]
    ]

    templates = _.sample templates, 2
    console.log templates
    return templates

  insertCommericalQuestion: (team, gameId, inning, inningDivision) ->
    name = team.nickname
    if inning is 1
      inningGrammer = "st"
    else if inning is 2
      inningGrammer = "nd"
    else if inning is 3
      inningGrammer = "rd"
    else
      inningGrammer = "th"

    que = "Will #{name} #{template.title} in the #{inning}#{inningGrammer} inning?"

    options =
      option1: {title: "True", number: 1, multiplier: 4}
      option2: {title: "False",  number: 2, multiplier: 4}

    Promise.bind @
      .then ->
        @Questions.insert
          _id: @Questions.db.ObjectId().toString()
          que: que
          type: "freePickk"
          game_id: parms.gameId
          gameId: parms.gameId
          teamId: team.teamId
          inningDivision: parms.inningDivision
          inning: parms.inning
          period: 1
          dateCreated: new Date()
          active: true
          processed: false
          commercial: true
          binaryChoice: true
          options: options
          outcomes: template.outcomes
          usersAnswered: []
      .tap ->
        @logger.verbose "Create commercial question '#{text}' for the game (#{game.name})"

  closeActiveCommercialQuestions: (gameId) ->
    Promise.bind @
    .then -> @Questions.find {commercial: true, game_id: gameId, active: true}
    .map (question) ->
      Promise.bind @
      .then -> @Questions.update {_id: question._id}, {$set: {active: null, lastUpdated: new Date()}}
