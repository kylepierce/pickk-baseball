_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Task = require "./Task"
FantasyGame = require "../model/FantasyGame"

module.exports = class extends Task
  constructor: (dependencies) ->
    super

    Match.check dependencies, Match.ObjectIncluding
      fantasy: Match.Any
      mongodb: Match.Any

  execute: (date = new Date(), minutes = 1) ->
    api = @dependencies.fantasy.mlb

    Promise.bind @
    .then -> api.playByPlayDeltaAsync(date, minutes)
    .map @upsertGame

  upsertGame: (game) ->
    fantasyGame = new FantasyGame game
    collection = @dependencies.mongodb.collection("FantasyGames")
    collection.update fantasyGame.getSelector(), {$set: fantasyGame}, {upsert: true}

