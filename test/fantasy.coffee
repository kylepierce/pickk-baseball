createDependencies = require "../helper/dependencies"
settings = (require "../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")
Promise = require "bluebird"

describe "Fantasy API", ->
  dependencies = createDependencies settings, "PickkImport"

  it 'should check whether "areAnyGamesInProgress" works for MLB', ->
    @timeout(60000) if process.env.NOCK_BACK_MODE in ["record", "wild"]

    new Promise (resolve, reject) ->
      nock.back "test/fixtures/mbl/areAnyGamesInProgress.json", (recordingDone) ->
        Promise.bind @
        .then -> dependencies.fantasy.mlb.areAnyGamesInProgressAsync()
        .then (result) ->
          should.exist result
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone

