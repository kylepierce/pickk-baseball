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

  execute: (date = new Date()) ->
    api = @dependencies.fantasy.mlb

    Promise.bind @
    .then -> api.boxScoresAsync(date)
    .map @upsertGame

  upsertGame: (team) ->
    fantasyGame = new FantasyGame team
    collection = @dependencies.mongodb.collection("FantasyGames")
    collection.update fantasyGame.getSelector(), {$set: fantasyGame}, {upsert: true}

