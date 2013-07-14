"use strict"

root = this

# To be initialized on document load
stdout = null
user_input = null
controller = null
editor = null
progress = null
bs_cl = null

sys_path = '/sys'

preload = ->
  $('#overlay').fadeOut 'slow'
  $('#progress-container').fadeOut 'slow'
  $('#console').click()
  return
  node.fs.readFile "#{sys_path}/browser/mini-rt.tar", (err, data) ->
    if err
      console.error "Error downloading mini-rt.tar: #{err}"
      return
    file_count = 0
    done = false
    start_untar = (new Date).getTime()
    on_complete = ->
      end_untar = (new Date).getTime()
      console.log "Untarring took a total of #{end_untar-start_untar}ms."
      $('#overlay').fadeOut 'slow'
      $('#progress-container').fadeOut 'slow'
      $('#console').click()
    update_bar = _.throttle ((percent, path) ->
      bar = $('#progress > .bar')
      preloading_file = $('#preloading-file')
      # +10% hack to make the bar appear fuller before fading kicks in
      display_perc = Math.min Math.ceil(percent*100), 100
      bar.width "#{display_perc}%"
      preloading_file.text(
        if display_perc < 100 then "Loading #{path}"  else "Done!"))

    untar new util.BytesArray(data), ((percent, path, file) ->
      update_bar(percent, path)
      base_dir = 'vendor/classes/'
      ext = path.split('.')[1]
      unless ext is 'class'
        on_complete() if percent == 100
        return
      file_count++
      asyncExecute (->
        # XXX: We convert from bytestr to array to process the tar file, and
        #      then back to a bytestr to store as a file in the filesystem.
        node.fs.writeFile path, util.array_to_bytestr(file), 'utf8', (err, data) ->
          if err
            console.error "Error writing #{path}: #{err}"
            return
          on_complete() if --file_count == 0 and done
      ), 0),
      ->
        done = true
        on_complete() if file_count == 0
    return

# Read in a binary classfile asynchronously. Return an array of bytes.
read_classfile = (cls, cb, failure_cb) ->
  cls = cls[1...-1] # Convert Lfoo/bar/Baz; -> foo/bar/Baz.
  cpath = jvm.system_properties['java.class.path']
  i = 0
  try_get = ->
    node.fs.readFile "#{cpath[i]}#{cls}.class", (err, data) ->
      i++
      if err
        if i is cpath.length
          failure_cb -> throw new Error "Error: No file found for class #{cls}."
        else
          try_get()
        return
      cb data
  # We could launch them all at once, but we would need to ensure that we use
  # the working version that occurs first in the classpath.
  try_get()

process_bytecode = (buffer) -> new ClassData.ReferenceClassData(buffer)

onResize = ->
  h = $(window).height() * 0.7
  $('#console').height(h)
  $('#source').height(h)

$(window).resize(onResize)

$(document).ready ->
  onResize()
  editor = $('#editor')
  # set up the local file loaders
  $('#file').change (ev) ->
    unless FileReader?
      controller.message """
        Your browser doesn't support file loading.
        Try using the editor to create files instead.
        """, "error"
      return $('#console').click() # click to restore focus
    num_files = ev.target.files.length
    files_uploaded = 0
    controller.message "Uploading #{num_files} files...\n", 'success', true
    # Need to make a function instead of making this the body of a loop so we
    # don't overwrite "f" before the onload handler calls.
    file_fcn = ((f) ->
      reader = new FileReader
      reader.onerror = (e) ->
        switch e.target.error.code
          when e.target.error.NOT_FOUND_ERR then alert "404'd"
          when e.target.error.NOT_READABLE_ERR then alert "unreadable"
          when e.target.error.SECURITY_ERR then alert "only works with --allow-file-access-from-files"
      ext = f.name.split('.')[1]
      isClass = ext == 'class'
      reader.onload = (e) ->
        files_uploaded++
        node.fs.writeFile node.process.cwd() + '/' + f.name, e.target.result, (err) ->
          if err
            controller.message "[#{files_uploaded}/#{num_files}] File '#{f.name}' could not be saved: #{err}\n", 'error', files_uploaded != num_files
          else
            controller.message "[#{files_uploaded}/#{num_files}] File '#{f.name}' saved.\n",
              'success', files_uploaded != num_files
            if isClass
              editor.getSession?().setValue("/*\n * Binary file: #{f.name}\n */")
            else
              editor.getSession?().setValue(e.target.result)
          $('#console').click() # click to restore focus
      if isClass then reader.readAsBinaryString(f) else reader.readAsText(f)
    )
    for f in ev.target.files
      file_fcn(f)
    return

  jqconsole = $('#console')
  controller = jqconsole.console
    promptLabel: 'doppio > '
    commandHandle: (line) ->
      [cmd,args...] = line.trim().split(/\s+/)
      if cmd == '' then return true
      handler = commands[cmd]
      try
        if handler? then handler(a.trim() for a in args when a.length>0)
        else "Unknown command '#{cmd}'. Enter 'help' for a list of commands."
      catch e
        controller.message e.toString(), 'error'
    tabComplete: tabComplete
    autofocus: false
    animateScroll: true
    promptHistory: true
    welcomeMessage: """
      Welcome to Doppio! You may wish to try the following Java programs:
        java classes/test/FileRead
        java classes/demo/Fib <num>
        java classes/demo/Chatterbot
        java classes/demo/RegexTestHarness
        java classes/demo/GzipDemo c Hello.txt hello.gz (compress)
        java classes/demo/GzipDemo d hello.gz hello.tmp (decompress)
        java classes/demo/DiffPrint Hello.txt hello.tmp

      We support the stock Sun Java Compiler:
        javac classes/test/FileRead.java
        javac classes/demo/Fib.java

      (Note: if you edit a program and recompile with javac, you'll need
        to run 'clear_cache' to see your changes when you run the program.)

      We can run Rhino, the Java-based JS engine:
        rhino

      Text files can be edited by typing `edit [filename]`.

      You can also upload your own files using the uploader above the top-right
      corner of the console.

      Enter 'help' for full a list of commands. Ctrl-D is EOF.

      Doppio has been tested with the latest versions of the following desktop browsers:
        Chrome, Safari, Firefox, Opera, Internet Explorer 10, and Internet Explorer 9.
      """

  stdout = (str) -> controller.message str, '', true # noreprompt

  user_input = (resume) ->
    oldPrompt = controller.promptLabel
    controller.promptLabel = ''
    controller.reprompt()
    oldHandle = controller.commandHandle
    controller.commandHandle = (line) ->
      controller.commandHandle = oldHandle
      controller.promptLabel = oldPrompt
      if line == '\0' # EOF
        resume 0
      else
        line += "\n" # so BufferedReader knows it has a full line
        resume (line.charCodeAt(i) for __,i in line)

  close_editor = ->
    $('#ide').fadeOut 'fast', ->
      $('#console').fadeIn('fast').click() # click to restore focus

  $('#save_btn').click (e) ->
    fname = $('#filename').val()
    contents = editor.getSession().getValue()
    contents += '\n' unless contents[contents.length-1] == '\n'
    node.fs.writeFile fname, contents, (err) ->
      if err
        controller.message "File could not be saved: #{err}", 'error'
      else
        controller.message("File saved as '#{fname}'.", 'success')
      close_editor()
      e.preventDefault()

  $('#close_btn').click (e) -> close_editor(); e.preventDefault()
  bs_cl = new ClassLoader.BootstrapClassLoader(read_classfile)
  preload()

# helper function for 'ls'
read_dir = (dir, pretty=true, columns=true, cb) ->
  node.fs.readdir dir, (err, contents) ->
    if err or contents.length is 0 then return cb('')
    contents = contents.sort()
    return cb(contents.join('\n')) unless pretty
    pretty_list = []
    max_len = 0
    i = 0
    next_content = ->
      c = contents[i++]
      node.fs.stat (dir+'/'+c), (err, stat) ->
        if stat.isDirectory()
          c += '/'
        max_len = c.length if c.length > max_len
        pretty_list.push c
        unless i is contents.length
          next_content()
          return
        return cb(pretty_list.join('\n')) unless columns
        # XXX: assumes 100-char lines
        num_cols = (100/(max_len+1))|0
        col_size = Math.ceil(pretty_list.length/num_cols)
        column_list = []
        for [1..num_cols]
          column_list.push pretty_list.splice(0, col_size)
        row_list = []
        rpad = (str,len) -> str + Array(len - str.length + 1).join(' ')
        for i in [0...col_size]
          row = (rpad(col[i],max_len+1) for col in column_list when col[i]?)
          row_list.push row.join('')
        cb(row_list.join('\n'))
    next_content()

commands =
  ecj: (args, cb) ->
    jvm.set_classpath "#{sys_path}/vendor/classes/", './'
    rs = new runtime.RuntimeState(stdout, user_input, bs_cl)
    # HACK: -D args unsupported by the console.
    jvm.system_properties['jdt.compiler.useSingleThread'] = true
    jvm.run_class rs, 'org/eclipse/jdt/internal/compiler/batch/Main', args, ->
        # HACK: remove any classes that just got compiled from the class cache
        for c in args when c.match /\.java$/
          bs_cl.remove_class(util.int_classname(c.slice(0,-5)))
        jvm.reset_system_properties()
        controller.reprompt()
    return null  # no reprompt, because we handle it ourselves
  javac: (args, cb) ->
    jvm.set_classpath "#{sys_path}/vendor/classes/", "./:#{sys_path}/"
    rs = new runtime.RuntimeState(stdout, user_input, bs_cl)
    jvm.run_class rs, 'classes/util/Javac', args, ->
        # HACK: remove any classes that just got compiled from the class cache
        for c in args when c.match /\.java$/
          bs_cl.remove_class(util.int_classname(c.slice(0,-5)))
        controller.reprompt()
    return null  # no reprompt, because we handle it ourselves
  java: (args, cb) ->
    jvm.dump_state = false
    # XXX: dump-state support
    for i in [0...args.length]
      if args[i] is '-Xdump-state'
        jvm.dump_state = true
        args.splice i, 1
        break

    if !args[0]? or (args[0] == '-classpath' and args.length < 3)
      return "Usage: java [-classpath path1:path2...] class [args...]"
    if args[0] == '-classpath'
      jvm.set_classpath "#{sys_path}/vendor/classes/", args[1]
      class_name = args[2]
      class_args = args[3..]
    else
      jvm.set_classpath "#{sys_path}/vendor/classes/", './'
      class_name = args[0]
      class_args = args[1..]
    rs = new runtime.RuntimeState(stdout, user_input, bs_cl)
    jvm.run_class(rs, class_name, class_args, -> controller.reprompt())
    return null  # no reprompt, because we handle it ourselves
  test: (args) ->
    return "Usage: test all|[class(es) to test]" unless args[0]?
    # method signature is:
    # run_tests(args,stdout,hide_diffs,quiet,keep_going,done_callback)
    if args[0] == 'all'
      testing.run_tests [], stdout, true, false, true, -> controller.reprompt()
    else
      testing.run_tests args, stdout, false, false, true, -> controller.reprompt()
    return null
  javap: (args) ->
    return "Usage: javap class" unless args[0]?
    node.fs.readFile "#{args[0]}.class", (err, buf) ->
      if err
        controller.message "Could not find class '#{args[0]}'.",'error'
      else
        controller.message(disassembler.disassemble(process_bytecode(buf)), 'success')
    return null
  rhino: (args, cb) ->
    jvm.set_classpath "#{sys_path}/vendor/classes/", './'
    rs = new runtime.RuntimeState(stdout, user_input, bs_cl)
    jvm.run_class(rs, 'com/sun/tools/script/shell/Main', args, -> controller.reprompt())
    return null  # no reprompt, because we handle it ourselves
  list_cache: ->
    cached_classes = bs_cl.get_loaded_class_list(true)
    '  ' + cached_classes.sort().join('\n  ')
  # Reset the bootstrap classloader
  clear_cache: ->
    bs_cl = new ClassLoader.BootstrapClassLoader(read_classfile)
    return true
  ls: (args) ->
    if args.length == 0
      read_dir '.', null, null, (list) ->
        controller.message list, 'success'
    else if args.length == 1
      read_dir args[0], null, null, (list) ->
        controller.message list, 'success'
    else
      i = 0
      read_next_dir = ->
        read_dir args[i++], null, null, (list) ->
          controller.message "#{d}:\n#{list}\n\n", 'success', true
          if i is args.length then return controller.reprompt()
          read_next_dir()
      read_next_dir()
    return null
  edit: (args) ->
    startEditor = (data) ->
      $('#console').fadeOut 'fast', ->
        $('#filename').val args[0]
        $('#ide').fadeIn('fast')
        # initialize the editor. technically we only need to do this once, but more
        # than once is fine too
        editor = ace.edit('source')
        editor.setTheme 'ace/theme/twilight'
        if not args[0]? or args[0].split('.')[1] is 'java'
          JavaMode = require("ace/mode/java").Mode
          editor.getSession().setMode(new JavaMode)
        else
          TextMode = require("ace/mode/text").Mode
          editor.getSession().setMode(new TextMode)
        editor.getSession().setValue(data)
    if args[0]?
      node.fs.readFile args[0], 'utf8', (err, data) ->
        if err then data = defaultFile
        startEditor data
        controller.reprompt()
      return null
    else
      startEditor defaultFile
      return true
  cat: (args) ->
    fname = args[0]
    return "Usage: cat <file>" unless fname?
    node.fs.readFile fname, 'utf8', (err, data) ->
      if err
        controller.message "Could not open file #{fname}: #{err}", 'error'
      else
        controller.message data
    return null
  mv: (args) ->
    if args.length < 2 then return "Usage: mv <from-file> <to-file>"
    node.fs.rename args[0], args[1], (err) ->
      if err then controller.message "Could not rename #{args[0]} to #{args[1]}: #{err}", 'error', true
      controller.reprompt()
    return null
  cd: (args) ->
    if args.length > 1 then return "Usage: cd <directory>"
    if args.length == 0 then args.push("~")
    # Verify path exits before going there. chdir does not verify that the
    # directory exists.
    node.fs.exists args[0], (doesExist) ->
      if doesExist
        node.process.chdir(args[0])
      else
        controller.message "Directory #{args[0]} does not exist.\n", 'error', true
      controller.reprompt()
    return null
  rm: (args) ->
    return "Usage: rm <file>" unless args[0]?
    if args[0] == '*'
      node.fs.readdir '.', (err, fnames) ->
        if err
          controller.message "Could not remove '.': #{err}", 'error'
        else
          for fname in fnames
            completed = 0
            node.fs.stat fname, (err, fstat) ->
              if err
                controller.message "Could not remove '.': #{err}", 'error'
              else if fstat.is_directory
                controller.message "ERROR: '#{fname}' is a directory.", 'error'
              else
                node.fs.unlink fname, (err) ->
                  if err then controller.message "Could not remove file: #{err}", true
                  if ++completed is fname.length then controller.reprompt()
    else node.fs.unlink args[0], (err) ->
      if err then controller.message "Could not remove file: #{err}", true
      controller.reprompt()
    return null
  emacs: -> "Try 'vim'."
  vim: -> "Try 'emacs'."
  time: (args) ->
    start = (new Date).getTime()
    console.profile args[0]
    controller.onreprompt = ->
      controller.onreprompt = null
      console.profileEnd()
      end = (new Date).getTime()
      controller.message "\nCommand took a total of #{end-start}ms to run.\n", '', true
    commands[args.shift()](args)
  profile: (args) ->
    count = 0
    runs = 5
    duration = 0
    time_once = ->
      start = (new Date).getTime()
      controller.onreprompt = ->
        unless count < runs
          controller.onreprompt = null
          controller.message "\n#{args[0]} took an average of #{duration/runs}ms.\n", '', true
          return
        end = (new Date).getTime()
        if count++ == 0 # first one to warm the cache
          return time_once()
        duration += end - start
        time_once()
      commands[args.shift()](args)
    time_once()
  help: (args) ->
    """
    Ctrl-D is EOF.

    Java-related commands:
      javac <source file>    -- Invoke the Java 6 compiler.
      java <class> [args...] -- Run with command-line arguments.
      javap <class>          -- Display disassembly.
      time                   -- Measure how long it takes to run a command.
      rhino                  -- Run Rhino, the Java-based JavaScript engine.

    File management:
      cat <file>             -- Display a file in the console.
      edit <file>            -- Edit a file.
      ls <dir>               -- List files.
      mv <src> <dst>         -- Move / rename a file.
      rm <file>              -- Delete a file.
      cd <dir>               -- Change current directory.

    Cache management:
      list_cache             -- List the cached class files.
      clear_cache            -- Clear the cached class files.
    """

tabComplete = ->
  promptText = controller.promptText()
  args = promptText.split /\s+/
  prefix = longestCommmonPrefix(getCompletions(args))
  return if prefix == ''  # TODO: if we're tab-completing a blank, show all options
  # delete existing text so we can do case correction
  promptText = promptText.substr(0, promptText.length - util.last(args).length)
  controller.promptText(promptText + prefix)

getCompletions = (args) ->
  if args.length is 1 then commandCompletions args[0]
  else if args[0] is 'time' then getCompletions(args[1..])
  else fileNameCompletions args[0], args

commandCompletions = (cmd) ->
  (name for name of commands when name.substr(0, cmd.length) is cmd)

fileNameCompletions = (cmd, args) ->
  validExtension = (fname) ->
    dot = fname.lastIndexOf('.')
    ext = if dot is -1 then '' else fname.slice(dot+1)
    if cmd is 'javac' then ext is 'java'
    else if cmd is 'javap' or cmd is 'java' then ext is 'class'
    else true
  chopExt = args.length == 2 and (cmd is 'javap' or cmd is 'java')
  toComplete = util.last(args)
  lastSlash = toComplete.lastIndexOf('/')
  if lastSlash >= 0
    dirPfx = toComplete.slice(0, lastSlash+1)
    searchPfx = toComplete.slice(lastSlash+1)
  else
    dirPfx = ''
    searchPfx = toComplete
  try
    dirList = node.fs.readdirSync(if dirPfx == '' then '.' else dirPfx)
    # Slight cheat.
    dirList.push('..')
    dirList.push('.')
  catch e
    return []

  completions = []
  for item in dirList
    isDir = node.fs.statSync(dirPfx + item)?.isDirectory()
    continue unless validExtension(item) or isDir
    if item.slice(0, searchPfx.length) == searchPfx
      if isDir
        completions.push(dirPfx + item + '/')
      else if cmd != 'cd'
        completions.push(dirPfx + (if chopExt then item.split('.',1)[0] else item))
  completions

# use the awesome greedy regex hack, from http://stackoverflow.com/a/1922153/10601
longestCommmonPrefix = (lst) -> lst.join(' ').match(/^(\S*)\S*(?: \1\S*)*$/i)[1]

defaultFile =
  """
  class Test {
    public static void main(String[] args) {
      // enter code here
    }
  }
  """
