createDependencies = require "../../../../helper/dependencies"
settings = (require "../../../../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")
Promise = require "bluebird"
moment = require "moment"
ImportGames = require "../../../../lib/task/sportRadar/ImportGames"
loadFixtures = require "../../../../helper/loadFixtures"
sportRadarGamesFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/importGames/collection/SportRadarGames.json"
inactualClosedGameFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/importGames/collection/InactualClosedGame.json"
closedGameFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/importGames/collection/ClosedGame.json"
sportRadarGamesWithInningsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/importGames/collection/SportRadarGamesWithInnings.json"

describe "Import brief information about games for date specified from SportRadar to Mongo", ->
  dependencies = createDependencies settings, "PickkImport"
  mongodb = dependencies.mongodb

  importGames = undefined
  SportRadarGames = mongodb.collection("games")

  date = moment("2016-06-12").toDate() # in fact 2016-06-11 because of time zone shift
  gameId = "fec58a7a-eff7-4eec-9535-f64c42cc4870"
  closedGameId = "69383e6a-7b67-486c-8f36-52f174a42c62"
  closedGameDate = moment("2016-08-02").toDate() # in fact 2016-08-01 because of time zone shift

  beforeEach ->
    importGames = new ImportGames dependencies

    Promise.bind @
    .then ->
      Promise.all [
        SportRadarGames.remove()
      ]

  it 'should import games into the clear collection', ->
    gameNumber = undefined
    @timeout 10000

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
          status.should.be.equal "inprogress"
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

  it 'should mark the game as "closing" when its state is changed to "closed"', ->
    new Promise (resolve, reject) ->
      nock.back "test/fixtures/task/sportRadar/importGames/request/closed_game.json", (recordingDone) ->
        Promise.bind @
        .then -> loadFixtures inactualClosedGameFixtures, mongodb
        .then -> SportRadarGames.findOne({"id": closedGameId})
        .then (game) ->
          should.exist game

          {status, completed} = game
          should.exist status
          status.should.be.equal "inprogress"

          should.exist completed
          completed.should.be.equal false
        .then -> importGames.execute closedGameDate
        .then -> SportRadarGames.findOne({"id": closedGameId})
        .then (game) ->
          should.exist game

          {status, completed, close_processed} = game
          should.exist status
          status.should.be.equal "closed"

          should.exist completed
          completed.should.be.equal true

          should.exist close_processed
          close_processed.should.be.equal false
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone

  it 'shouldn\'t set "close_processed" if the game is already closed', ->
    new Promise (resolve, reject) ->
      nock.back "test/fixtures/task/sportRadar/importGames/request/closed_game.json", (recordingDone) ->
        Promise.bind @
        .then -> loadFixtures closedGameFixtures, mongodb
        .then -> importGames.execute closedGameDate
        .then -> SportRadarGames.findOne({"id": closedGameId})
        .then (game) ->
          should.exist game

          {close_processed} = game
          should.not.exist close_processed
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone
