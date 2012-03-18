# **Docco** is a quick-and-dirty, few-hundred-line-long, literate-programming-style
# documentation generator. It produces HTML
# that displays your comments alongside your code. Comments are passed through
# [Markdown](http://daringfireball.net/projects/markdown/syntax), and code is
# passed through [Pygments](http://pygments.org/) syntax highlighting.
# This page is the result of running Docco against its own source file.
#
# If you install Docco, you can run it from the command-line:
#
#     docco src/*.coffee
#
# ...will generate an HTML documentation page for each of the named source files, 
# with a menu linking to the other pages, saving it into a `docs` folder.
#
# The [source for Docco](http://github.com/jashkenas/docco) is available on GitHub,
# and released under the MIT license.
#
# To install Docco, first make sure you have [Node.js](http://nodejs.org/),
# [Pygments](http://pygments.org/) (install the latest dev version of Pygments
# from [its Mercurial repo](http://dev.pocoo.org/hg/pygments-main)). Then, with NPM:
#
#     sudo npm install -g docco
#
# Docco can be used to process CoffeeScript, JavaScript, Ruby, Python, or TeX files.
# By default only single-line comments are processed, block comments may be included
# by passing the `-b` flag to Docco.
#
#### Partners in Crime:
#
# * If **Node.js** doesn't run on your platform, or you'd prefer a more 
# convenient package, get [Ryan Tomayko](http://github.com/rtomayko)'s 
# [Rocco](http://rtomayko.github.com/rocco/rocco.html), the Ruby port that's 
# available as a gem. 
# 
# * If you're writing shell scripts, try
# [Shocco](http://rtomayko.github.com/shocco/), a port for the **POSIX shell**,
# also by Mr. Tomayko.
# 
# * If Python's more your speed, take a look at 
# [Nick Fitzgerald](http://github.com/fitzgen)'s [Pycco](http://fitzgen.github.com/pycco/). 
#
# * For **Clojure** fans, [Fogus](http://blog.fogus.me/)'s 
# [Marginalia](http://fogus.me/fun/marginalia/) is a bit of a departure from 
# "quick-and-dirty", but it'll get the job done.
#
# * **Lua** enthusiasts can get their fix with 
# [Robert Gieseke](https://github.com/rgieseke)'s [Locco](http://rgieseke.github.com/locco/).
# 
# * And if you happen to be a **.NET**
# aficionado, check out [Don Wilson](https://github.com/dontangg)'s 
# [Nocco](http://dontangg.github.com/nocco/).

#### Main Documentation Generation Functions

# Generate the documentation for a source file by reading it in, splitting it
# up into comment/code sections, highlighting them for the appropriate language,
# and merging them into an HTML template.
generate_documentation = (source, config, callback) ->
  fs.readFile source, "utf-8", (error, code) ->
    throw error if error
    if not get_language source
      console.error "error: skipping unknown file type -> #{source}"
      return callback()
    sections = parse source, code, config.blocks
    highlight source, sections, ->
      generate_html source, sections, config
      callback()

# Given a string of source code, parse out each comment and the code that
# follows it, and create an individual **section** for it.
# Sections take the form:
#
#     {
#       docs_text: ...
#       docs_html: ...
#       code_text: ...
#       code_html: ...
#     }
#
parse = (source, code, blocks=false) ->
  lines    = code.split '\n'
  sections = []
  language = get_language source
  has_code = docs_text = code_text = ''
  in_block = false

  save = (docs, code) ->
    sections.push docs_text: docs, code_text: code

  # Iterate over the source lines, and separate out single/block
  # comments from code chunks.
  for line in lines
    
    # If we're not in a block comment, and find a match for the start 
    # of one, eat the tokens, and note that we're now in a block.
    if not in_block and blocks and language.blocks and line.match(language.enter)
      line = line.replace(language.enter, '')
      in_block = true
      
    # Process the line, marking it as docs if we're in a block comment, 
    # or we find a single-line comment marker.
    single = line.match(language.comment_matcher)
    if in_block or (not line.match(language.comment_filter) and single)
      
      # If we have code text, and we're entering a comment, store off
      # the current docs and code, then start a new section.
      if has_code
        save docs_text, code_text
        has_code = docs_text = code_text = ''

      # If there's a single comment, and we're not in a block, eat the
      # comment token.
      line = line.replace(language.comment_matcher, '') if single and not in_block

      # If we're in a block, and we find the end of it in the line, eat
      # the end token, and note that we're no longer in the block.
      if in_block and line.match(language.exit)
        line = line.replace(language.exit, '')
        in_block = false        
      
      docs_text += line + '\n'
    else
      has_code = yes
      code_text += line + '\n'
      
  # Save the final section, if any, and return the sections array. 
  save docs_text, code_text if code_text != '' and docs_text != ''
  sections

# Highlights a single chunk of code, using **Pygments** over stdio,
# and runs the text of its corresponding comment through **Markdown**, using
# [Showdown.js](http://attacklab.net/showdown/).
#
# We process the entire file in a single call to Pygments by inserting little
# marker comments between each section and then splitting the result string
# wherever our markers occur.
highlight = (source, sections, callback) ->
  language = get_language source
  pygments = spawn 'pygmentize', ['-l', language.name, '-f', 'html', '-O', 'encoding=utf-8,tabsize=2']
  output   = ''
  
  pygments.stderr.addListener 'data',  (error)  ->
    console.error error.toString() if error
    
  pygments.stdin.addListener 'error',  (error)  ->
    console.error "Could not use Pygments to highlight the source."
    process.exit 1
    
  pygments.stdout.addListener 'data', (result) ->
    output += result if result
    
  pygments.addListener 'exit', ->
    output = output.replace(highlight_start, '').replace(highlight_end, '')
    fragments = output.split language.divider_html
    for section, i in sections
      section.code_html = highlight_start + fragments[i] + highlight_end
      section.docs_html = new showdown.converter().makeHtml section.docs_text
    callback()
    
  if pygments.stdin.writable
    pygments.stdin.write((section.code_text for section in sections).join(language.divider_text))
    pygments.stdin.end()
  
# Once all of the code is finished highlighting, we can generate the HTML file
# and write out the documentation. Pass the completed sections into the template
# found in `resources/docco.jst`
generate_html = (source, sections, config) ->
  # Compute the destination HTML path for an input source file path. If the source
  # is `lib/example.coffee`, the HTML will be at `docs/example.html`
  destination = (filepath) ->
    path.join(config.output, path.basename(filepath, path.extname(filepath)) + '.html')
    
  title = path.basename source
  dest  = destination source
  html  = config.docco_template {
    title      : title, 
    sections   : sections, 
    sources    : config.sources, 
    path       : path, 
    destination: destination
    css        : path.basename(config.css)
  }
  console.log "docco: #{source} -> #{dest}"
  fs.writeFileSync dest, html

#### Helpers & Setup

# Require our external dependencies, including **Showdown.js**
# (the JavaScript implementation of Markdown).
fs       = require 'fs'
path     = require 'path'
showdown = require('showdown').Showdown
{spawn, exec} = require 'child_process'
commander = require 'commander'

# A list of the languages that Docco supports, mapping the file extension to
# the name of the Pygments lexer and the symbol that indicates a comment. To
# add another language to Docco's repertoire, add it here.
languages =
  '.coffee':
    name: 'coffee-script', symbol: '#', enter: /^\s*#{3}(?!#)/, exit: /#{3}(?!#)\s*$/
  '.js':
    name: 'javascript', symbol: '//', enter: /\/\*\s*/, exit: /\s*\*\//
  '.rb':
    name: 'ruby', symbol: '#', enter: /^=begin$/, exit: /^=end$/
  '.py':
    name: 'python', symbol: '#', enter: /"""/, exit: /"""/
  '.tex':
    name: 'tex', symbol: '%', enter: /\\begin{comment}/, exit: /\\end{comment}/
  '.latex':
    name: 'tex', symbol: '%', enter: /\\begin{comment}/, exit: /\\end{comment}/
  '.c':
    name: 'c', symbol: '//'
  '.h':
    name: 'c', symbol: '//'

# Build out the appropriate matchers and delimiters for each language.
for ext, l of languages

  # Does the line begin with a comment?
  l.comment_matcher = new RegExp('^\\s*' + l.symbol + '\\s?')

  # Support block comment parsing?
  l.blocks = (l.enter and l.exit)

  # Ignore [hashbangs](http://en.wikipedia.org/wiki/Shebang_(Unix\))
  # and interpolations...
  l.comment_filter = new RegExp('(^#![/]|^\\s*#\\{)')

  # The dividing token we feed into Pygments, to delimit the boundaries between
  # sections.
  l.divider_text = '\n' + l.symbol + 'DIVIDER\n'

  # The mirror of `divider_text` that we expect Pygments to return. We can split
  # on this to recover the original sections.
  # Note: the class is "c" for Python and "c1" for the other languages
  l.divider_html = new RegExp('\\n*<span class="c1?">' + l.symbol + 'DIVIDER<\\/span>\\n*')

# Get the current language we're documenting, based on the extension.
get_language = (source) -> languages[path.extname(source)]

# Ensure that the destination directory exists.
ensure_directory = (dir, callback) ->
  exec "mkdir -p #{dir}", -> callback()

# Micro-templating, originally by John Resig, borrowed by way of
# [Underscore.js](http://documentcloud.github.com/underscore/).
template = (str) ->
  new Function 'obj',
    'var p=[],print=function(){p.push.apply(p,arguments);};' +
    'with(obj){p.push(\'' +
    str.replace(/[\r\t\n]/g, " ")
       .replace(/'(?=[^<]*%>)/g,"\t")
       .split("'").join("\\'")
       .split("\t").join("'")
       .replace(/<%=(.+?)%>/g, "',$1,'")
       .split('<%').join("');")
       .split('%>').join("p.push('") +
       "');}return p.join('');"

# The start of each Pygments highlight block.
highlight_start = '<div class="highlight"><pre>'

# The end of each Pygments highlight block.
highlight_end   = '</pre></div>'

#### Public API

# Docco exports a basic public API for usage in other applications.
# A simple usage might look like this
#
#     Docco = require('docco')
#     
#     sources = 
#       "src/index.coffee"
#       "src/plugins/*.coffee"
#       "src/web/*.py"
#     
#     options = 
#       template : "src/templates/docs/myproject.jst"
#       output   : "web/docs"
#       css      : "src/templates/docs/myproject.docs.css"
#       blocks   : true
#     
#     Docco.document sources, options, ->
#       console.log("Docco documentation complete.")
#     

# Extract the docco version from `package.json`
version = JSON.parse(fs.readFileSync("#{__dirname}/../package.json")).version

# Default configuration options.
defaults =
  template: "#{__dirname}/../resources/docco.jst"
  css     : "#{__dirname}/../resources/docco.css"
  output  : "docs/"
  blocks  : false


# ### Run from Commandline
  
# Run Docco from a set of command line arguments.  
#  
# 1. Parse command line using [Commander JS](https://github.com/visionmedia/commander.js).
# 2. Document sources, or print the usage help if none are specified.
run = (args=process.argv) ->
  commander.version(version)
    .usage("[options] <file_pattern ...>")
    .option("-c, --css [file]","use a custom css file",defaults.css)
    .option("-o, --output [path]","use a custom output path",defaults.output)
    .option("-t, --template [file]","use a custom .jst template",defaults.template)
    .option("-b, --blocks","parse block comments where available",defaults.blocks)
    .parse(args)
    .name = "docco"
  if commander.args.length
    document(commander.args.slice(),commander)
  else
    console.log commander.helpInformation()

# ### Document Sources

# Run Docco over a list of `sources` with the given `options`.
#  
# 1. Construct config to use by taking `defaults` first, then  merging in `options`
# 2. Generate the source list to iterate over and document. 
# 3. Load the specified template and css files.
# 4. Ensure the output path is created, write out the CSS style file, 
# document and output HTML for each source, and finally invoke the
# completion callback, if it is specified.
document = (sources,options={},callback=null) ->
  config = {}
  config[key] = defaults[key] for key,value of defaults
  config[key] = value for key,value of options if key of defaults

  files = []
  files = files.concat(exports.resolve_source(src)) for src in sources
  config.sources = files
  
  config.docco_template = template fs.readFileSync(config.template).toString()
  docco_styles = fs.readFileSync(config.css).toString()

  ensure_directory config.output, ->
    fs.writeFileSync path.join(config.output,path.basename(config.css)), docco_styles
    files = config.sources.slice()
    next_file = -> 
      callback() if callback? and not files.length
      generate_documentation files.shift(), config, next_file if files.length
    next_file()

# ### Resolve Wildcard Source Inputs

# Resolve a wildcard `source` input to the files it matches.
#
# 1. If the input contains no wildcard characters, just return it.
# 2. Convert the wildcard match to a regular expression, and return
# an array of files in the path that match it.
resolve_source = (source) ->
  return source if not source.match(/([\*\?])/)
  regex_str = path.basename(source)
    .replace(/\./g, "\\$&")
    .replace(/\*/,".*")
    .replace(/\?/,".")
  regex = new RegExp('^(' + regex_str + ')$')
  file_path = path.dirname(source)
  files = fs.readdirSync file_path
  return (path.join(file_path,file) for file in files when file.match regex)

# ### Exports

# Information about docco, and functions for programatic usage.

exports[key] = value for key, value of {
  run           : run
  document      : document
  parse         : parse
  resolve_source: resolve_source
  version       : version
  defaults      : defaults
  languages     : languages
}
