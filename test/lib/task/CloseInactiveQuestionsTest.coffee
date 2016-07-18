_ = require "underscore"
createDependencies = require "../../../helper/dependencies"
settings = (require "../../../helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")
Promise = require "bluebird"
CloseInactiveQuestions = require "../../../lib/task/CloseInactiveQuestions"
loadFixtures = require "../../../helper/loadFixtures"
gamesFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/closeInactiveQuestions/collection/games.json"
questionsFixtures = require "#{process.env.ROOT_DIR}/test/fixtures/task/closeInactiveQuestions/collection/questions.json"

describe "Close questions for inactive games", ->
  dependencies = createDependencies settings, "PickkImport"
  mongodb = dependencies.mongodb

  closeInactiveQuestions = new CloseInactiveQuestions dependencies
  SportRadarGames = mongodb.collection("games")
  Questions = mongodb.collection("questions")

  beforeEach ->
    Promise.bind @
    .then ->
      Promise.all [
        SportRadarGames.remove()
        Questions.remove()
      ]

  it 'should close questions related with inactive games', ->
    Promise.bind @
    .then -> loadFixtures gamesFixtures, mongodb
    .then -> loadFixtures questionsFixtures, mongodb
    .then -> closeInactiveQuestions.execute()
    .then -> Questions.findOne({id: "active_question_for_active_game"})
    .then (question) ->
      should.exist question

      question.should.be.an "object"
      {active} = question

      should.exist active
      active.should.be.equal true
    .then -> Questions.find({game_id: "2b0ba18a-41f5-46d7-beb3-1e86b9a4acc0", active: true})
    .then (questions) ->
      should.exist questions

      questions.should.be.an "array"
      questions.length.should.be.equal 0
