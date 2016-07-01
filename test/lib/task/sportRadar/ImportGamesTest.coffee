createDependencies = require "../../../../helper/dependencies"
settings = (require "../../../../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")
Promise = require "bluebird"
moment = require "moment"
ImportGames = require "../../../../lib/task/sportRadar/ImportGames"
loadFixtures = require "../../../../helper/loadFixtures"
sportRadarGamesFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/importGames/collection/SportRadarGames.json"
sportRadarGamesWithInningsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/importGames/collection/SportRadarGamesWithInnings.json"

describe "Import brief information about games for date specified from SportRadar to Mongo", ->
  dependencies = createDependencies settings, "PickkImport"
  mongodb = dependencies.mongodb

  importGames = undefined
  SportRadarGames = mongodb.collection("games")

  date = moment("2016-06-11").toDate()
  gameId = "fec58a7a-eff7-4eec-9535-f64c42cc4870"

  beforeEach ->
    importGames = new ImportGames dependencies

    Promise.bind @
    .then ->
      Promise.all [
        SportRadarGames.remove()
      ]

  it 'should import games into the clear collection', ->
    gameNumber = undefined

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/task/sportRadar/importGames/request/games.json", (recordingDone) ->
        Promise.bind @
        .then -> dependencies.sportRadar.getScheduledGames date
        .then (result) -> gameNumber = result.league.games.length
        .then -> importGames.execute(date)
        .then -> SportRadarGames.count()
        .then (count) ->
          # ensure amount of games is right
          count.should.be.equal gameNumber
        .then -> SportRadarGames.findOne({"id": gameId})
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
      nock.back "test/fixtures/task/sportRadar/importGames/request/games.json", (recordingDone) ->
        Promise.bind @
        .then -> loadFixtures sportRadarGamesFixtures, mongodb
        .then -> SportRadarGames.findOne({"id": gameId})
        .then (result) ->
          # ensure "Key" is corrupted
          should.exist result

          {status} = result
          should.exist status
          status.should.be.equal "InProgress"
        .then -> dependencies.sportRadar.getScheduledGames date
        .then (result) -> gameNumber = result.league.games.length
        .then -> importGames.execute(date)
        .then -> SportRadarGames.count()
        .then (count) ->
          # ensure amount of games is right
          count.should.be.equal gameNumber
        .then -> SportRadarGames.findOne({"id": gameId})
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

  it 'shouldn\'t drop data fetched by other calls before', ->
    new Promise (resolve, reject) ->
      nock.back "test/fixtures/task/sportRadar/importGames/request/single.json", (recordingDone) ->
        Promise.bind @
        .then -> loadFixtures sportRadarGamesWithInningsFixtures, mongodb
        .then -> SportRadarGames.findOne({"id": gameId})
        .then (game) ->
          # ensure the game contains innings
          should.exist game

          {innings} = game
          should.exist innings
          innings.should.be.an "array"
          innings.length.should.be.equal 1
        .then -> importGames.execute(date)
        .then -> SportRadarGames.findOne({"id": gameId})
        .then (game) ->
          # ensure innings hasn't been override
          should.exist game

          {innings} = game
          should.exist innings
          innings.should.be.an "array"
          innings.length.should.be.equal 1
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone

  it 'should emit event for each upserted game', ->
    spy = sinon.spy()
    importGames.observe "upserted", spy

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/task/sportRadar/importGames/request/single.json", (recordingDone) ->
        Promise.bind @
        .then -> importGames.execute(date)
        .then ->
          spy.should.have.callCount 15
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone
