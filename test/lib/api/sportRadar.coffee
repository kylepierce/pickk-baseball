createDependencies = require "../../../helper/dependencies"
settings = (require "../../../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")
Promise = require "bluebird"
moment = require "moment"
_ = require "underscore"

describe "SportRadar API", ->
  dependencies = createDependencies settings, "PickkImport"

  date = moment("2016-06-11").toDate()

  it 'should check whether scheduled games are fetched', ->
    @timeout(60000) if process.env.NOCK_BACK_MODE in ["record", "wild"]

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/api/sportRadar/getScheduledGames.json", (recordingDone) ->
        Promise.bind @
        .then -> dependencies.sportRadar.getScheduledGames(date)
        .then (result) ->
          should.exist result

          {league} = result
          should.exist league
          league.should.be.an "object"

          {games} = league
          should.exist games
          games.should.be.an "array"
          games.length.should.be.equal 15
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone
