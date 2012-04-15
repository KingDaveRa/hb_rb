class Tagger

  @platform = nil
  @command = nil
 
  def createCommand(file, tagInfo)
    raise "unsupported operation"
  end

  def initialize(platform, cmd)
    @platform = platform
    @command = cmd
  end
  
  def available?()
    return (Tools::OS::platform?(@platform) and Tools::OS::command?(@command))
  end
  
  def to_s
    @command
  end
end

class AtomicParsley < Tagger

  OSX_COMMAND = File.expand_path("tools/atomicparsley/osx/AtomicParsley")
  WIN_COMMAND = File.expand_path("tools/atomicparsley/windows/AtomicParsley.exe") 

  ARG_MAP = {
    "title" => "--title",
    "disc" => "--disknum",
    "name" => "--artist",
    "episode" => "--tracknum",
    "season" => "--TVSeason",
    "descr" => "--description"
  }

  def createCommand(file, tagInfo)
    cmd = "#{@command} \"#{file}\""
    cmd << " --overWrite"
    tagInfo.each do |key, value|
      arg = ARG_MAP[key]
      next if arg.nil?()
      value = "" if value.nil?()
      cmd << " #{arg} \"#{value}\""
    end
    return cmd
  end
end

class SublerCLITagger < Tagger
  OSX_COMMAND = File.expand_path("tools/subler/osx/SublerCLI")
  SUBLER_TAGS = [
      "Name", "Artist", "Album Artist", "Album", "Grouping", "Composer", "Comments", "Genre", "Release Date", 
      "Track #", "Disk #", "TV Show", "TV Episode #", "TV Network", "TV Episode ID", "TV Season", "Description", 
      "Long Description", "Rating", "Rating Annotation", "Studio", "Cast", "Director", "Codirector", "Producers", 
      "Screenwriters", "Lyrics", "Copyright", "Encoding Tool", "Encoded By", "contentID", "HD Video", "Gapless", 
      "Content Rating", "Media Kind", "Artwork"
    ]
  SUBLER_TAG_MAP = {
    "title" => "Name",
    "disc" => "Disk #",
    "name" => "Artist",
    "episode" => "Track #",
    "season" => "TV Season",
    "descr" => "Description"
  }

  def createCommand(file, tagMap)
    tags = ""
    tagMap.each do |key, value|
      tag = SUBLER_TAG_MAP[key]
      next if tag.nil?
      ##puts "#{key} => #{value}"
      tags << "{#{escape(tag)}:#{escape(value)}}"
    end
    return nil if tags.length == 0
    return "\"#{SUBLER_CLI}\" -i \"#{file}\" -t \"#{tags}\""
  end

  def escape(tag)
    return "" if tag.nil?
    t = tag.gsub("{","&#123;")
    t = t.gsub(":","&#58;")
    t = t.gsub("}","&#125;")
    return t
  end
end

class TaggerFactory
  @@TAGGERS = [
    SublerCLITagger.new(Tools::OS::OSX, SublerCLITagger::OSX_COMMAND),
    AtomicParsley.new(Tools::OS::OSX, AtomicParsley::OSX_COMMAND),
    AtomicParsley.new(Tools::OS::WINDOWS, AtomicParsley::WIN_COMMAND)
  ]

  def self.newTagger()
    @@TAGGERS.each do |t|
      return t if t.available?()
    end
    raise "found no tagger for platform #{Tools::OS.platform()}"
  end
end