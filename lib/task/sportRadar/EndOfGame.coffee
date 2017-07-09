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
    @GamePlayed = dependencies.mongodb.collection("gamePlayed")
    @Notifications = dependencies.mongodb.collection("notifications")
    @SportRadarGames = dependencies.mongodb.collection("games")

  execute: (gameId) ->
    return if game.close_processed isnt false

    Promise.bind @
      .then -> @exchangeCoins gameId
      .then -> @awardLeaders gameId
      .then -> @SportRadarGames.update {_id: gameId}, {$set: {close_processed: true}}

  exchangeCoins: (gameId) ->
    Promise.bind @
    .then -> @GamePlayed.find {gameId: gameId}
    .map (player) ->
      notificationId = chance.guid()
      rate = if player['coins'] < 10000 then 2500 else 7500
      {coins} = player
      diamonds = Math.floor(coins / rate)
      message = "You traded #{coins} coins you earned playing #{game.name} for #{diamonds} diamonds"

      Promise.bind @
      .then ->
        @GamePlayed.update {userId: player['userId'], gameId: gameId}, {$inc: {diamonds: diamonds}}
      .then ->
        @Notifications.insert
          _id: notificationId
          userId: player['userId']
          type: "diamonds"
          source: "Exchange"
          gameId: gameId
          read: false
          notificationId: notificationId
          dateCreated: new Date()
          message: message
      # .tap -> @logger.verbose "Exchange coins on diamonds (#{diamonds})", {userId: player['userId'], gameId: game._id}

  awardLeaders: (gameId) ->
    rewards = [50, 40, 30, 25, 22, 20, 17, 15, 12, 10]
    positions = [1..10]
    images = {1: "1st", 2: "2nd", 3: "3rd"}
    places = {1: "First", 2: "Second", 3: "Third"}
    trophyId = "xNMMTjKRrqccnPHiZ"

    Promise.bind @
    .then -> @GamePlayed.find({gameId: gameId}).sort({coins: -1}).limit(10)
    .then (players) ->
      winners = _.zip players, rewards, positions
      winners = winners.slice 0, players.length # in case when there are less than 10 players involved
      Promise.all (for winner in winners
        do (winner) =>
          [player, reward, position] = winner

          notificationTrophyId = chance.guid()
          notificationId = chance.guid()
          now = new Date()

          notifications = []

          notifications.push
            _id: notificationTrophyId
            userId: player['userId']
            type: "trophy"
            gameId: gameId
            notificationId: notificationTrophyId
            dateCreated: now

          if position <= 3
            notifications.push
              _id: notificationId
              userId: player['userId']
              type: "diamonds"
              tag: "leader"
              gameId: gameId
              read: false
              notificationId: notificationId
              dateCreated: now
              message: "<img style='max-width:100%;' src='/#{images[position]}.png'> <br>Congrats On Winning #{places[position]} Place Here is #{reward} Diamonds!"

          Promise.bind @
          .then ->
            @GamePlayed.update {userId: player['userId'], gameId: gameId}, {$inc: {diamonds: reward}}
          .then ->
            @Users.update {_id: player['userId']},
              $push:
                "profile.trophies": trophyId
          .then -> Promise.all (@Notifications.insert notification for notification in notifications)
          # .tap -> @logger.verbose "Reward user #{player['userId']} with #{reward} diamonds for position #{position} in game (#{game.name})"
      )
