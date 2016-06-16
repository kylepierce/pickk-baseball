createDependencies = require "../helper/dependencies"
settings = (require "../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")
Promise = require "bluebird"
moment = require "moment"
ImportActiveTeams = require "../lib/task/ImportActiveTeams"

describe "Import data from Fantasy to Mongo", ->
  dependencies = createDependencies settings, "PickkImport"

  importActiveTeams = new ImportActiveTeams dependencies
  FantasyGames = dependencies.mongodb.collection("FantasyGames")
  FantasyTeams = dependencies.mongodb.collection("FantasyTeams")

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
          count.should.be.equal teamNumber
        .then -> FantasyTeams.findOne({"TeamID": 23})
        .then (team) ->
          should.exist team["Key"]
          team["Key"].should.be.equal "COL"
          should.exist team["Name"]
          team["Name"].should.be.equal "Rockies"
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone
