createDependencies = require "../../../helper/dependencies"
settings = (require "../../../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")
Promise = require "bluebird"
moment = require "moment"
_ = require "underscore"

describe "SportRadar API", ->
  dependencies = createDependencies settings, "PickkImport"

  date = moment("2016-06-12").toDate() # in fact 2016-06-11 because of time zone shift
  gameId = "6a37e74c-728f-4ee5-8f99-5387cde7e397"
  teamId = "833a51a9-0d84-410f-bd77-da08c3e5e26e"

  it 'should check whether scheduled games are fetched', ->
    @timeout(60000) if process.env.NOCK_BACK_MODE in ["record", "wild"]

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/api/sportRadar/getScheduledGames.json", (recordingDone) ->
        Promise.bind @
        .then -> dependencies.sportRadar.getScheduledGames date
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

  it 'should check whether detailed information about the game are fetched', ->
    @timeout(60000) if process.env.NOCK_BACK_MODE in ["record", "wild"]

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/api/sportRadar/getPlayByPlay.json", (recordingDone) ->
        Promise.bind @
        .then -> dependencies.sportRadar.getPlayByPlay gameId
        .then (result) ->
          should.exist result

          {game} = result
          should.exist game
          game.should.be.an "object"

          {id} = game
          should.exist id
          id.should.be.equal "6a37e74c-728f-4ee5-8f99-5387cde7e397"

          {innings} = game
          should.exist innings
          innings.should.be.an "array"
          innings.length.should.be.equal 11
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone

  it 'should check whether information about the team are fetched', ->
    @timeout(60000) if process.env.NOCK_BACK_MODE in ["record", "wild"]

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/api/sportRadar/getTeamProfile.json", (recordingDone) ->
        Promise.bind @
        .then -> dependencies.sportRadar.getTeamProfile teamId
        .then (result) ->
          should.exist result

          {name, players} = result
          should.exist name
          name.should.be.equal "Royals"

          should.exist players
          players.should.be.an "array"
          players.length.should.be.equal 40
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone
