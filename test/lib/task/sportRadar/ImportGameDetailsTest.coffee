createDependencies = require "../../../../helper/dependencies"
settings = (require "../../../../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")
Promise = require "bluebird"
moment = require "moment"
ImportGameDetails = require "../../../../lib/task/sportRadar/ImportGameDetails"
loadFixtures = require "../../../../helper/loadFixtures"
sportRadarGamesFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/importGameDetails/collection/SportRadarGames.json"
sportRadarGamesWithInningsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/sportRadar/importGameDetails/collection/SportRadarGamesWithInnings.json"

describe "Import details information about a game specified to Mongo", ->
  dependencies = createDependencies settings, "PickkImport"
  mongodb = dependencies.mongodb

  importGameDetails = new ImportGameDetails dependencies
  SportRadarGames = mongodb.collection("games")

  gameId = "fec58a7a-eff7-4eec-9535-f64c42cc4870"

  beforeEach ->
    Promise.bind @
    .then ->
      Promise.all [
        SportRadarGames.remove()
      ]

  it 'should set game details for a game in the first time', ->

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/task/sportRadar/importGameDetails/request/game.json", (recordingDone) ->
        Promise.bind @
        .then -> loadFixtures sportRadarGamesFixtures, mongodb
        .then -> SportRadarGames.findOne({"id": gameId})
        .then (game) ->
          # ensure the game has no innings at all
          should.exist game
          
          {innings} = game
          should.not.exist innings
        .then -> importGameDetails.execute gameId
        .then -> SportRadarGames.findOne({"id": gameId})
        .then (game) ->
          # ensure innings have been added
          should.exist game

          {innings} = game
          should.exist innings
          innings.length.should.be.equal 10
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone

  it 'should update game details for a game in progress', ->
    new Promise (resolve, reject) ->
      nock.back "test/fixtures/task/sportRadar/importGameDetails/request/game.json", (recordingDone) ->
        Promise.bind @
        .then -> loadFixtures sportRadarGamesWithInningsFixtures, mongodb
        .then -> SportRadarGames.findOne({"id": gameId})
        .then (game) ->
          # ensure the game contains only one inning at the moment
          should.exist game

          {innings} = game
          should.exist innings
          innings.length.should.be.equal 1
        .then -> importGameDetails.execute gameId
        .then -> SportRadarGames.findOne({"id": gameId})
        .then (game) ->
          # ensure innings have been added
          should.exist game

          {innings} = game
          should.exist innings
          innings.length.should.be.equal 10
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone
