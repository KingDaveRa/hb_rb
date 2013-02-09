#!/usr/bin/ruby

require 'optparse'

class Handbrake
  require 'fileutils'
  require 'lib/tools.rb'
  include Tools

  L = Tools::Loggers.console()

  HANDBRAKE_CLI = File.expand_path("tools/handbrake/#{Tools::OS::platform()}/HandBrakeCLI")
  raise "#{HANDBRAKE_CLI} does not exist" if not Tools::OS::command2?(HANDBRAKE_CLI)

  # https://forum.handbrake.fr/viewtopic.php?f=6&t=19426
  X264_PRESETS = {}
  X264_PRESETS["ultrafast"] = "ref=1:bframes=0:cabac=0:8x8dct=0:weightp=0:me=dia:subq=0:rc-lookahead=0:mbtree=0:analyse=none:trellis=0:aq-mode=0:scenecut=0:no-deblock=1"
  X264_PRESETS["superfast"] = "ref=1:weightp=1:me=dia:subq=1:rc-lookahead=0:mbtree=0:analyse=i4x4,i8x8:trellis=0"
  X264_PRESETS["veryfast"] = "ref=1:weightp=1:subq=2:rc-lookahead=10:trellis=0"
  X264_PRESETS["faster"] = "ref=2:mixed-refs=0:weightp=1:subq=4:rc-lookahead=20"
  X264_PRESETS["fast"] = "ref=2:weightp=1:subq=6:rc-lookahead=30"
  X264_PRESETS["medium"] = ""  
  X264_PRESETS["slow"] = "ref=5:b-adapt=2:direct=auto:me=umh:subq=8:rc-lookahead=50"
  X264_PRESETS["slower"] = "ref=8:b-adapt=2:direct=auto:me=umh:subq=9:rc-lookahead=60:analyse=all:trellis=2"
  X264_PRESETS["veryslow"] = "ref=16:bframes=8:b-adapt=2:direct=auto:me=umh:merange=24:subq=10:rc-lookahead=60:analyse=all:trellis=2"
  X264_PRESETS["placebo"] = "ref=16:bframes=16:b-adapt=2:direct=auto:me=tesa:merange=24:subq=10:rc-lookahead=60:analyse=all:trellis=2:no-fast-pskip=1"

  def self.readInfo(options)
    path = File.expand_path(options.input)
    cmd = "\"#{HANDBRAKE_CLI}\" -i \"#{path}\" --scan -t 0 2>&1"
    output = %x[#{cmd}]

    dvd_title_pattern = /libdvdnav: DVD Title: (.*)/
    dvd_alt_title_pattern = /libdvdnav: DVD Title \(Alternative\): (.*)/
    dvd_serial_pattern = /libdvdnav: DVD Serial Number: (.*)/
    main_feature_pattern = /\+ Main Feature/

    title_blocks_pattern = /\+ vts .*, ttn .*, cells .* \(([0-9]+) blocks\)/
    title_pattern = /\+ title ([0-9]+):/
    title_info_pattern = /\+ size: ([0-9]+x[0-9]+).*, ([0-9.]+) fps/
    in_audio_section_pattern = /\+ audio tracks:/
    audio_pattern = /\+ ([0-9]+), (.*?) \(iso639-2: (.*?)\), ([0-9]+Hz), ([0-9]+bps)/
    file_audio_pattern = /\+ ([0-9]+), (.*?) \(iso639-2: (.*?)\)/
    in_subtitle_section_pattern = /\+ subtitles:/
    subtitle_pattern = /\+ ([0-9]+), (.*?) \(iso639-2: (.*?)\)/
    duration_pattern = /\+ duration: (.*)/
    chapter_pattern = /\+ ([0-9]+): cells (.*), ([0-9]+) blocks, duration (.*)/

    source = MovieSource.new(path)
    title = nil

    in_audio_section = false
    in_subtitle_section = false
    output.each_line do |line|
      puts "out> #{line}" if options.debug and options.verbose

      if line.match(dvd_title_pattern)
        puts "> match: dvd-title" if options.debug and options.verbose
        info = line.scan(dvd_title_pattern)[0]
        source.title = info[0].strip
      elsif line.match(dvd_alt_title_pattern)
        puts "> match: dvd-alt-title" if options.debug and options.verbose
        info = line.scan(dvd_alt_title_pattern)[0]
        source.title_alt = info[0].strip
      elsif line.match(dvd_serial_pattern)
        puts "> match: dvd-serial" if options.debug and options.verbose
        info = line.scan(dvd_serial_pattern)[0]
        source.serial = info[0].strip
      elsif line.match(in_audio_section_pattern)
        in_audio_section = true
      elsif line.match(in_subtitle_section_pattern)
        in_subtitle_section = true
      elsif line.match(title_pattern)
        puts "> match: title" if options.debug and options.verbose
        info = line.scan(title_pattern)[0]
        title = Title.new(info[0])
        source.titles().push(title)
      end

      next if title.nil?

      if line.match(main_feature_pattern)
        puts "> match: main-feature" if options.debug and options.verbose
        title.mainFeature = true
      elsif line.match(title_blocks_pattern)
        puts "> match: blocks" if options.debug and options.verbose
        info = line.scan(title_blocks_pattern)[0]
        title.blocks = info[0].to_i
      elsif line.match(title_info_pattern)
        puts "> match: info" if options.debug and options.verbose
        info = line.scan(title_info_pattern)[0]
        title.size = info[0]
        title.fps = info[1]
      elsif line.match(duration_pattern)
        puts "> match: duration" if options.debug and options.verbose
        info = line.scan(duration_pattern)[0]
        title.duration = info[0]
      elsif line.match(chapter_pattern)
        puts "> match: chapter" if options.debug and options.verbose
        info = line.scan(chapter_pattern)[0]
        chapter = Chapter.new(info[0])
        chapter.cells = info[1]
        chapter.blocks = info[2]
        chapter.duration = info[3]
        title.chapters().push(chapter)
      elsif in_audio_section and line.match(audio_pattern)
        puts "> match: audio" if options.debug and options.verbose
        info = line.scan(audio_pattern)[0]
        track = AudioTrack.new(info[0], info[1])
        if info[1].match(/\((.*?)\)\s*\((.*?)\)\s*\((.*?)\)\s*/)
          info2 = info[1].scan(/\((.*?)\)\s*\((.*?)\)\s*\((.*?)\)\s*/)[0]
          track.codec = info2[0]
          track.comment = info2[1]
          track.channels = info2[2]
        elsif info[1].match(/\((.*?)\)\s*\((.*?)\)\s*/)
          info2 = info[1].scan(/\((.*?)\)\s*\((.*?)\)\s*/)[0]
          track.codec = info2[0]
          track.channels = info2[1]
        end
        track.lang = info[2]
        track.rate = info[3]
        track.bitrate = info[4]
        title.audioTracks().push(track)
      elsif in_audio_section and line.match(file_audio_pattern)
        puts "> match: audio" if options.debug and options.verbose
        info = line.scan(file_audio_pattern)[0]
        track = AudioTrack.new(info[0], info[1])
        if info[1].match(/\((.*?)\)\s*\((.*?)\)\s*\((.*?)\)\s*/)
          info2 = info[1].scan(/\((.*?)\)\s*\((.*?)\)\s*\((.*?)\)\s*/)[0]
          track.codec = info2[0]
          track.comment = info2[1]
          track.channels = info2[2]
        elsif info[1].match(/\((.*?)\)\s*\((.*?)\)\s*/)
          info2 = info[1].scan(/\((.*?)\)\s*\((.*?)\)\s*/)[0]
          track.codec = info2[0]
          track.channels = info2[1]
        end
        track.lang = info[2]
        title.audioTracks().push(track)
      elsif in_subtitle_section and line.match(subtitle_pattern)
        puts "> match: subtitle" if options.debug and options.verbose
        info = line.scan(subtitle_pattern)[0]
        subtitle = Subtitle.new(info[0], info[1], info[2])
        if info[1].match(/\((.*?)\)/)
          info2 = info[1].scan(/\((.*?)\)/)[0]
          subtitle.comment = info2[0]
        end
        title.subtitles().push(subtitle)
      end
    end
    source.titles().first().mainFeature = true if source.titles().size == 1
    return source
  end

  def self.convert(options, source, titleMatcher, audioMatcher, subtitleMatcher)
    converted = []
    output = options.output
    preset = options.preset
    mainFeatureOnly = options.mainFeatureOnly || false
    force = options.force || false
    skipDuplicates = options.skipDuplicates || false
    verbose = options.verbose || false
    debug = options.debug || false
    mixdownOnly = options.mixdownOnly || false
    copyOnly = options.copyOnly || false
    allTracksPerLanguage = options.allTracksPerLanguage || false
    skipCommentaries = options.skipCommentaries || false
    xtraArgs = options.xtra_args
    minLength = TimeTool::timeToSeconds(options.minLength)
    maxLength = TimeTool::timeToSeconds(options.maxLength)
    ipodCompatibility = options.ipodCompatibility || false
    enableAutocrop = options.enableAutocrop || false
    x264preset = options.x264preset

    source.titles().each do |title|
      L.info("checking #{title}") if verbose
      next if not (titleMatcher.matches(title) and (not mainFeatureOnly or (mainFeatureOnly and title.mainFeature)))

      tracks = audioMatcher.filter(title.audioTracks, false, !allTracksPerLanguage)
      subtitles = subtitleMatcher.filter(title.subtitles, false, !allTracksPerLanguage)

      duration = TimeTool::timeToSeconds(title.duration)
      if minLength >= 0 and duration < minLength
        L.info("skipping title because it's duration is too short (#{TimeTool::secondsToTime(minLength)} <= #{TimeTool::secondsToTime(duration)} <= #{TimeTool::secondsToTime(maxLength)})") if verbose
        next
      end
      if maxLength >= 0 and duration > maxLength
        L.info("skipping title because it's duration is too long (#{TimeTool::secondsToTime(minLength)} <= #{TimeTool::secondsToTime(duration)} <= #{TimeTool::secondsToTime(maxLength)})") if verbose
        next
      end
      if tracks.empty?() or tracks.length < audioMatcher.allowed().length
        L.info("skipping title because it contains not all wanted audio-tracks (available: #{title.audioTracks})") if verbose
        next
      end
      if skipDuplicates and title.blocks() >= 0 and converted.include?(title.blocks())
        L.info("skipping because source contains it twice") if verbose
        next
      end

      outputFile = File.expand_path(output)
      outputFile = outputFile.gsub("#pos#", "%02d" % title.pos)
      outputFile = outputFile.gsub("#size#", title.size)
      outputFile = outputFile.gsub("#fps#", title.fps)
      outputFile = outputFile.gsub("#ts#", Time.new.strftime("%Y-%m-%d_%H_%M_%S"))
      outputFile = outputFile.gsub("#title#", source.name)
      if File.exists?(outputFile) and not force
        L.info("skipping title because \"#{outputFile}\" already exists") if verbose
        next
      end
      
      L.info("converting #{title}")

      extra_arguments = xtraArgs
      ext = File.extname(outputFile).downcase
      ismp4 = false
      ismkv = false
      if ext.eql?(".mp4") or ext.eql?(".m4v")
        ismp4 = true
      elsif ext.eql?(".mkv")
        ismkv = true
      else
        raise "error unsupported extension #{ext}"
      end

      command="\"#{HANDBRAKE_CLI}\""
      command << " --input \"#{source.path()}\""
      command << " --output \"#{outputFile}\""
      if not options.chapters.nil?
        command << " --chapters #{options.chapters}"
      end
      command << " --verbose" if verbose
      if not preset.nil? and not preset.empty?
        command << " --preset \"#{preset}\""
      else
        # video
        command << " --encoder x264"
        command << " --quality 20.0"
        #command << " --vb 2500"
        #command << " --two-pass"
        #command << " --turbo"
        x264_quality_opts = nil

        if not x264preset.nil? and X264_PRESETS[x264preset]
          x264_quality_opts = X264_PRESETS[x264preset]
        end

        # append for iPod-compatibility
        if ipodCompatibility and ismp4
          x264_quality_opts = "level=30:bframes=0:weightp=0:cabac=0:8x8dct=0:ref=1:vbv-maxrate=#{vbr}:vbv-bufsize=2500:analyse=all:me=umh:no-fast-pskip=1:psy-rd=0,0:subme=6:trellis=0"

          command << " --ipod-atom"

          if x264_quality_opts.nil?
            x264_quality_opts = ""
          else
            x264_quality_opts << ":"
          end
          x264_quality_opts << "level=30:bframes=0:cabac=0:weightp=0:8x8dct=0"
        end
        # tune encoder
        command << " -x #{x264_quality_opts}" if not x264_quality_opts.nil?

        if ismp4 and not ipodCompatibility
          command << " --large-file"
        end

        if ismp4
          command << " --format mp4"
          command << " --optimize"
        elsif ismkv
          command << " --format mkv"
        end
        command << " --markers"

        # picture settings
        command << " --decomb"
        command << " --detelecine"
        command << " --crop 0:0:0:0" if not enableAutocrop
        if not ipodCompatibility
          command << " --loose-anamorphic"
          command << " --modulus 16"
        end
        # FullHD as Maximum
        #command << " --maxWidth 1920"
        #command << " --maxHeight 1080"

        # audio
        paudio = []
        paencoder = []
        parate = []
        pmixdown = []
        pab = []
        paname = []
        if mixdownOnly
          add_copy_track = false
          add_mixdown_track = true
        elsif copyOnly
          add_copy_track = true
          add_mixdown_track = false
        else
          add_copy_track = true
          add_mixdown_track = true
        end
        tracks.each do |t|
          L.info("checking audio-track #{t}") if debug or verbose
          next if skipCommentaries and t.commentary?
          if add_copy_track
            # copy original track
            paudio << t.pos
            paencoder << "copy"
            parate << "auto"
            pmixdown << "auto"
            pab << "auto"
            paname << "#{t.descr}"
            L.info("adding audio-track: #{t}") if verbose
          end
          if add_mixdown_track
            # add mixdown track (just the first per language)
            paudio << t.pos
            paencoder << "faac"
            parate << "auto"
            pmixdown << "dpl2"
            pab << "160"
            paname << "#{t.descr} (mixdown)"
            L.info("adding mixed down audio-track: #{t}") if verbose
          end
        end
        command << " --audio #{paudio.join(',')}"
        command << " --aencoder #{paencoder.join(',')}"
        command << " --arate #{parate.join(',')}"
        command << " --mixdown #{pmixdown.join(',')}"
        command << " --ab #{pab.join(',')}"
        command << " --aname \"#{paname.join('","')}\""
        command << " --audio-fallback faac"

        # subtitles
        psubtitle = []
        subtitles.each do |s|
          next if skipCommentaries and s.commentary?
          psubtitle << s.pos
        end
        command << " --subtitle #{psubtitle.join(',')}" if not psubtitle.empty?()
      end

      # title (useed by default and if preset is selected)
      command << " --title #{title.pos}"

      # the rest...
      command << " " << extra_arguments if not extra_arguments.nil?() and not extra_arguments.empty?
      command << " 2>&1"

      converted.push(title.blocks())
      if force or (not File.exists?(outputFile) and Dir.glob("#{File.dirname(outputFile)}/*.#{File.basename(outputFile)}").empty?)
        L.info(command)
        if not debug
          parentDir = File.dirname(outputFile)
          FileUtils.mkdir_p(parentDir) unless File.directory?(parentDir)
          system command
          if File.exists?(outputFile)
            size = File.size(outputFile)
            if size >= 0 and size < (1 * 1024 * 1024)
              L.warn("file-size only #{size / 1024} KB - removing file #{File.basename(outputFile)}")
              File.delete(outputFile)
              converted.delete(title.blocks())
            else
              L.info("file #{outputFile} created")
            end
          else
            L.warn("file #{outputFile} not created")
          end
        end
      else
        if File.exists?(outputFile)
          f = outputFile
        else
          f = Dir.glob("#{File.dirname(outputFile)}/*.#{File.basename(outputFile)}").join(", ")
        end
        L.info("skipping title because \"#{f}\" already exists")
      end
    end
  end
end

class Chapter
  attr_accessor :pos, :cells, :blocks, :duration
  def initialize(pos)
    @pos = pos.to_i
    @duration = nil
    @cells = nil
    @blocks = nil
  end

  def to_s
    "#{pos}. #{duration} (cells=#{cells}, blocks=#{blocks})"
  end
end

class Subtitle
  attr_accessor :pos, :descr, :comment, :lang
  def initialize(pos, descr, lang)
    @pos = pos.to_i
    @lang = lang
    @descr = descr
    @comment = nil
  end

  def commentary?()
    return true if @descr.downcase().include?("commentary")
    return false
  end

  def to_s
    "#{pos}. #{descr} (lang=#{lang}, comment=#{comment}, commentary=#{commentary?()})"
  end
end

class AudioTrack
  attr_accessor :pos, :descr, :codec, :comment, :channels, :lang, :rate, :bitrate
  def initialize(pos, descr)
    @pos = pos.to_i
    @descr = descr
    @codec = nil
    @comment = nil
    @channels = nil
    @lang = nil
    @rate = nil
    @bitrate = nil
  end

  def commentary?()
    return true if @descr.downcase().include?("commentary")
    return false
  end

  def to_s
    "#{pos}. #{descr} (codec=#{codec}, channels=#{channels}, lang=#{lang}, comment=#{comment}, rate=#{rate}, bitrate=#{bitrate}, commentary=#{commentary?()})"
  end
end

class Title
  attr_accessor :pos, :audioTracks, :subtitles, :chapters, :size, :fps, :duration, :mainFeature, :blocks
  def initialize(pos)
    @pos = pos.to_i
    @blocks = -1
    @audioTracks = []
    @subtitles = []
    @chapters = []
    @size = nil
    @fps = nil
    @duration = nil
    @mainFeature = false
  end

  def to_s
    "title #{"%02d" % pos}: #{duration}, #{size}, #{fps} fps, main-feature: #{mainFeature()}, blocks: #{blocks}, chapters: #{chapters.length}, audio-tracks: #{audioTracks.collect{|t| t.lang}.join(",")}, subtitles: #{subtitles.collect{|s| s.lang}.join(",")}"
  end
end

class MovieSource
  attr_accessor :title, :title_alt, :serial, :titles, :path
  def initialize(path)
    @titles = []
    @path = path
    @title = nil
    @title_alt = nil
    @serial = nil
  end

  def name(use_alt = false)
    return @title_alt if usable?(@title_alt) and use_alt
    return @title if usable?(@title)
    return File.basename(path()) if usable?(File.basename(path()))
    return "unknown"
  end

  def usable?(str)
    return false if str.nil?
    return false if str.strip.empty?
    return false if str.strip.eql? "unknown"
    return true
  end

  def info
    s = "#{self}"
    titles().each do |t|
      s << "\n#{t}"
      s << "\n  audio-tracks:"
      t.audioTracks().each do |e|
        s << "\n    #{e}"
      end
      s << "\n  subtitles:"
      t.subtitles().each do |e|
        s << "\n    #{e}"
      end
      s << "\n  chapters:"
      t.chapters().each do |c|
        s << "\n    #{c}"
      end
    end
    s
  end

  def to_s
    "#{path} (title=#{title}, title_alt=#{title_alt}, serial=#{serial}, name=#{name()})"
  end
end

class ValueMatcher
  attr_accessor :allowed
  def initialize(allowed)
    @allowed = allowed
  end

  def value(obj)
    raise "method not implemented"
  end

  def matches(obj)
    #puts "#{allowed} #{value(obj)} -> #{allowed().nil? or allowed().include?(value(obj))}"
    allowed().nil? or allowed().include?(value(obj))
  end

  def filter(list, onlyFirst = false, skipDuplicatedValues = true)
    return list if allowed().nil?

    filtered = []
    stack = []
    allowed().each do |a|
      list.each do |e|
        v = value(e)
        if (v == a or v.eql? a) and (!skipDuplicatedValues or !stack.include?(v))
          stack.push v
          filtered.push e
          break if onlyFirst
        end
      end
    end
    return filtered
  end

  def to_s
    "#{@allowed}"
  end
end

class PosMatcher < ValueMatcher
  def value(obj)
    obj.pos
  end
end

class LangMatcher < ValueMatcher
  def value(obj)
    obj.lang
  end
end

def showUsageAndExit(helpText, msg = nil)
  puts helpText
  puts ""
  puts "available place-holders for output-file:"
  puts "  #pos#   - title-number on input-source"
  puts "  #size#  - resolution"
  puts "  #fps#   - frames per second"
  puts "  #ts#    - current timestamp"
  puts "  #title# - source-title (dvd-label, directory-basename, filename)"
  puts
  puts "hints:"
  puts "use raw disk devices (e.g. /dev/rdisk1) to ensure that libdvdnav can read the title"
  puts "see https://forum.handbrake.fr/viewtopic.php?f=10&t=26165&p=120036#p120035"
  puts
  puts "for x264-presets have a look at"
  puts "https://forum.handbrake.fr/viewtopic.php?f=6&t=19426"
  puts
  puts "examples:"
  puts "convert main-feature with all original-tracks (audio and subtitle) for languages german and english"
  puts "#{File.basename($0)} --input /dev/rdisk1 --output \"~/Desktop/Movie.m4v\" --movie"
  puts
  puts "convert all episodes with all original-tracks (audio and subtitle) for languages german and english"
  puts "#{File.basename($0)} --input /dev/rdisk1 --output \"~/Desktop/Series_SeasonX_#pos#.m4v\" --episodes"
  puts
  if not msg.nil?
    puts msg
    puts
  end
  exit
end

options = Struct.new(
  :input, :output, :force,
  :ipodCompatibility, :enableAutocrop,
  :languages, :mixdownOnly, :copyOnly, :subtitles,
  :preset, :mainFeatureOnly, :titles, :chapters,
  :minLength, :maxLength, :skipDuplicates,
  :allTracksPerLanguage, :skipCommentaries,
  :checkOnly, :xtra_args, :debug, :verbose, :logfile,
  :x264preset).new
options.input = nil
options.output = nil
options.force = false
options.ipodCompatibility = false
options.enableAutocrop = false
options.languages = ["deu"]
options.mixdownOnly = false
options.copyOnly = false
options.subtitles = []
options.preset = nil
options.mainFeatureOnly = false
options.titles = nil
options.chapters = nil
options.minLength = nil
options.maxLength = nil
options.skipDuplicates = false
options.allTracksPerLanguage = false
options.skipCommentaries = false
options.checkOnly = false
options.xtra_args = nil
options.debug = false
options.verbose = false
options.logfile = nil
options.x264preset = nil

ARGV.options do |opts|
  opts.separator("")
  opts.separator("files")
  opts.on("--input INPUT", "input-source") { |arg| options.input = arg }
  opts.on("--output OUTPUT", "output-file (mp4, m4v and mkv supported)") { |arg| options.output = arg }
  opts.on("--force", "force override of existing files") { |arg| options.force = arg }
  opts.on("--check", "show only available titles and tracks") { |arg| options.checkOnly = arg }
  opts.on("--help", "Display this screen") { |arg| showUsageAndExit(opts.to_s) }

  opts.separator("")
  opts.separator("output-options")
  opts.on("--compatibility", "enables iPod compatible output") { |arg| options.ipodCompatibility = arg }
  opts.on("--autocrop", "automatically crop black bars") { |arg| options.enableAutocrop = arg }
  opts.on("--audio LANGUAGES", Array, "the audio languages") { |arg| options.languages = arg }
  opts.on("--mixdown-only", "create only mixed down track (Dolby ProLogic 2)") { |arg| options.mixdownOnly = arg }
  opts.on("--copy-only", "copy original-audio track") { |arg| options.copyOnly = arg }
  opts.on("--subtitles LANGUAGES", Array, "the subtitle languages") { |arg| options.subtitles = arg }
  opts.on("--preset PRESET", "the preset to use") { |arg| options.preset = arg }

  opts.separator("")
  opts.separator("filter-options")
  opts.on("--main", "main-feature only") { |arg| options.mainFeatureOnly = arg }
  opts.on("--titles TITLES", Array, "the title-numbers to rip (use --check to see available titles)") { |arg| options.titles = arg }
  opts.on("--chapters CHAPTERS", "the chapters to rip (e.g. 2 or 3-4)") { |arg| options.chapters = arg }
  opts.on("--min-length DURATION", "the minimum-track-length - format hh:nn:ss") { |arg| options.minLength = arg }
  opts.on("--max-length DURATION", "the maximum-track-length - format hh:nn:ss") { |arg| options.maxLength = arg }
  opts.on("--skip-duplicates", "skip duplicate titles (checks block-size)") { |arg| options.skipDuplicates = arg }
  opts.on("--all-tracks-per-language", "convert all found audio- or subtitle-track per language (default is only the first)") { |arg| options.allTracksPerLanguage = arg }
  opts.on("--skip-commentaries", "ignore commentary-audio- and subtitle-tracks") { |arg| options.skipCommentaries = arg }

  opts.separator("")
  opts.separator("expert-options")
  opts.on("--xtra ARGS", "additional arguments for handbrake") { |arg| options.xtra_args = arg }
  opts.on("--debug", "enable debug-mode (doesn't start conversion)") { |arg| options.debug = arg }
  opts.on("--verbose", "enable verbose output") { |arg| options.verbose = arg }
  opts.on("--x264preset PRESET", "use x264-preset (#{Handbrake::X264_PRESETS.keys().join(', ')})") { |arg| options.x264preset = arg }

  opts.separator("")
  opts.separator("shorts")
  opts.on("--default",   "sets: --audio deu,eng --subtitles deu,eng --copy-only --all-tracks-per-language --skip-commentaries") do |arg|
    options.languages = ["deu", "eng"]
    options.subtitles = ["deu", "eng"]
    options.copyOnly = true
    options.allTracksPerLanguage = true
    options.skipCommentaries = true
  end
  opts.on("--movie",   "sets: --default --main") do |arg|
    options.languages = ["deu", "eng"]
    options.subtitles = ["deu", "eng"]
    options.copyOnly = true
    options.allTracksPerLanguage = true
    options.skipCommentaries = true
    options.mainFeatureOnly = true
  end
  opts.on("--episodes", "sets: --default --min-length 00:10:00 --max-length 00:50:00 --skip-duplicates") do |arg|
    options.languages = ["deu", "eng"]
    options.subtitles = ["deu", "eng"]
    options.copyOnly = true
    options.allTracksPerLanguage = true
    options.skipCommentaries = true
    options.minLength = "00:10:00"
    options.maxLength = "00:50:00"
    options.skipDuplicates = true
  end
end

begin
  ARGV.parse!
rescue => e
  if not e.kind_of?(SystemExit)
    showUsageAndExit(ARGV.options.to_s, e.to_s)
  else
    exit
  end
end

if options.input.nil?() or (not options.checkOnly and options.output.nil?())
  showUsageAndExit(ARGV.options.to_s, "input or output not set")
end

if not options.x264preset.nil? and not Handbrake::X264_PRESETS[options.x264preset]
  showUsageAndExit(ARGV.options.to_s,"unknown x264-preset: #{options.x264preset}")
end

if not File.exists? options.input
  puts "\"#{options.input}\" does not exist"
  exit
end

source = Handbrake::readInfo(options)

titleMatcher = PosMatcher.new(options.titles)
audioMatcher = LangMatcher.new(options.languages)
subtitleMatcher = LangMatcher.new(options.subtitles)

if options.checkOnly
  puts source.info
else
  Handbrake::convert(options, source, titleMatcher, audioMatcher, subtitleMatcher)
end