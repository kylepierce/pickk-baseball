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

  execute: (old, update) ->
    Promise.bind @
      .then -> @checkGameStatus old, update
      .catch (error) =>
        @logger.verbose error
      .then -> @handleGame old, update
      .return true
      .catch (error) =>
        @logger.error error.message, _.extend({stack: error.stack}, error.details)

  calculateMultipliersForPlay: (bases, playerId) ->
    Promise.bind @
    .then -> @Players.findOne({_id: playerId})
    .then (player) ->
      stat = if player.stats.three_year['no_statistics_available_'] then player.stats.y2016extended else player.stats.three_year

      situation = switch true
        when bases.first and bases.second and bases.third then stat['bases_loaded']
        when bases.first then stat['runners_on']
        when bases.second and bases.third then stat['scoring_position']
        else stat['total']

      atBats = situation.ab
      avg = situation.avg
      hit = situation.h
      walk = parseInt(situation.bb)
      hitByBall = parseInt(situation.hbp)
      walkPercent = (walk + hitByBall ) / atBats
      homeRun = parseInt(situation.hr)
      homeRunPercent = homeRun / atBats
      triple = parseInt(situation.triple)
      triplePercent = triple / atBats
      double = parseInt(situation.double)
      doublePercent = double / atBats
      single = parseInt(hit - homeRun - double - triple)
      singlePercent = single / atBats
      outs = (atBats - hitByBall - walk - homeRun - triple - double - single)
      outPercent = outs / atBats

      outPercent = (100 - (outPercent*100).toFixed(2))
      walkPercent = (100 - (walkPercent*100).toFixed(2))
      singlePercent = (100 - (singlePercent*100).toFixed(2))
      doublePercent = (100 - (doublePercent*100).toFixed(2))
      triplePercent = (100 - (triplePercent*100).toFixed(2))
      homeRunPercent = (100 - (homeRunPercent*100).toFixed(2))

      toMultiplier = (value) =>
        switch true
          when value < 25 then @getRandomArbitrary 1.95, 2.45
          when value < 50 then @getRandomArbitrary 2.27, 3.3
          when value < 60 then @getRandomArbitrary 3.2, 4.7
          when value < 75 then @getRandomArbitrary 3.65, 4.15
          when value < 85 then @getRandomArbitrary 3.75, 5.35
          when value < 90 then @getRandomArbitrary 4.25, 6.75
          when value < 95 then @getRandomArbitrary 5.65, 8.95
          when value < 99 then @getRandomArbitrary 7.95, 14.5
          else @getRandomArbitrary 5.5, 9

      out: toMultiplier outPercent
      walk: toMultiplier walkPercent
      single: toMultiplier singlePercent
      double: toMultiplier doublePercent
      triple: toMultiplier triplePercent
      homerun: toMultiplier homeRunPercent
    .catch (error) ->
      # @logger.verbose "Fallback to generic multipliers for play. Player (#{playerId})"
      @getGenericMultipliersForPlay()

  calculateMultipliersForPitch: (playerId, balls, strikes) ->
    Promise.bind @
    .then -> @Players.findOne({_id: playerId})
    .then (player) ->

      stat = if player.stats.three_year['no_statistics_available_'] then player.stats.y2016extended else player.stats.three_year
      totalAtBat = stat.total['ab']

      currentPlayKey = "count_#{balls}_#{strikes}"
      play = stat[currentPlayKey] or player.stats.career
      playEoP = play['ab']

      # End of Play probability
      EoP = parseInt(playEoP) / parseInt(totalAtBat)
      remainingPercent = 1 - EoP
      hitPercent = play['avg'] * EoP
      outPercent = (1 - hitPercent) * EoP

      if strikes is 2
        option1EoP = play['so']
      else
        nextPlayKey = "count_#{balls}_#{strikes + 1}"
        nextPlay = stat[nextPlayKey]
        option1EoP = nextPlay?['ab'] or 1

      if balls is 3
        option2EoP = play['bb']
      else
        nextPlayKey = "count_#{balls + 1}_#{strikes}"
        nextPlay = stat[nextPlayKey]
        option2EoP = nextPlay?['ab'] or 1

      option1EoP = parseInt option1EoP
      option2EoP = parseInt option2EoP
      combinedEoP = option1EoP + option2EoP
      option1EoPPercentage = (( option1EoP / combinedEoP ) * remainingPercent).toFixed(4)
      option2EoPPercentage = (( option2EoP / combinedEoP ) * remainingPercent).toFixed(4)

      strikePercent = (100 - (option1EoPPercentage * 100).toFixed(2))
      ballPercent = (100 - (option2EoPPercentage *100).toFixed(2))
      outPercent = (100 - (outPercent*100).toFixed(2))
      hitPercent = (100 - (hitPercent*100).toFixed(2))

      toMultiplier = (value) =>
        switch true
          when value < 25 then @getRandomArbitrary 1.55,2.25
          when value < 50 then @getRandomArbitrary 1.75, 2.25
          when value < 60 then @getRandomArbitrary 2.5,2.75
          when value < 75 then @getRandomArbitrary 2.75, 3.25
          when value < 85 then @getRandomArbitrary 3.25, 2.75
          when value < 90 then @getRandomArbitrary 3.75, 4.5
          else @getRandomArbitrary 3.5, 4.5

      strike: toMultiplier strikePercent
      ball: toMultiplier ballPercent
      out: toMultiplier outPercent
      hit: toMultiplier hitPercent
      foulball: @getRandomArbitrary(1.5, 2)
    .catch (error) ->
      # @logger.verbose "Fallback to generic multipliers for pitch. Player (#{playerId})"
      @getGenericMultipliersForPitch()

  getGenericMultipliersForPlay: ->
    out: @getRandomArbitrary 1.95, 2.95
    walk: @getRandomArbitrary 3.05, 5.65
    single: @getRandomArbitrary 3.35, 5.65
    double: @getRandomArbitrary 6.05, 8.65
    triple: @getRandomArbitrary 9.05, 15.65
    homerun: @getRandomArbitrary 8.05, 12.65

  getGenericMultipliersForPitch: ->
    strike: @getRandomArbitrary 1.55, 2.5
    ball: @getRandomArbitrary 1.45, 2.65
    out: @getRandomArbitrary 2.05, 3.65
    hit: @getRandomArbitrary 3.05, 5.65
    foulball: @getRandomArbitrary 1.65, 2.45

  getRandomArbitrary: (min, max) -> parseFloat((Math.random() * (max - min) + min).toFixed(2))
