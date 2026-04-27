sub init()
    ' Actual display resolution — drives all layout so the channel is correct
    ' on both 1080p (1920×1080) and 4K (3840×2160) Roku devices.
    deviceInfo = CreateObject("roDeviceInfo")
    display    = deviceInfo.GetDisplaySize()
    m.screenW  = display.w
    m.screenH  = display.h

    ' -- fill-screen layout nodes (dimensions set here, not in XML) --
    for each nodeId in ["bg", "imgA", "imgB"]
        n = m.top.findNode(nodeId)
        n.width  = m.screenW
        n.height = m.screenH
    end for

    ' -- crossfade handles --
    m.imgA      = m.top.findNode("imgA")
    m.imgB      = m.top.findNode("imgB")
    m.crossfade = m.top.findNode("crossfade")
    m.interpOut = m.top.findNode("fadeInterpOut")
    m.interpIn  = m.top.findNode("fadeInterpIn")

    ' -- caption: size and position proportional to screen height --
    '    ~33pt / 60px padding at 1080p  →  ~66pt / 120px at 4K
    fontSize  = Int(m.screenH * 0.040)
    padW      = Int(m.screenH * 0.055)
    padH      = Int(m.screenH * 0.065)
    shadowOff = Int(fontSize * 0.12)

    m.captionGroup   = m.top.findNode("captionGroup")
    m.captionText    = m.top.findNode("captionText")
    m.captionShadow  = m.top.findNode("captionShadow")
    m.captionFadeIn  = m.top.findNode("captionFadeIn")
    m.captionFadeOut = m.top.findNode("captionFadeOut")

    m.captionGroup.translation = [padW, m.screenH - fontSize - padH]
    maxLabelW = m.screenW - 2 * padW

    for each nodeId in ["captionText", "captionShadow"]
        n = m.top.findNode(nodeId)
        n.fontSize = fontSize
        n.width    = maxLabelW
    end for
    m.captionShadow.translation = [shadowOff, shadowOff]

    ' -- caption timers --
    m.captionInTimer = CreateObject("roSGNode", "Timer")
    m.captionInTimer.repeat = false
    m.captionInTimer.observeField("fire", "onCaptionIn")

    m.captionOutTimer = CreateObject("roSGNode", "Timer")
    m.captionOutTimer.repeat = false
    m.captionOutTimer.observeField("fire", "onCaptionOut")

    ' -- load content --
    m.config = loadConfig()
    m.images = loadImages()
    if m.config.shuffle then shuffleImages()

    m.currentIndex    = 0
    m.isFrontA        = true
    m.isTransitioning = false
    m.pendingCaption  = ""

    if m.images.Count() = 0 then return

    m.imgA.uri     = m.images[0].uri
    m.imgA.opacity = 1
    m.imgB.opacity = 0

    if m.images.Count() = 1 then return

    m.crossfade.observeField("state", "onAnimationState")

    m.slideTimer = CreateObject("roSGNode", "Timer")
    m.slideTimer.duration = m.config.displayDuration
    m.slideTimer.repeat   = false
    m.slideTimer.observeField("fire", "onSlideTimer")
    m.slideTimer.control = "start"

    showCaption(m.images[0].caption)
end sub

' ---------------------------------------------------------------------------
' Config + image list
' ---------------------------------------------------------------------------

function loadConfig() as Object
    config = {
        displayDuration:    10,
        transitionDuration: 1.5,
        shuffle:            false
    }
    raw = ReadAsciiFile("pkg:/config/theme.json")
    if raw = "" or raw = invalid then return config
    parsed = ParseJSON(raw)
    if parsed = invalid then return config
    if parsed.displayDuration    <> invalid then config.displayDuration    = parsed.displayDuration
    if parsed.transitionDuration <> invalid then config.transitionDuration = parsed.transitionDuration
    if parsed.shuffle            <> invalid then config.shuffle            = parsed.shuffle
    return config
end function

' Returns array of { uri: String, caption: String }.
' Accepts both legacy string arrays and new object arrays in theme.json.
function loadImages() as Object
    images = []
    raw = ReadAsciiFile("pkg:/config/theme.json")
    if raw = "" or raw = invalid then return images
    parsed = ParseJSON(raw)
    if parsed = invalid or parsed.images = invalid then return images
    for each entry in parsed.images
        if type(entry) = "roString" or type(entry) = "String"
            images.Push({ uri: "pkg:/images/" + entry, caption: "" })
        else if entry.filename <> invalid
            caption = ""
            if entry.caption <> invalid then caption = entry.caption
            images.Push({ uri: "pkg:/images/" + entry.filename, caption: caption })
        end if
    end for
    return images
end function

sub shuffleImages()
    n = m.images.Count()
    for i = n - 1 to 1 step -1
        j = Int(Rnd(0) * (i + 1))
        tmp = m.images[i]
        m.images[i] = m.images[j]
        m.images[j] = tmp
    end for
end sub

' ---------------------------------------------------------------------------
' Caption
' ---------------------------------------------------------------------------

' Stops any in-flight caption timers, then schedules fade-in at t+2s and
' fade-out at t+(displayDuration-2)s. No-ops if text is empty or slide is short.
sub showCaption(text as String)
    m.captionInTimer.control  = "stop"
    m.captionOutTimer.control = "stop"
    m.captionGroup.opacity = 0

    if text = "" or text = invalid then return
    if m.config.displayDuration < 5 then return

    m.captionText.text   = text
    m.captionShadow.text = text

    m.captionInTimer.duration  = 2.0
    m.captionOutTimer.duration = m.config.displayDuration - 2.0
    m.captionInTimer.control  = "start"
    m.captionOutTimer.control = "start"
end sub

sub onCaptionIn()
    m.captionFadeIn.control = "start"
end sub

sub onCaptionOut()
    m.captionFadeOut.control = "start"
end sub

' ---------------------------------------------------------------------------
' Slideshow state machine
' ---------------------------------------------------------------------------

sub onSlideTimer()
    if m.isTransitioning then return

    ' Kill caption immediately so it doesn't linger into the crossfade
    m.captionInTimer.control  = "stop"
    m.captionOutTimer.control = "stop"
    m.captionGroup.opacity = 0

    m.currentIndex = (m.currentIndex + 1) mod m.images.Count()
    img = m.images[m.currentIndex]
    m.pendingCaption = img.caption
    preloadNext(img.uri)
end sub

sub preloadNext(uri as String)
    m.isTransitioning = true
    if m.isFrontA
        m.imgB.uri     = uri
        m.imgB.opacity = 0
        m.imgB.observeField("loadStatus", "onBackLoaded")
    else
        m.imgA.uri     = uri
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
        showCaption(m.pendingCaption)
        m.slideTimer.control = "start"
    end if
end sub
