import std.stdio, std.regex, std.json, std.file, std.datetime, std.conv, std.process, std.net.curl;
import qobuz.api;

int main(string[] args)
{
  if (args.length != 2) {
    writefln("Usage: %s <album id or url>", args[0]);
    return -1;
  }

  auto path = thisExePath();
  path = path.replaceFirst(regex("qobuz-get$"), "magic.json"); // HACK
  string json;
  try {
    json = readText(path);
  } catch (Exception e) {
    writeln("Could not open magic.json!");
  }
  auto magic = parseJSON(json);
  
  // strip url part if we have it
  string id;
  auto urlPart = regex("^https?://play.qobuz.com/album/");
  if (args[1].matchFirst(urlPart)) {
    id = args[1].replaceFirst(urlPart, "");
  } else {
    id = args[1];
  }

  writeln("Looking up album...");
  auto album = getAlbum(magic, id);

  string title, artist, genre, year;
  JSONValue[] tracks;

  try {
    title = album["title"].str;
    artist = album["artist"]["name"].str;
    genre = album["genres_list"][0].str;
    auto releaseTime = SysTime.fromUnixTime(album["released_at"].integer, UTC());
    year = releaseTime.year.text;

    writefln("[ %s - %s (%s, %s) ]", artist, title, genre, year);

    tracks = album["tracks"]["items"].array();
  } catch (Exception e) {
    writeln("Could not parse album data!");
    return -4;
  }

  string dirName = artist~" - "~title~" ("~year~") [WEB FLAC]";
  mkdir(dirName);

  foreach (i, track; tracks) {
    auto num = (i+1).text;
    string url, trackName;
    try {
      trackName = track["title"].str;
      if (num.length < 2)
        num = "0"~num;
      writef(" [%s] %s... ", num, trackName);
      stdout.flush;
      url = getDownloadUrl(magic, track["id"].integer.text);
    } catch (Exception e) {
      writeln("Failed to parse track data!");
      return -7;
    }

    try {
      auto pipes = pipeProcess([magic["ffmpeg"].str, "-i", "-", "-metadata", "title="~trackName, "-metadata", "author="~artist,
          "-metadata", "album="~title, "-metadata", "year="~year, "-metadata", "track="~num, "-metadata", "genre="~genre,
          dirName~"/"~num~" "~trackName~".flac"], Redirect.stdin | Redirect.stderr | Redirect.stdout);
      foreach (chunk; byChunkAsync(url, 1024)) {
        pipes.stdin.rawWrite(chunk);
        pipes.stdin.flush;
      }
      pipes.stdin.close;
      wait(pipes.pid);
    } catch (Exception e) {
      writeln("Failed to download track! Check that ffmpeg is properly configured.");
      return -8;
    }
    writeln("Done!");
  }

  return 0;
}
