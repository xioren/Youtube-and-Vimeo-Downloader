import std/[json, uri, algorithm, sequtils, parseutils]
# import std/[sha1]

import utils

# NOTE: age gate tier 1: https://www.youtube.com/watch?v=HtVdAasjOgU
# NOTE: age gate tier 2: https://www.youtube.com/watch?v=Tq92D6wQ1mg
# NOTE: age gate tier 3: https://www.youtube.com/watch?v=7iAQCPmpSUI

# NOTE: clientVersion can be found in contextUrl response (along with api key)
const
  playerContext = """{
    "context": {
      "client": {
        "hl": "en",
        "clientName": "WEB",
        "clientVersion": "2.$3.00.00"
      }
    },
    "playbackContext": {
      "contentPlaybackContext": {
        "signatureTimestamp": $2
      }
    },
    "contentCheckOk": true,
    "racyCheckOk": true,
    "videoId": "$1"
  }"""
  playerBypassContextTier1 = """{
    "context": {
      "client": {
        "hl": "en",
        "clientName": "WEB_EMBEDDED_PLAYER",
        "clientVersion": "2.$3.00.00"
      }
    },
    "playbackContext": {
      "contentPlaybackContext": {
        "signatureTimestamp": $2
      }
    },
    "contentCheckOk": true,
    "racyCheckOk": true,
    "videoId": "$1"
  }"""
  # FIXME: does not work
  # NOTE: anecdotally, should work for https://www.youtube.com/watch?v=HsUATh_Nc2U
  # playerBypassContextTier2 = """{
  #   "context": {
  #     "client": {
  #       "hl": "en",
  #       "clientName": "WEB",
  #       "clientVersion": "2.$3.00.00",
  #       "clientScreen": "EMBED"
  #     }
  #   },
  #   "playbackContext": {
  #     "contentPlaybackContext": {
  #       "signatureTimestamp": $2
  #     }
  #   },
  #   "thirdParty": {
  #     "embedUrl": "https://google.com"
  #   },
  #   "contentCheckOk": true,
  #   "racyCheckOk": true,
  #   "videoId": "$1"
  # }"""
  playerBypassContextTier2 = """{
    "context": {
      "client": {
        "hl": "en",
        "clientName": "WEB",
        "clientVersion": "2.$3.00.00",
        "clientScreen": "EMBED"
      }
    },
    "playbackContext": {
      "contentPlaybackContext": {
        "signatureTimestamp": $2
      }
    },
    "contentCheckOk": true,
    "racyCheckOk": true,
    "videoId": "$1"
  }"""
  browseContext = """{
    "browseId": "$1",
    "context": {
      "client": {
        "hl": "en",
        "clientName": "WEB",
        "clientVersion": "2.$2.00.00"
      }
    },
    "params": "$3"
  }"""
  browseContinueContext = """{
    "context": {
      "client": {
        "hl": "en",
        "clientName": "WEB",
        "clientVersion": "2.$3.00.00",
        "mainAppWebInfo": {
          "graftUrl": "/channel/$1/videos"
        }
      }
    },
    "continuation": "$2"
  }"""
  playlistContext = """{
    "context": {
      "client": {
        "hl": "en",
        "clientName": "WEB",
        "clientVersion": "2.$1.00.00",
        "mainAppWebInfo": {
          "graftUrl": "/playlist?list=$2"
        }
      }
    },
    "playlistId": "$2"
  }"""

type
  Stream = object
    itag: int
    mime: string
    ext: string
    size: string
    quality: string
    resolution: string
    bitrate: string
    url: string
    baseUrl: string
    urlSegments: seq[string]
    filename: string
    dash: bool
    exists: bool

  Video = object
    title: string
    videoId: string
    url: string
    audioStream: Stream
    videoStream: Stream


const
  apiKey = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
  baseUrl = "https://www.youtube.com"
  watchUrl = "https://www.youtube.com/watch?v="
  # channelUrl = "https://www.youtube.com/channel/"
  playlistUrl = "https://www.youtube.com/playlist?list="
  playerUrl = "https://youtubei.googleapis.com/youtubei/v1/player?key=" & apiKey
  browseUrl = "https://youtubei.googleapis.com/youtubei/v1/browse?key=" & apiKey
  nextUrl = "https://youtubei.googleapis.com/youtubei/v1/next?key=" & apiKey
  baseJsUrl = "https://www.youtube.com/s/player/$1/player_ias.vflset/$2/base.js"
  # contextUrl = "https://www.youtube.com/sw.js_data"
  videosTab = "EgZ2aWRlb3M%3D"
  playlistsTab = "EglwbGF5bGlzdHM%3D"
  forward = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I',
             'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R',
             'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a',
             'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j',
             'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's',
             't', 'u', 'v', 'w', 'x', 'y', 'z', '0', '1',
             '2', '3', '4', '5', '6', '7', '8', '9', '-',
             '_']
  reverse = ['0', '1', '2', '3', '4', '5', '6', '7', '8',
             '9', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h',
             'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q',
             'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
             'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I',
             'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R',
             'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '-',
             '_']

let date = now().format("yyyyMMdd")

var
  apiLocale: string
  includeAudio, includeVideo: bool
  audioFormat: string
  showStreams: bool
  h: array[64, char]
  globalBaseJsVersion: string
  cipherPlan: seq[string]
  cipherFunctionMap: Table[string, string]
  nTransforms: Table[string, string]
  throttleArray: seq[string]
  throttlePlan: seq[seq[string]]


########################################################
# authentication (wip)
########################################################


# proc creatAuthenticationCookie(): string =
#   const xOrigin = "https://www.youtube.com"
#   let
#     timeStamp = toUnix(getTime())
#     sapisid = "" # NOTE: from cookies
#   result = "SAPISIDHASH " & $timeStamp & '_' & $secureHash(timeStamp & ' ' & sapisid & ' ' & xOrigin)


########################################################
# throttle logic
########################################################
# NOTE: thanks to https://github.com/pytube/pytube/blob/master/pytube/cipher.py
# as a reference

proc index[T](d: openarray[T], item: T): int =
  ## provide index of item in d
  for idx, i in d:
    if i == item:
      return idx
  raise newException(IndexDefect, "$1 not in $2" % [$item, $d.type])


proc throttleModFunction(d: string, e: int): int =
  ## function(d,e){e=(e%d.length+d.length)%d.length
  result = e mod (d.len + d.len) mod d.len


proc throttleModFunction(d: seq[string], e: int): int =
  ## function(d,e){e=(e%d.length+d.length)%d.length
  result = e mod (d.len + d.len) mod d.len


proc throttleUnshift(d: var string, e: int) =
  ## handles prepend also
  # function(d,e){e=(e%d.length+d.length)%d.length;d.splice(-e).reverse().forEach(function(f){d.unshift(f)})}
  d.rotateLeft(d.len - throttleModFunction(d, e))


proc throttleUnshift(d: var seq[string], e: int) =
  ## handles prepend also
  d.rotateLeft(d.len - throttleModFunction(d, e))


proc throttleCipher(d: var string, e: string) =
  #[
  forward: function(d,e){for(var f=64,h=[];++f-h.length-32;){switch(f)
  {case 58:f-=14;case 91:case 92:case 93:continue;case 123:f=47;case 94:case 95:
  case 96:continue;case 46:f=95}h.push(String.fromCharCode(f))}
  d.forEach(function(l,m,n){this.push(n[m]=h[(h.indexOf(l)-h.indexOf(this[m])+m-32+f--)%h.length])}

  reverse: function(d,e){for(var f=64,h=[];++f-h.length-32;){switch(f){case 91:f=44;continue;
  case 123:f=65;break;case 65:f-=18;continue;case 58:f=96;continue;case 46:f=95}
  h.push(String.fromCharCode(f))}d.forEach(function(l,m,n){this.push(n[m]
  =h[(h.indexOf(l)-h.indexOf(this[m])+m-32+f--)%h.length])},e.split(""))}
  ]#
  let temp = d
  var
    this = e
    bVal: int
  for idx, c in temp:
    bVal = (h.index(c) - h.index(this[idx]) + 64) mod h.len
    this.add(h[bVal])
    d[idx] = h[bVal]


proc throttleCipher(d: var seq[string], e: string) =
  # NOTE: needed to compile
  doAssert false


proc throttleReverse(d: var string) =
  # function(d){d.reverse()}
  d.reverse()


proc throttleReverse(d: var seq[string]) =
  d.reverse()


proc throttlePush(d: var string, e: string) =
  # NOTE: needed to compile
  doAssert false


proc throttlePush(d: var seq[string], e: string) =
  # function(d,e){d.push(e)}
  d.add(e)


proc splice(d: var string, fromIdx: int) =
  ## javascript splice
  # function(d,e){e=(e%d.length+d.length)%d.length;d.splice(e,1)};
  let e = throttleModFunction(d, fromIdx)
  d.delete(e, e)


proc splice(d: var seq[string], fromIdx: int) =
  # NOTE: needed to compile
  doAssert false


proc throttleSwap(d: var string, e: int) =
  ## handles nested splice also
  # swap: function(d,e){e=(e%d.length+d.length)%d.length;var f=d[0];d[0]=d[e];d[e]=f}
  # nested splice: function(d,e){e=(e%d.length+d.length)%d.length;d.splice(0,1,d.splice(e,1,d[0])[0])}
  let z = throttleModFunction(d, e)
  if z < 0:
    swap(d[0], d[d.len + z])
  else:
    swap(d[0], d[z])


proc throttleSwap(d: var seq[string], e: int) =
  ## handles nested splice also
  let z = throttleModFunction(d, e)
  if z < 0:
    swap(d[0], d[d.len + z])
  else:
    swap(d[0], d[z])


proc parseThrottleFunctionName(js: string): string =
  ## parse main throttle function
  # a.C&&(b=a.get("n"))&&(b=kha(b),a.set("n",b))
  # --> kha
  var match: array[1, string]
  let pattern = re"(a\.[A-Z]&&\(b=a.[sg]et[^}]+)"
  discard js.find(pattern, match)
  result = match[0].captureBetween('=', '(', match[0].find("a.set") - 10)


proc parseThrottleCode(mainFunc, js: string): string =
  ## parse throttle code block
  # mainThrottleFunction=function(a){.....}
  var match: array[1, string]
  let pattern = re("($1=function\\(\\w\\){.+?})(?=;)" % mainFunc, flags={reDotAll})
  discard js.find(pattern, match)
  result = match[0]


iterator splitThrottleArray(js: string): string =
  ## split the throttle array into individual components
  var
    match: array[1, string]
    item = newString(1)
    context: int

  discard js.find(re("(?<=,c=\\[)(.+)(?=\\];\n?c)", flags={reDotAll}), match)
  for idx, c in match[0]:
    if (c == ',' and context == 0 and match[0][min(idx + 3, match[0].high)] != '{') or
       idx == match[0].high:
      if idx == match[0].high:
        item.add(c)
      yield item.multiReplace(("\x00", ""), ("\n", ""))
      item = newString(1)
      continue
    elif c == '{':
      inc context
    elif c == '}':
      dec context
    item.add(c)


proc parseThrottleFunctionArray(js: string): seq[string] =
  ## parse c array
  for item in splitThrottleArray(js):
    if item.startsWith("\"") and item.endsWith("\""):
      result.add(item[1..^2])
    elif item.startsWith("function"):
      if item.contains("pop"):
        result.add("throttleUnshift")
      elif item.contains("case"):
        if item.contains("case 65"):
          result.add("throttleCipherReverse")
        else:
          result.add("throttleCipherForward")
      elif item.contains("reverse") and item.contains("unshift"):
        result.add("throttlePrepend")
      elif item.contains("reverse"):
        result.add("throttleReverse")
      elif item.contains("push") and item.contains("splice"):
        result.add("throttleReverse")
      elif item.contains("push"):
        result.add("throttlePush")
      elif item.contains("var"):
        result.add("throttleSwap")
      elif item.count("splice") == 2:
        result.add("throttleNestedSplice")
      elif item.contains("splice"):
        result.add("splice")
    else:
      result.add(item)


proc parseThrottlePlan(js: string): seq[seq[string]] =
  ## parse elements of c array
  # (c[4](c[52])...) --> @[@[4, 52],...]
  let parts = js.captureBetween('{', '}', js.find("try"))
  for part in parts.split("),"):
    result.add(part.findAll(re"(?<=\[)(\d+)(?=\])"))


proc calculateN(n: string): string =
  ## calculate new n value to prevent throttling
  var
    tempArray = throttleArray
    firstArg, secondArg, currFunc: string
    initialN = n
    k, e: string

  for step in throttlePlan:
    currFunc = tempArray[parseInt(step[0])]
    firstArg = tempArray[parseInt(step[1])]

    if step.len == 3:
      secondArg = tempArray[parseInt(step[2])]
      # NOTE: arg in exponential notation
      if secondArg.contains('E') and not secondArg.contains("Each"):
        (k, e) = secondArg.split('E')
        secondArg = k & '0'.repeat(parseInt(e))

    # TODO: im sure there is a clever way to compact this
    if firstArg == "null":
      if currFunc == "throttleUnshift" or currFunc == "throttlePrepend":
        throttleUnshift(tempArray, parseInt(secondArg))
      elif currFunc.contains("throttleCipher"):
        if currFunc.contains("Forward"):
          h = forward
        else:
          h = reverse
        throttleCipher(tempArray, secondArg)
      elif currFunc == "throttleReverse":
        throttleReverse(tempArray)
      elif currFunc == "throttlePush":
        throttlePush(tempArray, secondArg)
      elif currFunc == "throttleSwap" or currFunc == "throttleNestedSplice":
        throttleSwap(tempArray, parseInt(secondArg))
      elif currFunc == "splice":
        splice(tempArray, parseInt(secondArg))
    else:
      if currFunc == "throttleUnshift" or currFunc == "throttlePrepend":
        throttleUnshift(initialN, parseInt(secondArg))
      elif currFunc.contains("throttleCipher"):
        if currFunc.contains("Forward"):
          h = forward
        else:
          h = reverse
        throttleCipher(initialN, secondArg)
      elif currFunc == "throttleReverse":
        throttleReverse(initialN)
      elif currFunc == "throttlePush":
        throttlePush(initialN, secondArg)
      elif currFunc == "throttleSwap" or currFunc == "throttleNestedSplice":
        throttleSwap(initialN, parseInt(secondArg))
      elif currFunc == "splice":
        splice(initialN, parseInt(secondArg))

  result = initialN


########################################################
# cipher logic
########################################################
# NOTE: thanks to https://github.com/pytube/pytube/blob/master/pytube/cipher.py
# as a reference

proc getParts(cipherSignature: string): tuple[url, sc, s: string] =
  ## break cipher string into (url, sc, s)
  let parts = cipherSignature.split('&')
  result = (decodeUrl(parts[2].split('=')[1]), parts[1].split('=')[1], decodeUrl(parts[0].split('=')[1]))


proc parseFunctionPlan(js: string): seq[string] =
  ## get the scramble functions
  ## returns: @["ix.Nh(a,2)", "ix.ai(a,5)"...]

  # NOTE: matches vy=function(a){a=a.split("");uy.bH(a,3);uy.Fg(a,7);uy.Fg(a,50);
  # uy.S6(a,71);uy.bH(a,2);uy.S6(a,80);uy.Fg(a,38);return a.join("")};
  let functionPattern = re"([a-zA-Z]{2}\=function\(a\)\{a\=a\.split\([^\(]+\);[a-zA-Z]{2}\.[^\n]+)"
  var match: array[1, string]
  discard js.find(functionPattern, match)
  match[0].split(';')[1..^3]


proc parseParentFunctionName(jsFunction: string): string =
  ## get the name of the function containing the scramble functions
  ## ix.Nh(a,2) --> ix
  jsFunction.parseIdent()


proc parseChildFunction(function: string): tuple[name: string, argument: int] {.inline.} =
  ## returns function name and int argument
  ## ix.ai(a,5) --> (ai, 5)
  result.name = function.captureBetween('.', '(')
  result.argument = parseInt(function.captureBetween(',', ')'))


proc parseIndex(jsFunction: string): int {.inline.} =
  if jsFunction.contains("splice"):
    # NOTE: function(a,b){a.splice(0,b)} --> 0
    result = parseInt(jsFunction.captureBetween('(', ',', jsFunction.find("splice")))
  elif jsFunction.contains("%"):
    # NOTE: function(a,b){var c=a[0];a[0]=a[b%a.length];a[b%a.length]=c} --> 0
    result = parseInt(jsFunction.captureBetween('[', ']', jsFunction.find("var")))


proc createFunctionMap(js, mainFunc: string): Table[string, string] =
  ## map functions to corresponding function names
  ## {"wW": "function(a){a.reverse()}", "Nh": "function(a,b){a.splice(0,b)}"...}
  var match: array[1, string]
  let pattern = re("(?<=var $1={)(.+?)(?=};)" % mainFunc, flags={reDotAll})
  discard js.find(pattern, match)
  for item in match[0].split(",\n"):
    let parts = item.split(':')
    result[parts[0]] = parts[1]


proc decipher(signature: string): string =
  ## decipher signature
  var splitSig = @signature

  for item in cipherPlan:
    let
      (funcName, argument) = parseChildFunction(item)
      jsFunction = cipherFunctionMap[funcName]
      index = parseIndex(jsFunction)
    if jsFunction.contains("reverse"):
      ## function(a, b){a.reverse()}
      splitSig.reverse()
    elif jsFunction.contains("splice"):
      ## function(a, b){a.splice(0, b)}
      splitSig.delete(index, index + pred(argument))
    else:
      ## function(a,b){var c=a[0];a[0]=a[b%a.length];a[b%a.length]=c}
      swap(splitSig[index], splitSig[argument mod splitSig.len])

  result = splitSig.join()


proc getSigCipherUrl(signatureCipher: string): string =
  ## produce url with deciphered signature
  let parts = getParts(signatureCipher)
  result = parts.url & "&" & parts.sc & "=" & encodeUrl(decipher(parts.s))


########################################################
# stream logic
########################################################


proc urlOrCipher(stream: JsonNode): string =
  ## produce stream url, deciphering if necessary
  if stream.hasKey("url"):
    result = stream["url"].getStr()
  elif stream.hasKey("signatureCipher"):
    result = getSigCipherUrl(stream["signatureCipher"].getStr())

  let n = result.captureBetween('=', '&', result.find("&n="))
  if nTransforms.haskey(n):
    result = result.replace(n, nTransforms[n])
  else:
    let calculatedN = calculateN(n)
    nTransforms[n] = calculatedN
    if n != calculatedN:
      result = result.replace(n, calculatedN)


proc produceUrlSegments(baseUrl, segmentList: string): seq[string] =
  let base = parseUri(baseUrl)
  for segment in segmentList.findAll(re("""(?<=\")([a-z\d/\.-]+)(?=\")""")):
    result.add($(base / segment))


proc extractDashInfo(dashManifestUrl, itag: string): tuple[baseUrl, segmentList: string] =
  let (_, xml) = doGet(dashManifestUrl)
  var match: array[1, string]
  discard xml.find(re("""(?<=<Representation\s)(id="$1".+?)(?=</Representation>)""" % itag), match)
  result.baseUrl = match[0].captureBetween('>', '<', match[0].find("<BaseURL>") + 8)
  discard match[0].find(re("(?<=<SegmentList>)(.+)(?=</SegmentList>)"), match)
  result.segmentList = match[0]


proc selectVideoStream(streams: JsonNode, itag: int): JsonNode =
  # NOTE: zeroth stream usually seems to be the overall best quality
  if itag == 0:
    var largest = 0
    for stream in streams:
      if stream.hasKey("width"):
        if stream["bitrate"].getInt() > largest:
          largest = stream["bitrate"].getInt()
          result = stream
  else:
    for stream in streams:
      if stream["itag"].getInt() == itag:
        result = stream
        break


proc selectAudioStream(streams: JsonNode, itag: int): JsonNode =
  # NOTE: in tests, it seems youtube videos "without audio" still contain an empty
  # audio stream
  # "audio-less" video: https://www.youtube.com/watch?v=fW2e0CZjnFM
  if itag == 0:
    var largest = 0
    for stream in streams:
      if stream.hasKey("audioQuality"):
        if stream["bitrate"].getInt() > largest:
          largest = stream["bitrate"].getInt()
          result = stream
  else:
    for stream in streams:
      if stream["itag"].getInt() == itag:
        result = stream
        break


proc getVideoStreamInfo(stream: JsonNode, duration: int): tuple[itag: int, mime, ext, size, qlt, resolution, bitrate: string] =
  result.itag = stream["itag"].getInt()
  result.mime = stream["mimeType"].getStr().split(";")[0]
  result.ext = extensions[result.mime]
  result.qlt = stream["qualityLabel"].getStr()
  result.resolution = $stream["width"].getInt() & 'x' & $stream["height"].getInt()

  var rawBitrate: int
  if stream.hasKey("averageBitrate"):
    rawBitrate = stream["averageBitrate"].getInt()
  else:
    rawBitrate = stream["bitrate"].getInt()
  result.bitrate = formatSize(rawBitrate, includeSpace=true) & "/s"

  if stream.hasKey("contentLength"):
    result.size = formatSize(parseInt(stream["contentLength"].getStr()), includeSpace=true)
  else:
    # NOTE: estimate from bitrate
    result.size = formatSize(int(rawBitrate * duration / 8), includeSpace=true)



proc getAudioStreamInfo(stream: JsonNode, duration: int): tuple[itag: int, mime, ext, size, qlt, bitrate: string] =
  result.itag = stream["itag"].getInt()
  result.mime = stream["mimeType"].getStr().split(";")[0]
  result.ext = extensions[result.mime]
  result.qlt = stream["audioQuality"].getStr().replace("AUDIO_QUALITY_").toLowerAscii()

  var rawBitrate: int
  if stream.hasKey("averageBitrate"):
    rawBitrate = stream["averageBitrate"].getInt()
  else:
    rawBitrate = stream["bitrate"].getInt()
  result.bitrate = formatSize(rawBitrate, includeSpace=true) & "/s"

  if stream.hasKey("contentLength"):
    result.size = formatSize(parseInt(stream["contentLength"].getStr()), includeSpace=true)
  else:
    # NOTE: estimate from bitrate
    result.size = formatSize(int(rawBitrate * duration / 8), includeSpace=true)


proc newVideoStream(youtubeUrl, dashManifestUrl, videoId: string, duration: int, stream: JsonNode): Stream =
  if stream.kind != JNull:
    # NOTE: should NEVER be JNull but go through the motions anyway for parity with newAudioStream
    (result.itag, result.mime, result.ext, result.size, result.quality, result.resolution, result.bitrate) = getVideoStreamInfo(stream, duration)
    result.filename = addFileExt(videoId, result.ext)
    # QUESTION: are all dash segment stream denoted with "FORMAT_STREAM_TYPE_OTF"?
    if stream.hasKey("type") and stream["type"].getStr() == "FORMAT_STREAM_TYPE_OTF":
      # QUESTION: are dash urls or manifest urls ever ciphered?
      var segmentList: string
      result.dash = true
      (result.baseUrl, segmentList) = extractDashInfo(dashManifestUrl, $result.itag)
      result.urlSegments = produceUrlSegments(result.baseUrl, segmentList)
    else:
      result.url = urlOrCipher(stream)
    result.exists = true


proc newAudioStream(youtubeUrl, dashManifestUrl, videoId: string, duration: int, stream: JsonNode): Stream =
  if stream.kind != JNull:
    (result.itag, result.mime, result.ext, result.size, result.quality, result.bitrate) = getAudioStreamInfo(stream, duration)
    result.filename = addFileExt(videoId, result.ext)
    # QUESTION: are all dash segment stream denoted with "FORMAT_STREAM_TYPE_OTF"?
    if stream.hasKey("type") and stream["type"].getStr() == "FORMAT_STREAM_TYPE_OTF":
      # QUESTION: are dash urls or manifest urls ever ciphered?
      var segmentList: string
      result.dash = true
      (result.baseUrl, segmentList) = extractDashInfo(dashManifestUrl, $result.itag)
      result.urlSegments = produceUrlSegments(result.baseUrl, segmentList)
    else:
      result.url = urlOrCipher(stream)
    result.exists = true


proc newVideo(youtubeUrl, dashManifestUrl, title, videoId: string, duration: int,
              adaptiveFormats: JsonNode, aItag, vItag: int): Video =
  result.title = title
  result.url = youtubeUrl
  result.videoId = videoId
  result.videoStream = newVideoStream(youtubeUrl, dashManifestUrl, videoId, duration,
                                      selectVideoStream(adaptiveFormats, vItag))
  result.audioStream = newAudioStream(youtubeUrl, dashManifestUrl, videoId, duration,
                                      selectAudioStream(adaptiveFormats, aItag))


proc reportStreamInfo(stream: Stream) =
  echo "stream: ", stream.filename, '\n',
       "itag: ", stream.itag, '\n',
       "size: ", stream.size, '\n',
       "quality: ", stream.quality, '\n',
       "mime: ", stream.mime
  if stream.dash:
    echo "segments: ", stream.urlSegments.len


proc reportStreams(playerResponse: JsonNode, duration: int) =
  var
    itag: int
    mime, ext, size, quality, resolution, bitrate: string

  for item in playerResponse["streamingData"]["adaptiveFormats"]:
    if item.hasKey("audioQuality"):
      (itag, mime, ext, size, quality, bitrate) = getAudioStreamInfo(item, duration)
      echo "[audio]", " itag: ", itag, " quality: ", quality,
           " bitrate: ", bitrate, " mime: ", mime, " size: ", size
    else:
      (itag, mime, ext, size, quality, resolution, bitrate) = getVideoStreamInfo(item, duration)
      echo "[video]", " itag: ", itag, " quality: ", quality,
           " resolution: ", resolution, " bitrate: ", bitrate, " mime: ", mime,
           " size: ", size


########################################################
# misc
########################################################


proc parseBaseJs() =
  let (code, response) = doGet(baseJsUrl % [globalBaseJsVersion, apiLocale])
  if code.is2xx:
    cipherPlan = parseFunctionPlan(response)
    cipherFunctionMap = createFunctionMap(response, parseParentFunctionName(cipherPlan[0]))
    let throttleCode = parseThrottleCode(parseThrottleFunctionName(response), response)
    throttlePlan = parseThrottlePlan(throttleCode)
    throttleArray = parseThrottleFunctionArray(throttleCode)


proc isolateVideoId(youtubeUrl: string): string =
  if youtubeUrl.contains("youtu.be"):
    result = youtubeUrl.captureBetween('/', '?', 8)
  else:
    result = youtubeUrl.captureBetween('=', '&')


proc isolateChannel(youtubeUrl: string): string =
  # NOTE: vanity
  if "/c/" in youtubeUrl:
    let response = doGet(youtubeUrl)
    result = response[1].captureBetween('"', '"', response[1].find("""browseId":""") + 9)
  else:
    result = youtubeUrl.captureBetween('/', '/', youtubeUrl.find("channel"))


proc isolatePlaylist(youtubeUrl: string): string =
  result = youtubeUrl.captureBetween('=', '&', youtubeUrl.find("list="))


########################################################
# main
########################################################


proc getVideo(youtubeUrl: string, aItag=0, vItag=0) =
  let
    videoId = isolateVideoId(youtubeUrl)
    standardYoutubeUrl = watchUrl & videoId
  var
    code: HttpCode
    response: string
    playerResponse: JsonNode
    dashManifestUrl: string

  # NOTE: make initial request to get base.js version and timestamp
  (code, response) = doGet(standardYoutubeUrl)
  if code.is2xx:
    apiLocale = response.captureBetween('\"', '\"', response.find("GAPI_LOCALE\":") + 12)
    let
      sigTimeStamp = response.captureBetween(':', ',', response.find("\"STS\""))
      thisBaseJsVersion = response.captureBetween('/', '/', response.find("""jsUrl":"/s/player/""") + 11)
    if thisBaseJsVersion != globalBaseJsVersion:
      globalBaseJsVersion = thisBaseJsVersion
      parseBaseJs()

    (code, response) = doPost(playerUrl, playerContext % [videoId, sigTimeStamp, date])
    if code.is2xx:
      playerResponse = parseJson(response)
      if playerResponse["playabilityStatus"]["status"].getStr() == "ERROR":
        echo '<', playerResponse["playabilityStatus"]["reason"].getStr(), '>'
        return

      let
        title = playerResponse["videoDetails"]["title"].getStr()
        safeTitle = makeSafe(title)
        finalFilename = addFileExt(safeTitle, ".mkv")
        duration = parseInt(playerResponse["videoDetails"]["lengthSeconds"].getStr())

      if fileExists(finalFilename) and not showStreams:
        echo "<file exists> ", safeTitle
      else:
        # NOTE: age gate and misc youtube error handling
        if playerResponse["playabilityStatus"]["status"].getStr() == "LOGIN_REQUIRED":
          echo "[attempting age-gate bypass tier 1]"
          (code, response) = doPost(playerUrl, playerBypassContextTier1 % [videoId, sigTimeStamp, date])
          playerResponse = parseJson(response)

          if playerResponse["playabilityStatus"]["status"].getStr() != "OK":
            echo '<', playerResponse["playabilityStatus"]["reason"].getStr(), '>'
            echo "[attempting age-gate bypass tier 2]"
            (code, response) = doPost(playerUrl, playerBypassContextTier2 % [videoId, sigTimeStamp, date])
            playerResponse = parseJson(response)

            if playerResponse["playabilityStatus"]["status"].getStr() != "OK":
              echo '<', playerResponse["playabilityStatus"]["reason"].getStr(), '>'
              return
        elif playerResponse["playabilityStatus"]["status"].getStr() != "OK" or
             playerResponse["playabilityStatus"].hasKey("liveStreamability"):
          echo '<', playerResponse["playabilityStatus"]["reason"].getStr(), '>'
          # QUESTION: does "errorScreen" always imply "subreason"?
          if playerResponse["playabilityStatus"].hasKey("errorScreen") and
             playerResponse["playabilityStatus"]["errorScreen"]["playerErrorMessageRenderer"].hasKey("subreason"):
            for run in playerResponse["playabilityStatus"]["errorScreen"]["playerErrorMessageRenderer"]["subreason"]["runs"]:
              stdout.write(run["text"].getStr())
          return

        if showStreams:
          reportStreams(playerResponse, duration)
          return

        # QUESTION: hlsManifestUrl seems to be for live streamed videos but is it ever needed?
        if playerResponse["streamingData"].hasKey("dashManifestUrl"):
          dashManifestUrl = playerResponse["streamingData"]["dashManifestUrl"].getStr()
        let video = newVideo(standardYoutubeUrl, dashManifestUrl, title, videoId, duration,
                             playerResponse["streamingData"]["adaptiveFormats"], aItag, vItag)
        echo "title: ", video.title

        var attempt: HttpCode
        if includeVideo:
          reportStreamInfo(video.videoStream)
          if video.videoStream.dash:
            attempt = grab(video.videoStream.urlSegments, forceFilename=video.videoStream.filename,
                           forceDl=true)
          else:
            attempt = grab(video.videoStream.url, forceFilename=video.videoStream.filename,
                           forceDl=true)
          if not attempt.is2xx:
            echo "<failed to download video stream>"
            includeVideo = false
            # NOTE: remove empty file
            discard tryRemoveFile(video.videoStream.filename)

        if includeAudio and video.audioStream.exists:
          reportStreamInfo(video.audioStream)
          if video.audioStream.dash:
            attempt = grab(video.audioStream.urlSegments, forceFilename=video.audioStream.filename,
                           forceDl=true)
          else:
            attempt = grab(video.audioStream.url, forceFilename=video.audioStream.filename,
                           forceDl=true)
          if not attempt.is2xx:
            echo "<failed to download audio stream>"
            includeAudio = false
            # NOTE: remove empty file
            discard tryRemoveFile(video.audioStream.filename)
        else:
          includeAudio = false

        if includeAudio and includeVideo:
          joinStreams(video.videoStream.filename, video.audioStream.filename, safeTitle)
        elif includeAudio and not includeVideo:
          convertAudio(video.audioStream.filename, safeTitle, audioFormat)
        elif includeVideo:
          moveFile(video.videoStream.filename, finalFilename.changeFileExt(video.videoStream.ext))
          echo "[complete] ", addFileExt(safeTitle, video.videoStream.ext)
        else:
          echo "<no streams were downloaded>"
    else:
      echo '<', code, '>', '\n', "<failed to obtain video metadata>"
  else:
    echo '<', code, '>', '\n', "<failed to obtain channel metadata>"


proc getPlaylist(youtubeUrl: string) =
  var
    playlistResponse: JsonNode
    ids: seq[string]
    title: string
  let playlist = isolatePlaylist(youtubeUrl)

  let (code, response) = doPost(nextUrl, playlistContext % [date, playlist])
  if code.is2xx:
    playlistResponse = parseJson(response)
    title = playlistResponse["contents"]["twoColumnWatchNextResults"]["playlist"]["playlist"]["title"].getStr()
    echo "[collecting videos] ", title

    if playlistResponse["contents"]["twoColumnWatchNextResults"]["playlist"]["playlist"]["isInfinite"].getBool():
      echo "<infinite playlist...aborting>"
    else:
      for item in playlistResponse["contents"]["twoColumnWatchNextResults"]["playlist"]["playlist"]["contents"]:
        ids.add(item["playlistPanelVideoRenderer"]["videoId"].getStr())

      echo '[', ids.len, " videos queued]"
      for id in ids:
        getVideo(watchUrl & id)
  else:
    echo '<', code, '>', '\n', "<failed to obtain playlist metadata>"


proc getChannel(youtubeUrl: string) =
  let channel = isolateChannel(youtubeUrl)
  var
    channelResponse: JsonNode
    response: string
    code: HttpCode
    token, lastToken: string
    title: string
    videoIds: seq[string]
    playlistIds: seq[string]
    tabIdx = 1

  iterator gridRendererExtractor(renderer: string): string =
    let upperRenderer = capitalizeAscii(renderer)
    for section in channelResponse["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][tabIdx]["tabRenderer"]["content"]["sectionListRenderer"]["contents"]:
      if section["itemSectionRenderer"]["contents"][0].hasKey("messageRenderer"):
        echo '<', section["itemSectionRenderer"]["contents"][0]["messageRenderer"]["text"]["simpleText"].getStr(), '>'
      else:
        for item in section["itemSectionRenderer"]["contents"][0]["gridRenderer"]["items"]:
          if item.hasKey("continuationItemRenderer"):
            token = item["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"]["token"].getStr()
            lastToken = token

            while true:
              (code, response) = doPost(browseUrl, browseContinueContext % [channel, token, date])
              if code.is2xx:
                channelResponse = parseJson(response)
                for continuationItem in channelResponse["onResponseReceivedActions"][0]["appendContinuationItemsAction"]["continuationItems"]:
                  if continuationItem.hasKey("continuationItemRenderer"):
                    token = continuationItem["continuationItemRenderer"]["continuationEndpoint"]["continuationCommand"]["token"].getStr()
                  else:
                    yield continuationItem["grid" & upperRenderer & "Renderer"][renderer & "Id"].getStr()
                if token == lastToken:
                  break
                else:
                  lastToken = token
              else:
                echo "<failed to obtain channel metadata>"
          else:
              yield item["grid" & upperRenderer & "Renderer"][renderer & "Id"].getStr()

  (code, response) = doPost(browseUrl, browseContext % [channel, date, videosTab])
  if code.is2xx:
    echo "[collecting videos]"
    channelResponse = parseJson(response)
    title = channelResponse["metadata"]["channelMetadataRenderer"]["title"].getStr()
    if channelResponse["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][tabIdx]["tabRenderer"]["title"].getStr() == "Videos":
      for id in gridRendererExtractor("video"):
        videoIds.add(id)
      inc tabIdx

    if title.endsWith(" - Topic"):
      # NOTE: for now only get playlists for topic channels
      (code, response) = doPost(browseUrl, browseContext % [channel, date, playlistsTab])
      if code.is2xx:
        echo "[collecting playlists]"
        channelResponse = parseJson(response)
        if channelResponse["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][tabIdx]["tabRenderer"]["title"].getStr() == "Playlists":
          for section in channelResponse["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][tabIdx]["tabRenderer"]["content"]["sectionListRenderer"]["contents"]:
            if section["itemSectionRenderer"]["contents"][0].hasKey("messageRenderer"):
              echo '<', section["itemSectionRenderer"]["contents"][0]["messageRenderer"]["text"]["simpleText"].getStr(), '>'
            else:
              if section["itemSectionRenderer"]["contents"][0].hasKey("gridRenderer"):
                # NOTE: gridRenderer
                for id in gridRendererExtractor("playlist"):
                  playlistIds.add(id)
              elif section["itemSectionRenderer"]["contents"][0].hasKey("shelfRenderer"):
                if section["itemSectionRenderer"]["contents"][0]["shelfRenderer"]["content"].hasKey("expandedShelfContentsRenderer"):
                  # NOTE: expandedShelfContentsRenderer
                  for item in section["itemSectionRenderer"]["contents"][0]["shelfRenderer"]["content"]["expandedShelfContentsRenderer"]["items"]:
                    playlistIds.add(item["playlistRenderer"]["playlistId"].getStr())
                elif section["itemSectionRenderer"]["contents"][0]["shelfRenderer"]["content"].hasKey("horizontalListRenderer"):
                  # NOTE: horizontalListRenderer
                  for item in section["itemSectionRenderer"]["contents"][0]["shelfRenderer"]["content"]["horizontalListRenderer"]["items"]:
                    playlistIds.add(item["gridPlaylistRenderer"]["playlistId"].getStr())
                else:
                  echo "<failed to obtain channel metadata>"
              else:
                echo "<failed to obtain channel metadata>"
      else:
        echo '<', code, '>', '\n', "<failed to obtain channel metadata>"
  else:
    echo '<', code, '>', '\n', "<failed to obtain channel metadata>"

  echo '[', videoIds.len, " videos queued]", '\n', '[', playlistIds.len, " playlists queued]"
  for id in videoIds:
    getVideo(watchUrl & id)
  for id in playlistIds:
    getPlaylist(playlistUrl & id)


proc youtubeDownload*(youtubeUrl: string, audio, video, streams: bool, format, aItag, vItag: string) =
  includeAudio = audio
  includeVideo = video
  audioFormat = format
  showStreams = streams

  if "/channel/" in youtubeUrl or "/c/" in youtubeUrl:
    getChannel(youtubeUrl)
  elif "/playlist?" in youtubeUrl:
    getPlaylist(youtubeUrl)
  else:
    getVideo(youtubeUrl, parseInt(aItag), parseInt(vItag))
