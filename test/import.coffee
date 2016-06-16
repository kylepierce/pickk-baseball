createDependencies = require "../helper/dependencies"
settings = (require "../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")
Promise = require "bluebird"
moment = require "moment"
ImportActiveTeams = require "../lib/task/ImportActiveTeams"
ImportGamesForDate = require "../lib/task/ImportGamesForDate"
loadFixtures = require "../helper/loadFixtures"
fantasyTeamsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/import/data/FantasyTeams.json"
fantasyGamesFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/import/data/FantasyGames.json"

describe "Import data from Fantasy to Mongo", ->
  dependencies = createDependencies settings, "PickkImport"
  mongodb = dependencies.mongodb

  importActiveTeams = new ImportActiveTeams dependencies
  importGamesForDate = new ImportGamesForDate dependencies
  FantasyGames = mongodb.collection("FantasyGames")
  FantasyTeams = mongodb.collection("FantasyTeams")

  date = moment("2016-06-11")
  minutes = 10

  beforeEach ->
    Promise.bind @
    .then ->
      Promise.all [
        FantasyGames.remove()
        FantasyTeams.remove()
      ]

  it 'should import teams into the clear collection', ->
    teamNumber = undefined

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/import/activeTeams.json", (recordingDone) ->
        Promise.bind @
        .then -> dependencies.fantasy.mlb.activeTeamsAsync()
        .then (result) -> teamNumber = result.length
        .then -> importActiveTeams.execute()
        .then -> FantasyTeams.count()
        .then (count) ->
          # ensure amount of teams is right
          count.should.be.equal teamNumber
        .then -> FantasyTeams.findOne({"TeamID": 23})
        .then (team) ->
          # ensure some team has been added properly
          should.exist team["Key"]
          team["Key"].should.be.equal "COL"
          should.exist team["Name"]
          team["Name"].should.be.equal "Rockies"
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone

  it 'should update existing and insert new teams into the collection', ->
    teamNumber = undefined

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/import/activeTeams.json", (recordingDone) ->
        Promise.bind @
        .then -> loadFixtures fantasyTeamsFixtures, mongodb
        .then -> FantasyTeams.findOne({"TeamID": 14})
        .then (team) ->
          # ensure "Key" is corrupted
          should.exist team["Key"]
          team["Key"].should.be.equal "WRONG_KEY"
        .then -> dependencies.fantasy.mlb.activeTeamsAsync()
        .then (result) -> teamNumber = result.length
        .then -> importActiveTeams.execute()
        .then -> FantasyTeams.count()
        .then (count) ->
          # ensure amount of teams is right
          count.should.be.equal teamNumber
        .then -> FantasyTeams.findOne({"TeamID": 14})
        .then (team) ->
          # ensure "Key" has been updated
          should.exist team["Key"]
          team["Key"].should.be.equal "ARI"
        .then -> FantasyTeams.findOne({"TeamID": 23})
        .then (team) ->
          # ensure another team has been added properly
          should.exist team["Key"]
          team["Key"].should.be.equal "COL"
          should.exist team["Name"]
          team["Name"].should.be.equal "Rockies"
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone

  it 'should import games into the clear collection', ->
    gameNumber = undefined

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/import/games.json", (recordingDone) ->
        Promise.bind @
        .then -> dependencies.fantasy.mlb.boxScoresAsync(date)
        .then (result) -> gameNumber = result.length
        .then -> importGamesForDate.execute(date)
        .then -> FantasyGames.count()
        .then (count) ->
          # ensure amount of games is right
          count.should.be.equal gameNumber
        .then -> FantasyGames.findOne({"Game.GameID": 45848})
        .then (result) ->
          # ensure some game has been added properly
          should.exist result["Game"]
          result["Game"].should.be.an "object"
          game = result["Game"]
          should.exist game["Status"]
          game["Status"].should.be.equal "Final"
          should.exist game["AwayTeamID"]
          game["AwayTeamID"].should.be.equal 12
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone

  it 'should update existing and insert new games into the collection', ->
    gameNumber = undefined

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/import/games.json", (recordingDone) ->
        Promise.bind @
        .then -> loadFixtures fantasyGamesFixtures, mongodb
        .then -> FantasyGames.findOne({"Game.GameID": 45848})
        .then (result) ->
          # ensure "Key" is corrupted
          should.exist result["Game"]
          result["Game"].should.be.an "object"
          game = result["Game"]
          should.exist game["Status"]
          game["Status"].should.be.equal "InProgress"
        .then -> dependencies.fantasy.mlb.boxScoresAsync(date)
        .then (result) -> gameNumber = result.length
        .then -> importGamesForDate.execute(date)
        .then -> FantasyGames.count()
        .then (count) ->
          # ensure amount of games is right
          count.should.be.equal gameNumber
        .then -> FantasyGames.findOne({"Game.GameID": 45848})
        .then (result) ->
          # ensure "Status" has been updated
          should.exist result["Game"]
          result["Game"].should.be.an "object"
          game = result["Game"]
          should.exist game["Status"]
          game["Status"].should.be.equal "Final"
          # ensure "Innings" has been updated
          should.exist result["Innings"]
          result["Innings"].should.be.an "array"
          result["Innings"].length.should.be.equal 9
        .then -> FantasyGames.findOne({"Game.GameID": 45851})
        .then (result) ->
          # ensure some game has been added properly
          should.exist result["Game"]
          result["Game"].should.be.an "object"
          game = result["Game"]
          should.exist game["Status"]
          game["Status"].should.be.equal "Final"
          should.exist game["AwayTeamID"]
          game["AwayTeamID"].should.be.equal 25
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone
