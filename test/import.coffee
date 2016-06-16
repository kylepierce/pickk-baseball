createDependencies = require "../helper/dependencies"
settings = (require "../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")
Promise = require "bluebird"
moment = require "moment"
ImportActiveTeams = require "../lib/task/ImportActiveTeams"
loadFixtures = require "../helper/loadFixtures"
fantasyTeamsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/import/data/FantasyTeams.json"

describe "Import data from Fantasy to Mongo", ->
  dependencies = createDependencies settings, "PickkImport"
  mongodb = dependencies.mongodb

  importActiveTeams = new ImportActiveTeams dependencies
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

  it 'should import teams into clear collection', ->
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

  it 'should update existing and insert new teams into collection', ->
    teamNumber = undefined

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/import/activeTeams.json", (recordingDone) ->
        Promise.bind @
        .then -> loadFixtures fantasyTeamsFixtures, mongodb
        .then -> FantasyTeams.findOne({"TeamID": 14})
        .then (team) ->
          # ensure the "Key" is corrupted
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
          # ensure the "Key" was updated
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
