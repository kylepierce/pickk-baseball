createDependencies = require "../../../../helper/dependencies"
settings = (require "../../../../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")
Promise = require "bluebird"
moment = require "moment"
ImportGames = require "../../../../lib/task/sportRadar/ImportGames"
loadFixtures = require "../../../../helper/loadFixtures"
sportRadarGamesFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/importGames/collections/SportRadarGames.json"

describe "Import data from SportRadar to Mongo", ->
  dependencies = createDependencies settings, "PickkImport"
  mongodb = dependencies.mongodb

  importGames = new ImportGames dependencies
  SportRadarGames = mongodb.collection("SportRadarGames")

  date = moment("2016-06-11").toDate()

  beforeEach ->
    Promise.bind @
    .then ->
      Promise.all [
        SportRadarGames.remove()
      ]

  it 'should import games into the clear collection', ->
    gameNumber = undefined

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/task/sportRadar/importGames/games.json", (recordingDone) ->
        Promise.bind @
        .then -> dependencies.sportRadar.getScheduledGames(date)
        .then (result) -> gameNumber = result.league.games.length
        .then -> importGames.execute(date)
        .then -> SportRadarGames.count()
        .then (count) ->
          # ensure amount of games is right
          count.should.be.equal gameNumber
        .then -> SportRadarGames.findOne({"id": "fec58a7a-eff7-4eec-9535-f64c42cc4870"})
        .then (result) ->
          # ensure some game has been added properly
          should.exist result

          {status} = result
          should.exist status
          status.should.be.equal "closed"

          {home} = result
          should.exist home
          home.should.be.an "object"

          {name} = home
          should.exist name
          name.should.be.equal "White Sox"
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone

  it 'should update existing and insert new games into the collection', ->
    gameNumber = undefined

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/task/sportRadar/importGames/games.json", (recordingDone) ->
        Promise.bind @
        .then -> loadFixtures sportRadarGamesFixtures, mongodb
        .then -> SportRadarGames.findOne({"id": "fec58a7a-eff7-4eec-9535-f64c42cc4870"})
        .then (result) ->
          # ensure "Key" is corrupted
          should.exist result

          {status} = result
          should.exist status
          status.should.be.equal "InProgress"
        .then -> dependencies.sportRadar.getScheduledGames(date)
        .then (result) -> gameNumber = result.league.games.length
        .then -> importGames.execute(date)
        .then -> SportRadarGames.count()
        .then (count) ->
          # ensure amount of games is right
          count.should.be.equal gameNumber
        .then -> SportRadarGames.findOne({"id": "fec58a7a-eff7-4eec-9535-f64c42cc4870"})
        .then (result) ->
          # ensure some game has been added properly
          should.exist result

          {status} = result
          should.exist status
          status.should.be.equal "closed"

          {home} = result
          should.exist home
          home.should.be.an "object"

          {name} = home
          should.exist name
          name.should.be.equal "White Sox"
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone
