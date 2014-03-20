# The MIT License (MIT)
#
# Copyright (c) 2014 Chris Wilson
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

audioContext = new AudioContext()
isPlaying = false
sourceNode = null
analyser = null
theBuffer = null
detectorElem = undefined
canvasContext = undefined
pitchElem = undefined
noteElem = undefined
detuneElem = undefined
detuneAmount = undefined
WIDTH = 300
CENTER = 150
HEIGHT = 42
confidence = 0
currentPitch = 0


window.onload = ->
  request = new XMLHttpRequest()
  request.open "GET", "../sounds/whistling3.ogg", true
  request.responseType = "arraybuffer"
  request.onload = ->
    audioContext.decodeAudioData request.response, (buffer) ->
      theBuffer = buffer
      return

    return

  request.send()
  detectorElem = document.getElementById("detector")
  pitchElem = document.getElementById("pitch")
  noteElem = document.getElementById("note")
  detuneElem = document.getElementById("detune")
  detuneAmount = document.getElementById("detune_amt")
  canvasContext = document.getElementById("output").getContext("2d")
  detectorElem.ondragenter = ->
    @classList.add "droptarget"
    false

  detectorElem.ondragleave = ->
    @classList.remove "droptarget"
    false

  detectorElem.ondrop = (e) ->
    @classList.remove "droptarget"
    e.preventDefault()
    theBuffer = null
    reader = new FileReader()
    reader.onload = (event) ->
      audioContext.decodeAudioData event.target.result, ((buffer) ->
        theBuffer = buffer
        return
      ), ->
        alert "error loading!"
        return

      return

    reader.onerror = (event) ->
      alert "Error: " + reader.error
      return

    reader.readAsArrayBuffer e.dataTransfer.files[0]
    false

  return


error = ->
  alert "Stream generation failed."
  return

getUserMedia = (dictionary, callback) ->
  try
    navigator.getUserMedia = navigator.getUserMedia or navigator.webkitGetUserMedia or navigator.mozGetUserMedia
    navigator.getUserMedia dictionary, callback, error
  catch e
    alert "getUserMedia threw exception :" + e
  return

gotStream = (stream) ->
  
  # Create an AudioNode from the stream.
  mediaStreamSource = audioContext.createMediaStreamSource(stream)
  
  # Connect it to the destination.
  analyser = audioContext.createAnalyser()
  analyser.fftSize = 2048
  mediaStreamSource.connect analyser
  updatePitch()
  return

toggleLiveInput = ->
  getUserMedia {
    audio: true
  }, gotStream
  return

toggleLiveInput2 = ->
  getUserMedia {
    audio: true
  }, gotStream2
  return

togglePlayback = ->
  now = audioContext.currentTime
  if isPlaying
    
    #stop playing and return
    sourceNode.stop now
    sourceNode = null
    analyser = null
    isPlaying = false
    window.cancelAnimationFrame = window.webkitCancelAnimationFrame  unless window.cancelAnimationFrame
    window.cancelAnimationFrame rafID
    return "start"
  sourceNode = audioContext.createBufferSource()
  sourceNode.buffer = theBuffer
  sourceNode.loop = true
  analyser = audioContext.createAnalyser()
  analyser.fftSize = 2048
  sourceNode.connect analyser
  analyser.connect audioContext.destination
  sourceNode.start now
  isPlaying = true
  isLiveInput = false
  updatePitch()
  "stop"

rafID = null
tracks = null
buflen = 2048
buf = new Uint8Array(buflen)
MINVAL = 134 # 128 == zero.  MINVAL is the "minimum detected signal" level.

noteStrings = [
  "C"
  "C#"
  "D"
  "D#"
  "E"
  "F"
  "F#"
  "G"
  "G#"
  "A"
  "A#"
  "B"
]

noteFromPitch = (frequency) ->
  noteNum = 12 * (Math.log(frequency / 440) / Math.log(2))
  Math.round(noteNum) + 69

frequencyFromNoteNumber = (note) ->
  440 * Math.pow(2, (note - 69) / 12)

centsOffFromPitch = (frequency, note) ->
  1200 * Math.log(frequency / frequencyFromNoteNumber(note)) / Math.log(2)

autoCorrelate = (buf, sampleRate) ->
  MIN_SAMPLES = 4 # corresponds to an 11kHz signal
  MAX_SAMPLES = 1000 # corresponds to a 44Hz signal
  SIZE = 1000
  best_offset = -1
  best_correlation = 0
  rms = 0
  confidence = 0
  currentPitch = 0
  return  if buf.length < (SIZE + MAX_SAMPLES - MIN_SAMPLES) # Not enough data
  i = 0

  while i < SIZE
    val = (buf[i] - 128) / 128
    rms += val * val
    i++
  rms = Math.sqrt(rms / SIZE)
  offset = MIN_SAMPLES

  while offset <= MAX_SAMPLES
    correlation = 0
    i = 0

    while i < SIZE
      correlation += Math.abs(((buf[i] - 128) / 128) - ((buf[i + offset] - 128) / 128))
      i++
    correlation = 1 - (correlation / SIZE)
    if correlation > best_correlation
      best_correlation = correlation
      best_offset = offset
    offset++
  if (rms > 0.01) and (best_correlation > 0.01)
    confidence = best_correlation * rms * 10000
    currentPitch = sampleRate / best_offset
  return

  # console.log("f = " + sampleRate/best_offset + "Hz (rms: " + rms + " confidence: " + best_correlation + ")")

  # var best_frequency = sampleRate/best_offset;


pitchAnalyser = new PitchAnalyzer(2048)

noteAge = 0
prevNote = 0

updatePitch = (time) ->
  cycles = new Array
  analyser.getByteTimeDomainData buf
  
  pitchAnalyser.input(buf)
  pitchAnalyser.process()
  tone = pitchAnalyser.findTone()
  if tone? and tone.stabledb > -20
    #console.log tone.freq
    #console.log tone
    note = noteFromPitch(tone.freq)
    #noteFixed = noteFromPitchCorrected(tone.freq)
    if Math.abs(note-prevNote) < 1
      noteAge += 1
    else
      noteAge = 0
    prevNote = note
    if noteAge > 2
      $('#currentPitch').html(noteStrings[note % 12] + '<br>' + note + '<br>' + tone.freq + '<br>' + tone.stabledb + '<br>' + tone.age)

  window.requestAnimationFrame = window.webkitRequestAnimationFrame  unless window.requestAnimationFrame
  rafID = window.requestAnimationFrame(updatePitch)
  return


  # possible other approach to confidence: sort the array, take the median; go through the array and compute the average deviation
  autoCorrelate buf, audioContext.sampleRate
  
  #   detectorElem.className = (confidence>50)?"confident":"vague";
  canvasContext.clearRect 0, 0, WIDTH, HEIGHT
  if confidence < 10
    detectorElem.className = "vague"
    pitchElem.innerText = "--"
    noteElem.innerText = "-"
    detuneElem.className = ""
    detuneAmount.innerText = "--"
  else
    detectorElem.className = "confident"
    pitchElem.innerText = Math.floor(currentPitch)
    note = noteFromPitch(currentPitch)
    noteElem.innerHTML = noteStrings[note % 12]
    detune = centsOffFromPitch(currentPitch, note)
    if detune is 0
      detuneElem.className = ""
      detuneAmount.innerHTML = "--"
    
    # TODO: draw a line.
    else
      if Math.abs(detune) < 10
        canvasContext.fillStyle = "green"
      else
        canvasContext.fillStyle = "red"
      if detune < 0
        detuneElem.className = "flat"
      else
        detuneElem.className = "sharp"
      canvasContext.fillRect CENTER, 0, (detune * 3), HEIGHT
      detuneAmount.innerHTML = Math.abs(Math.floor(detune))
  window.requestAnimationFrame = window.webkitRequestAnimationFrame  unless window.requestAnimationFrame
  rafID = window.requestAnimationFrame(updatePitch)
  return


$(document).keydown (evt) ->

