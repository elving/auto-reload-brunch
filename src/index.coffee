sysPath = require 'path'
WebSocketServer = (require 'ws').Server
{isWorker} = require 'cluster'

isCss = (file) ->
  sysPath.extname(file.path) is '.css'

module.exports = class AutoReloader
  brunchPlugin: yes

  constructor: (@config) ->
    if 'autoReload' of @config
      console.warn 'Warning: config.autoReload is deprecated, please move it to config.plugins.autoReload'
    cfg = @config.plugins?.autoReload ? @config.autoReload ? {}
    @enabled = cfg.enabled ? true if @config.persistent
    {@delay} = cfg
    @connections = []
    ports = cfg.port ? [9485..9495]
    ports = [ports] unless Array.isArray ports
    @port = ports.shift()
    startServer = =>
      @server = new WebSocketServer {host: '0.0.0.0', @port}
      @server.on 'connection', (connection) =>
        @connections.push connection
        connection.on 'close', =>
          @connections.splice connection, 1
      @server.on 'error', (error) =>
        if error.toString().match /EADDRINUSE/
          if ports.length
            @port = ports.shift()
            return startServer()
          else
            error = "cannot start because port #{@port} is in use"
        console.error "AutoReload #{error}"
    startServer() if @enabled and not isWorker

  onCompile: (changedFiles) ->
    return unless @enabled
    didCompile = changedFiles.length > 0
    allCss = didCompile and changedFiles.every(isCss)
    if '[object Object]' is toString.call @enabled
      return unless didCompile or @enabled.assets
      if allCss
        return unless @enabled.css
      else if didCompile
        changedExts = changedFiles.map (_) ->
          sysPath.extname(_.path).slice(1)
        return unless Object.keys(@enabled).some (_) =>
          @enabled[_] and _ in changedExts
    message = if allCss then 'stylesheet' else 'page'

    sendMessage = => @connections
      .filter (connection) =>
        connection.readyState is 1
      .forEach (connection) =>
        connection.send message

    if @delay
      setTimeout sendMessage, @delay
    else
      do sendMessage

  include: ->
    if @enabled
      [(sysPath.join __dirname, '..', 'vendor', 'auto-reload.js')]
    else
      []

  teardown: -> @server?.close()

  # act as a compiler to automatically set ws port on client side
  type: 'javascript'
  extension: 'js'
  compile: (params, callback) ->
    if @enabled and @port isnt 9485 and 'auto-reload.js' is sysPath.basename params.path
      params.data = params.data.replace 9485, @port
    callback null, params
