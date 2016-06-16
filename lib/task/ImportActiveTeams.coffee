_ = require "underscore"
Match = require "mtr-match"
Promise = require "bluebird"
Task = require "./Task"
FantasyTeam = require "../model/FantasyTeam"

module.exports = class extends Task
  constructor: (dependencies) ->
    super

    Match.check dependencies, Match.ObjectIncluding
      fantasy: Match.Any
      mongodb: Match.Any

  execute: ->
    api = @dependencies.fantasy.mlb

    Promise.bind @
    .then -> api.activeTeamsAsync()
    .map @upsertTeam

  upsertTeam: (team) ->
    fantasyTeam = new FantasyTeam team
    collection = @dependencies.mongodb.collection("FantasyTeams")
    collection.update fantasyTeam.getSelector(), {$set: fantasyTeam}, {upsert: true}

