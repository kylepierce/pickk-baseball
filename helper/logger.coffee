util = require "util"
shelljs = require "shelljs"
winston = require "winston"
path = require "path"
loggly = require "winston-loggly"
sanitize = require "./sanitize"

winston.addColors
  verbose: "grey"
  info: "green"

module.exports = (options) ->
  transports = (new winston.transports[name](config) for name, config of options.transports)

  fileTransport = options.transports['File']
  if fileTransport
    directory = path.dirname fileTransport['filename']
    shelljs.mkdir "-p", directory

  logger = new winston.Logger(
    transports: transports
  )

#  logger.addRewriter (level, msg, meta) ->
#    sanitize(meta, options.sanitizedProperties)

  logger
