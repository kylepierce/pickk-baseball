createDependencies = require "../helper/dependencies"
settings = (require "../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")
Promise = require "bluebird"
moment = require "moment"

describe "Fantasy API", ->
  dependencies = createDependencies settings, "PickkImport"

  date = moment("2016-06-11")
  minutes = 10

  it 'should check whether "areAnyGamesInProgress" works for MLB', ->
    @timeout(60000) if process.env.NOCK_BACK_MODE in ["record", "wild"]

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/fantasy/mlb/areAnyGamesInProgress.json", (recordingDone) ->
        Promise.bind @
        .then -> dependencies.fantasy.mlb.areAnyGamesInProgressAsync()
        .then (result) ->
          result.should.be.a "boolean"
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone

  it 'should check whether "activeTeams" works for MLB', ->
    @timeout(60000) if process.env.NOCK_BACK_MODE in ["record", "wild"]

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/fantasy/mlb/activeTeamsAsync.json", (recordingDone) ->
        Promise.bind @
        .then -> dependencies.fantasy.mlb.activeTeamsAsync()
        .then (result) ->
          result.should.be.an "array"
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone

  it 'should check whether "playByPlayDelta" works for MLB', ->
    @timeout(60000) if process.env.NOCK_BACK_MODE in ["record", "wild"]

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/fantasy/mlb/playByPlayDelta.json", (recordingDone) ->
        Promise.bind @
        .then -> dependencies.fantasy.mlb.playByPlayDeltaAsync(date, minutes)
        .then (result) ->
          result.should.be.an "array"
          result.length.should.be.equal 15
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone

  it 'should check whether "boxScores" works for MLB', ->
    @timeout(60000) if process.env.NOCK_BACK_MODE in ["record", "wild"]

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/fantasy/mlb/boxScores.json", (recordingDone) ->
        Promise.bind @
        .then -> dependencies.fantasy.mlb.boxScoresAsync(date)
        .then (result) ->
          result.should.be.an "array"
          result.length.should.be.equal 15
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone

