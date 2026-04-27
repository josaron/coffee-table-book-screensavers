sub init()
    m.imgA = m.top.findNode("imgA")
    m.imgB = m.top.findNode("imgB")
    m.crossfade = m.top.findNode("crossfade")
    m.interpOut = m.top.findNode("fadeInterpOut")
    m.interpIn = m.top.findNode("fadeInterpIn")

    m.config = loadConfig()
    m.images = loadImages()

    if m.config.shuffle then shuffleImages()

    m.currentIndex = 0
    m.isFrontA = true
    m.isTransitioning = false

    if m.images.Count() = 0 then return

    ' Show first image: A is front
    m.imgA.uri = m.images[0]
    m.imgA.opacity = 1
    m.imgB.opacity = 0

    if m.images.Count() = 1 then return  ' single image — nothing more to do

    m.crossfade.observeField("state", "onAnimationState")

    m.slideTimer = CreateObject("roSGNode", "Timer")
    m.slideTimer.duration = m.config.displayDuration
    m.slideTimer.repeat = false
    m.slideTimer.observeField("fire", "onSlideTimer")
    m.slideTimer.control = "start"
end sub

' ---------------------------------------------------------------------------
' Config + image list
' ---------------------------------------------------------------------------

function loadConfig() as Object
    config = {
        displayDuration: 10,
        transitionDuration: 1.5,
        shuffle: false
    }
    raw = ReadAsciiFile("pkg:/config/theme.json")
    if raw = "" or raw = invalid then return config
    parsed = ParseJSON(raw)
    if parsed = invalid then return config
    if parsed.displayDuration <> invalid    then config.displayDuration    = parsed.displayDuration
    if parsed.transitionDuration <> invalid then config.transitionDuration = parsed.transitionDuration
    if parsed.shuffle <> invalid            then config.shuffle            = parsed.shuffle
    return config
end function

function loadImages() as Object
    images = []
    raw = ReadAsciiFile("pkg:/config/theme.json")
    if raw = "" or raw = invalid then return images
    parsed = ParseJSON(raw)
    if parsed = invalid or parsed.images = invalid then return images
    for each filename in parsed.images
        images.Push("pkg:/images/" + filename)
    end for
    return images
end function

sub shuffleImages()
    n = m.images.Count()
    for i = n - 1 to 1 step -1
        j = Int(Rnd(0) * (i + 1))  ' Rnd(0) returns float in [0,1)
        tmp = m.images[i]
        m.images[i] = m.images[j]
        m.images[j] = tmp
    end for
end sub

' ---------------------------------------------------------------------------
' Slideshow state machine
' ---------------------------------------------------------------------------

sub onSlideTimer()
    if m.isTransitioning then return
    m.currentIndex = (m.currentIndex + 1) mod m.images.Count()
    preloadNext(m.images[m.currentIndex])
end sub

' Load next image into the back buffer; begin crossfade once loaded.
sub preloadNext(uri as String)
    m.isTransitioning = true
    if m.isFrontA
        m.imgB.uri = uri
        m.imgB.opacity = 0
        m.imgB.observeField("loadStatus", "onBackLoaded")
    else
        m.imgA.uri = uri
        m.imgA.opacity = 0
        m.imgA.observeField("loadStatus", "onBackLoaded")
    end if
end sub

sub onBackLoaded()
    if m.isFrontA
        status = m.imgB.loadStatus
        if status <> "ready" and status <> "failed" then return
        m.imgB.unobserveField("loadStatus")
    else
        status = m.imgA.loadStatus
        if status <> "ready" and status <> "failed" then return
        m.imgA.unobserveField("loadStatus")
    end if
    beginCrossfade()
end sub

sub beginCrossfade()
    m.crossfade.duration = m.config.transitionDuration
    if m.isFrontA
        m.interpOut.fieldToInterp = "imgA.opacity"
        m.interpIn.fieldToInterp  = "imgB.opacity"
    else
        m.interpOut.fieldToInterp = "imgB.opacity"
        m.interpIn.fieldToInterp  = "imgA.opacity"
    end if
    m.isFrontA = not m.isFrontA
    m.crossfade.control = "start"
end sub

sub onAnimationState()
    if m.crossfade.state = "stopped"
        m.isTransitioning = false
        m.slideTimer.control = "start"
    end if
end sub
