Match = require "mtr-match"
Promise = require "bluebird"

module.exports = (fixtures, mongodb) ->
  Match.check fixtures, Object
  Match.check mongodb, Match.Any

  Promise.all (for collectionName, documents of fixtures
    collection = mongodb.collection collectionName
    Promise.all (collection.insert document for document in documents)
  )
      
